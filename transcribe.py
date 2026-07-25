#!/usr/bin/env python3
r"""批量转录视频生成中文字幕 SRT。

用法:
    # 全量跑（跳过已存在的 srt）
    .venv\Scripts\python.exe transcribe.py

    # 单文件测试
    .venv\Scripts\python.exe transcribe.py --file "<视频路径>"

    # 只跑前 N 个
    .venv\Scripts\python.exe transcribe.py --limit 3

    # 强制覆盖已有 srt
    .venv\Scripts\python.exe transcribe.py --force

    # 本地写完后同步推送一份到云端(P盘视频同目录)
    .venv\Scripts\python.exe transcribe.py --push-cloud
"""
from __future__ import annotations

import argparse
import logging
import sys
import time
from pathlib import Path

from faster_whisper import WhisperModel

# ─────────────────────────── 配置 ───────────────────────────
SRC_ROOT = Path(
    r"P:\CloudMedia\Video\网课\03.【2027考研数学】张宇等启航专属班！"
    r"\01.（七期）2027考研数学一、二、三\04.基础阶段\01.基础30讲-高数"
)
DST_ROOT = Path(r"D:\Code\Video2Srt\subs")
MODEL_BASE = Path(
    r"C:\Users\550W\AppData\Local\Buzz\Buzz\Cache\models"
    r"\models--Systran--faster-whisper-large-v2"
)
LOG_FILE = Path(r"D:\Code\Video2Srt\progress.log")
CLOUD_FAILED = Path(r"D:\Code\Video2Srt\cloud_failed.txt")

INITIAL_PROMPT = "以下是普通话的句子。"

# 断句参数
MAX_SENT_DUR = 7.0       # 句时长高于此 -> 拆分
MAX_CHARS_PER_LINE = 20  # 单行最大字数，超出则换行
MAX_CHARS_PER_SENT = MAX_CHARS_PER_LINE * 2  # 句字数上限，超出则拆分
GAP_THRESHOLD = 0.8      # segment 间隔超过此(秒)视为自然停顿 -> 断句

SENT_END_MARKS = set("。！？；!?;")
SENT_PAUSE_MARKS = set("，、：,:")

# 半角标点 -> 全角（中文排版规范；只转安全的，不转句号防误伤小数点/版本号）
_PUNCT_MAP = str.maketrans({",": "，", ";": "；"})

# 重试参数（应对夸克网盘/WebDAV 不稳定）
RETRY_WAIT = 60     # P盘不可用时每次等待秒数
RETRY_TIMES = 10    # P盘不可用时最多重试次数
IO_RETRY = 3        # 单个视频/推送 IO 失败重试次数
IO_RETRY_DELAY = 30  # 单次重试间隔


# ─────────────────────────── 工具 ───────────────────────────
def fmt_ts(sec: float) -> str:
    if sec < 0:
        sec = 0.0
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    ms = int(round((sec - int(sec)) * 1000))
    if ms == 1000:
        ms = 0
        s += 1
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def find_model_path() -> str:
    snapshots = MODEL_BASE / "snapshots"
    if not snapshots.exists():
        raise FileNotFoundError(f"模型 snapshots 目录不存在: {snapshots}")
    for d in sorted(snapshots.iterdir()):
        if (d / "model.bin").exists() and (d / "config.json").exists():
            return str(d)
    raise FileNotFoundError(f"未在 {snapshots} 下找到完整模型")


def build_model() -> WhisperModel:
    return WhisperModel(
        find_model_path(),
        device="cuda",
        compute_type="float16",
    )


def normalize_punct(text: str) -> str:
    return text.translate(_PUNCT_MAP)


def with_retry(fn, *, desc: str = "", max_retries: int = IO_RETRY,
               base_delay: int = IO_RETRY_DELAY, log=None):
    """对不稳定操作（WebDAV 读写）做重试。最后一次仍失败则抛异常。"""
    for attempt in range(1, max_retries + 1):
        try:
            return fn()
        except Exception as e:
            if attempt >= max_retries:
                raise
            if log:
                log.warning(f"{desc} 第{attempt}/{max_retries}次失败: {e}，{base_delay}秒后重试")
            time.sleep(base_delay)
    # unreachable
    return None


# ─────────────────────────── 转录 ───────────────────────────
def transcribe_one(model: WhisperModel, video_path: Path):
    segments, _info = model.transcribe(
        str(video_path),
        language="zh",
        task="transcribe",
        beam_size=5,
        vad_filter=True,
        vad_parameters=dict(
            min_silence_duration_ms=500,
            speech_pad_ms=200,
        ),
        word_timestamps=True,
        initial_prompt=INITIAL_PROMPT,
    )
    return list(segments)


# ─────────────────────────── 中文断句重组 ───────────────────────────
# 策略：以 Whisper 的 segment 为基础单位，按"句末标点 / 大停顿"切句，
# 不靠字数硬切（避免在词中间断开）；得到的句子若仍过长，再按逗号优先拆分。
class _W:
    __slots__ = ("word", "start", "end")

    def __init__(self, word, start, end):
        self.word = word
        self.start = start
        self.end = end


def _seg_words(seg):
    if seg.words:
        return list(seg.words)
    return [_W(seg.text, seg.start, seg.end)]


def _split_words(words):
    """把一组 word 拆成多个子句，每个子句不超过 MAX_CHARS_PER_SENT 字。
    优先在停顿标点(逗号)处切 -> 不切词；无标点超长才按字数硬切。"""
    # 1) 按停顿标点切
    sub = []
    cur = []
    for w in words:
        cur.append(w)
        if w.word and w.word[-1] in SENT_PAUSE_MARKS:
            sub.append(cur)
            cur = []
    if cur:
        sub.append(cur)

    # 2) 合并过短子句（合并后不超过 MAX_CHARS_PER_SENT）
    merged = []
    for s in sub:
        s_len = sum(len(w.word) for w in s)
        if merged:
            prev_len = sum(len(w.word) for w in merged[-1])
            if prev_len + s_len <= MAX_CHARS_PER_SENT:
                merged[-1].extend(s)
                continue
        merged.append(list(s))

    # 3) 仍超长的子句 -> 按字数硬切（兜底，少见）
    refined = []
    for s in merged:
        s_len = sum(len(w.word) for w in s)
        if s_len <= MAX_CHARS_PER_SENT:
            refined.append(s)
        else:
            acc = []
            acc_len = 0
            for w in s:
                acc.append(w)
                acc_len += len(w.word)
                if acc_len >= MAX_CHARS_PER_SENT:
                    refined.append(acc)
                    acc = []
                    acc_len = 0
            if acc:
                if refined and sum(len(w.word) for w in acc) < MAX_CHARS_PER_LINE:
                    refined[-1].extend(acc)
                else:
                    refined.append(acc)
    return refined or [words]


def reflow(segments):
    """重组为自然中文句子。返回 [(text, start, end), ...]"""
    segs = []
    for s in segments:
        ws = _seg_words(s)
        text = "".join(w.word for w in ws).strip()
        if text:
            segs.append((text, s.start, s.end, ws))

    if not segs:
        return []

    # 第一阶段：只在"句末标点 / 大停顿"处断句，不按字数硬切
    sentences = []
    cur_t, cur_s, cur_e, cur_w = segs[0]
    cur_w = list(cur_w)
    for text, s, e, ws in segs[1:]:
        gap = s - cur_e
        ends_sent = cur_t and cur_t[-1] in SENT_END_MARKS
        big_gap = gap > GAP_THRESHOLD
        if ends_sent or big_gap:
            sentences.append((cur_t, cur_s, cur_e, cur_w))
            cur_t, cur_s, cur_e, cur_w = text, s, e, list(ws)
        else:
            cur_t += text
            cur_e = e
            cur_w.extend(ws)
    sentences.append((cur_t, cur_s, cur_e, cur_w))

    # 第二阶段：过长句按逗号优先拆分
    final = []
    for t, s, e, ws in sentences:
        if len(t) > MAX_CHARS_PER_SENT or (e - s) > MAX_SENT_DUR:
            for sub in _split_words(ws):
                st = "".join(w.word for w in sub).strip()
                if not st:
                    continue
                ss = max(0.0, sub[0].start)
                se = sub[-1].end
                if se <= ss:
                    se = ss + 0.3
                final.append((st, ss, se))
        else:
            final.append((t, max(0.0, s), e))
    return final


# ─────────────────────────── SRT 输出 ───────────────────────────
def _wrap_line(text: str) -> str:
    if len(text) <= MAX_CHARS_PER_LINE:
        return text
    mid = len(text) // 2
    best = mid
    for offset in range(min(6, len(text) // 2)):
        for pos in (mid - offset, mid + offset):
            if 0 <= pos < len(text) and text[pos] in SENT_PAUSE_MARKS:
                best = pos + 1
                break
        else:
            continue
        break
    return text[:best] + "\n" + text[best:]


def write_srt(sentences, path: Path):
    lines = []
    for i, (text, start, end) in enumerate(sentences, 1):
        text = normalize_punct(text)
        lines.append(str(i))
        lines.append(f"{fmt_ts(start)} --> {fmt_ts(end)}")
        lines.append(_wrap_line(text))
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


# ─────────────────────────── 云端推送 ───────────────────────────
def cloud_push(local_srt: Path, src_video: Path, log):
    """把本地 srt 复制到云端视频同目录（同名 .srt）。失败记录到 cloud_failed.txt。"""
    cloud_srt = src_video.with_suffix(".srt")
    data = local_srt.read_bytes()

    def _write():
        cloud_srt.write_bytes(data)

    try:
        with_retry(_write, desc=f"推送 {cloud_srt.name}", log=log)
        return True
    except Exception as e:
        log.error(f"  云端推送失败: {e}")
        with open(CLOUD_FAILED, "a", encoding="utf-8") as f:
            f.write(f"{local_srt}\t{cloud_srt}\n")
        return False


# ─────────────────────────── 主流程 ───────────────────────────
def setup_logging():
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("srt")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s", "%H:%M:%S")
    fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
    fh.setFormatter(fmt)
    logger.addHandler(fh)
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    logger.addHandler(sh)
    return logger


def find_videos(log, single: str | None = None, limit: int | None = None):
    """扫描视频；P盘不可用时等待重试。"""
    if single:
        return [Path(single)]
    for attempt in range(1, RETRY_TIMES + 1):
        videos = sorted(SRC_ROOT.rglob("*.mp4"))
        if videos:
            if limit:
                videos = videos[:limit]
            return videos
        log.warning(f"P盘暂无视频（WebDAV可能未恢复），{RETRY_WAIT}秒后重试 {attempt}/{RETRY_TIMES}")
        time.sleep(RETRY_WAIT)
    log.error(f"P盘等待 {RETRY_TIMES} 次仍不可用，退出。")
    return []


def process_one(model, v: Path, srt: Path, log):
    """转录单个视频（带重试）。返回 (sentences, 耗时)。"""
    def _do():
        segments = transcribe_one(model, v)
        sentences = reflow(segments)
        write_srt(sentences, srt)
        return sentences

    t0 = time.time()
    sentences = with_retry(_do, desc=f"转录 {v.name}", log=log)
    return sentences, time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="只处理单个视频文件")
    ap.add_argument("--limit", type=int, help="只处理前 N 个")
    ap.add_argument("--force", action="store_true", help="覆盖已有 srt")
    ap.add_argument("--push-cloud", action="store_true",
                    help="本地写完后同步推送一份到云端(P盘视频同目录)")
    args = ap.parse_args()

    log = setup_logging()
    DST_ROOT.mkdir(parents=True, exist_ok=True)
    if args.push_cloud:
        log.info("已开启云端推送：每个视频完成后同步到 P 盘")

    videos = find_videos(log, args.file, args.limit)
    if not videos:
        return
    log.info(f"共 {len(videos)} 个视频待处理。加载模型…")
    model = build_model()
    log.info("模型就绪。开始转录。")

    ok = fail = skip = pushed = 0
    for i, v in enumerate(videos, 1):
        try:
            rel = v.relative_to(SRC_ROOT)
        except ValueError:
            rel = v
        srt = DST_ROOT / rel.with_suffix(".srt")
        if srt.exists() and not args.force:
            # 已存在但云端没有时，若开启推送则补推
            if args.push_cloud:
                cloud_srt = v.with_suffix(".srt")
                if not cloud_srt.exists():
                    if cloud_push(srt, v, log):
                        pushed += 1
            log.info(f"[{i}/{len(videos)}] SKIP {rel}")
            skip += 1
            continue
        srt.parent.mkdir(parents=True, exist_ok=True)

        try:
            sentences, dt = process_one(model, v, srt, log)
            ok += 1
            msg = (f"[{i}/{len(videos)}] OK  {len(sentences):3d}句 "
                   f"{dt:6.1f}s  {rel.name}")
            if args.push_cloud:
                if cloud_push(srt, v, log):
                    pushed += 1
                    msg += "  [已推云]"
            log.info(msg)
        except Exception as e:
            fail += 1
            log.error(f"[{i}/{len(videos)}] FAIL {rel.name}: {e}")

    log.info(f"完成。成功 {ok} 失败 {fail} 跳过 {skip}"
             + (f" 推云 {pushed}" if args.push_cloud else ""))
    if CLOUD_FAILED.exists() and CLOUD_FAILED.stat().st_size > 0:
        log.info(f"部分云端推送失败，见 {CLOUD_FAILED}")


if __name__ == "__main__":
    main()
