#!/usr/bin/env python3
r"""批量转录视频生成中文字幕 SRT。

常用命令:
    # 全量跑（跳过已存在且格式可解析的 srt）
    .venv\Scripts\python.exe transcribe.py

    # 单文件测试
    .venv\Scripts\python.exe transcribe.py --file "<视频路径>"

    # 只跑前 N 个
    .venv\Scripts\python.exe transcribe.py --limit 3

    # 强制覆盖已有 srt
    .venv\Scripts\python.exe transcribe.py --force

    # 本地写完后同步推送一份到云端(P盘视频同目录)
    .venv\Scripts\python.exe transcribe.py --push-cloud

    # 只修复已有字幕的时间轴、换行和少量重复毛边，不重新转录
    .venv\Scripts\python.exe transcribe.py --repair-existing
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import shutil
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from faster_whisper import WhisperModel


PROGRESS_PREFIX = "__VIDEO2SRT_PROGRESS__ "
PROJECT_ROOT = Path(__file__).resolve().parent
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "config.json"

DEFAULT_SRC_ROOT = Path(
    r"P:\CloudMedia\Video\网课\03.【2027考研数学】张宇等启航专属班！"
    r"\01.（七期）2027考研数学一、二、三\04.基础阶段\01.基础30讲-高数"
)
DEFAULT_MODEL_BASE = Path(
    r"C:\Users\550W\AppData\Local\Buzz\Buzz\Cache\models"
    r"\models--Systran--faster-whisper-large-v2"
)

SENT_END_MARKS = set("。！？；!?;")
SENT_PAUSE_MARKS = set("，、：,:")
WRAP_MARKS = SENT_END_MARKS | SENT_PAUSE_MARKS

# 半角标点 -> 全角（不转句号，避免误伤小数点/版本号）
_PUNCT_MAP = str.maketrans({",": "，", ";": "；", ":": "："})
_TS_RE = re.compile(
    r"^(\d\d):(\d\d):(\d\d),(\d\d\d)\s+-->\s+"
    r"(\d\d):(\d\d):(\d\d),(\d\d\d)$"
)


@dataclass
class AppConfig:
    src_root: Path = DEFAULT_SRC_ROOT
    dst_root: Path = PROJECT_ROOT
    model_base: Path = DEFAULT_MODEL_BASE
    log_file: Path = PROJECT_ROOT / "progress.log"
    cloud_failed: Path = PROJECT_ROOT / "cloud_failed.txt"
    cache_dir: Path = PROJECT_ROOT / ".cache" / "videos"

    video_extensions: list[str] = field(default_factory=lambda: [".mp4"])
    preserve_source_root_name: bool = True
    use_local_cache: bool = True
    delete_cache_after: bool = True

    device: str = "cuda"
    compute_type: str = "float16"
    language: str = "zh"
    task: str = "transcribe"
    beam_size: int = 5
    temperature: float = 0.0
    condition_on_previous_text: bool = False
    compression_ratio_threshold: float | None = 2.4
    log_prob_threshold: float | None = -1.0
    no_speech_threshold: float | None = 0.6
    hallucination_silence_threshold: float | None = 1.0
    initial_prompt: str = "以下是普通话的句子。"

    vad_min_silence_duration_ms: int = 420
    vad_speech_pad_ms: int = 200

    max_sentence_duration: float = 5.5
    max_chars_per_line: int = 18
    max_chars_per_sentence: int = 32
    gap_threshold: float = 0.55
    min_caption_duration: float = 0.35
    min_caption_gap: float = 0.01

    retry_wait: int = 60
    retry_times: int = 10
    io_retry: int = 3
    io_retry_delay: int = 30


PATH_FIELDS = {
    "src_root",
    "dst_root",
    "model_base",
    "log_file",
    "cloud_failed",
    "cache_dir",
}


class _W:
    __slots__ = ("word", "start", "end")

    def __init__(self, word: str, start: float, end: float):
        self.word = word
        self.start = start
        self.end = end


def _resolve_path(value: Any, base_dir: Path) -> Path:
    raw = os.path.expandvars(str(value))
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = base_dir / path
    return path.resolve(strict=False)


def normalize_config(cfg: AppConfig) -> AppConfig:
    cfg.video_extensions = [
        ext if ext.startswith(".") else f".{ext}" for ext in cfg.video_extensions
    ]
    cfg.max_chars_per_line = max(8, int(cfg.max_chars_per_line))
    cfg.max_chars_per_sentence = max(
        cfg.max_chars_per_line, int(cfg.max_chars_per_sentence)
    )
    cfg.min_caption_duration = max(0.1, float(cfg.min_caption_duration))
    cfg.min_caption_gap = max(0.0, float(cfg.min_caption_gap))
    return cfg


def config_to_dict(cfg: AppConfig) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for name, value in cfg.__dict__.items():
        if isinstance(value, Path):
            out[name] = str(value)
        else:
            out[name] = value
    return out


def load_config(path: Path) -> AppConfig:
    cfg = AppConfig()
    if not path.exists():
        return normalize_config(cfg)

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"配置文件必须是 JSON 对象: {path}")

    base_dir = path.resolve(strict=False).parent
    valid_keys = set(cfg.__dict__)
    for key, value in data.items():
        if key not in valid_keys:
            continue
        if key in PATH_FIELDS:
            setattr(cfg, key, _resolve_path(value, base_dir))
        else:
            setattr(cfg, key, value)
    return normalize_config(cfg)


def write_default_config(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cfg = normalize_config(AppConfig())
    path.write_text(
        json.dumps(config_to_dict(cfg), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def apply_cli_overrides(cfg: AppConfig, args: argparse.Namespace) -> AppConfig:
    for attr in ("src_root", "dst_root", "model_base", "cache_dir"):
        value = getattr(args, attr, None)
        if value:
            setattr(cfg, attr, _resolve_path(value, Path.cwd()))

    for attr in (
        "device",
        "compute_type",
        "max_chars_per_line",
        "max_chars_per_sentence",
        "gap_threshold",
        "max_sentence_duration",
    ):
        value = getattr(args, attr, None)
        if value is not None:
            setattr(cfg, attr, value)

    if args.no_local_cache:
        cfg.use_local_cache = False
    if args.keep_cache:
        cfg.delete_cache_after = False
    if args.no_preserve_source_root:
        cfg.preserve_source_root_name = False
    return normalize_config(cfg)


def fmt_ts(sec: float) -> str:
    total_ms = max(0, int(round(sec * 1000)))
    total_s, ms = divmod(total_ms, 1000)
    total_m, s = divmod(total_s, 60)
    h, m = divmod(total_m, 60)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def parse_ts(text: str) -> float:
    h, m, s_ms = text.split(":")
    s, ms = s_ms.split(",")
    total_ms = (
        ((int(h) * 60 + int(m)) * 60 + int(s)) * 1000 + int(ms)
    )
    return total_ms / 1000


def normalize_caption_text(text: str) -> str:
    text = text.replace("\ufffd", "")
    text = text.translate(_PUNCT_MAP)
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def with_retry(
    fn,
    *,
    desc: str = "",
    max_retries: int = 3,
    base_delay: int = 30,
    log: logging.Logger | None = None,
):
    """对不稳定操作做重试。最后一次仍失败则抛异常。"""
    for attempt in range(1, max_retries + 1):
        try:
            return fn()
        except Exception as e:
            if attempt >= max_retries:
                raise
            if log:
                log.warning(
                    f"{desc} 第{attempt}/{max_retries}次失败: {e}，"
                    f"{base_delay}秒后重试"
                )
            time.sleep(base_delay)
    return None


def find_model_path(cfg: AppConfig) -> str:
    if (cfg.model_base / "model.bin").exists() and (
        cfg.model_base / "config.json"
    ).exists():
        return str(cfg.model_base)

    snapshots = cfg.model_base / "snapshots"
    if not snapshots.exists():
        raise FileNotFoundError(f"模型 snapshots 目录不存在: {snapshots}")
    for d in sorted(snapshots.iterdir()):
        if (d / "model.bin").exists() and (d / "config.json").exists():
            return str(d)
    raise FileNotFoundError(f"未在 {snapshots} 下找到完整模型")


def build_model(cfg: AppConfig) -> WhisperModel:
    return WhisperModel(
        find_model_path(cfg),
        device=cfg.device,
        compute_type=cfg.compute_type,
    )


def emit_progress(enabled: bool, event: str, **payload) -> None:
    if not enabled:
        return
    data = {"event": event, **payload}
    print(PROGRESS_PREFIX + json.dumps(data, ensure_ascii=False), flush=True)


def transcribe_one(
    model: WhisperModel,
    video_path: Path,
    cfg: AppConfig,
    progress_cb=None,
):
    segments, _info = model.transcribe(
        str(video_path),
        language=cfg.language,
        task=cfg.task,
        beam_size=cfg.beam_size,
        temperature=cfg.temperature,
        condition_on_previous_text=cfg.condition_on_previous_text,
        compression_ratio_threshold=cfg.compression_ratio_threshold,
        log_prob_threshold=cfg.log_prob_threshold,
        no_speech_threshold=cfg.no_speech_threshold,
        hallucination_silence_threshold=cfg.hallucination_silence_threshold,
        vad_filter=True,
        vad_parameters=dict(
            min_silence_duration_ms=cfg.vad_min_silence_duration_ms,
            speech_pad_ms=cfg.vad_speech_pad_ms,
        ),
        word_timestamps=True,
        initial_prompt=cfg.initial_prompt,
    )
    duration = float(getattr(_info, "duration", 0.0) or 0.0)
    out = []
    last_percent = -1
    last_emit = 0.0
    for seg in segments:
        out.append(seg)
        if progress_cb and duration > 0:
            percent = max(0, min(100, int((float(seg.end) / duration) * 100)))
            now = time.time()
            if percent != last_percent and (
                percent >= last_percent + 2 or now - last_emit >= 1.5
            ):
                progress_cb(percent, float(seg.end), duration)
                last_percent = percent
                last_emit = now
    if progress_cb:
        progress_cb(100, duration, duration)
    return out


def _word_text(word) -> str:
    return normalize_caption_text(str(getattr(word, "word", "")))


def _word_start(word) -> float:
    return float(getattr(word, "start", 0.0) or 0.0)


def _word_end(word) -> float:
    return float(getattr(word, "end", _word_start(word)) or _word_start(word))


def _words_text(words) -> str:
    return "".join(_word_text(w) for w in words).strip()


def _words_len(words) -> int:
    return len(_words_text(words))


def _words_duration(words) -> float:
    if not words:
        return 0.0
    return max(0.0, _word_end(words[-1]) - _word_start(words[0]))


def _find_split_pos(text: str, max_len: int) -> int:
    if len(text) <= max_len:
        return len(text)
    limit = min(max_len, len(text))
    left = max(1, limit - 8)
    for pos in range(limit, left - 1, -1):
        if text[pos - 1] in WRAP_MARKS:
            return pos
    for pos in range(limit, left - 1, -1):
        if text[pos - 1].isspace():
            return pos
    return limit


def _split_text_chunks(text: str, max_len: int) -> list[str]:
    text = normalize_caption_text(text)
    chunks: list[str] = []
    while len(text) > max_len:
        pos = _find_split_pos(text, max_len)
        chunks.append(text[:pos].strip())
        text = text[pos:].strip()
    if text:
        chunks.append(text)
    return [c for c in chunks if c]


def _split_plain_subtitle(
    text: str, start: float, end: float, cfg: AppConfig
) -> list[tuple[str, float, float]]:
    chunks = _split_text_chunks(text, cfg.max_chars_per_sentence)
    if len(chunks) <= 1:
        return [(text, start, end)]

    duration = max(end - start, cfg.min_caption_duration * len(chunks))
    total_chars = sum(len(c) for c in chunks) or len(chunks)
    out = []
    cursor = start
    for i, chunk in enumerate(chunks, 1):
        if i == len(chunks):
            chunk_end = start + duration
        else:
            chunk_end = cursor + duration * (len(chunk) / total_chars)
        if chunk_end <= cursor:
            chunk_end = cursor + cfg.min_caption_duration
        out.append((chunk, cursor, chunk_end))
        cursor = chunk_end
    return out


def _split_oversized_word(word, cfg: AppConfig):
    text = _word_text(word)
    if len(text) <= cfg.max_chars_per_sentence:
        return [word]

    chunks = _split_text_chunks(text, cfg.max_chars_per_sentence)
    start = _word_start(word)
    end = max(_word_end(word), start + cfg.min_caption_duration * len(chunks))
    duration = end - start
    out = []
    for i, chunk in enumerate(chunks):
        chunk_start = start + duration * (i / len(chunks))
        chunk_end = start + duration * ((i + 1) / len(chunks))
        out.append(_W(chunk, chunk_start, chunk_end))
    return out


def _seg_words(seg, cfg: AppConfig):
    words = [w for w in list(getattr(seg, "words", None) or []) if _word_text(w)]
    if words:
        out = []
        for w in words:
            out.extend(_split_oversized_word(w, cfg))
        return out
    return [_W(str(getattr(seg, "text", "")), seg.start, seg.end)]


def _split_words(words, cfg: AppConfig):
    """按停顿、时长和字数拆分 word 列表，尽量不在词中间断开。"""
    expanded = []
    for w in words:
        expanded.extend(_split_oversized_word(w, cfg))

    chunks = []
    cur = []
    for w in expanded:
        cur.append(w)
        word = _word_text(w)
        reached_pause = bool(word and word[-1] in SENT_PAUSE_MARKS)
        reached_len = _words_len(cur) >= cfg.max_chars_per_sentence
        reached_duration = (
            len(cur) > 1 and _words_duration(cur) >= cfg.max_sentence_duration
        )
        if reached_pause or reached_len or reached_duration:
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)

    merged = []
    for chunk in chunks:
        if not chunk:
            continue
        if merged:
            candidate = merged[-1] + chunk
            if (
                _words_len(candidate) <= cfg.max_chars_per_sentence
                and _words_duration(candidate) <= cfg.max_sentence_duration
            ):
                merged[-1].extend(chunk)
                continue
        merged.append(list(chunk))
    return merged or [expanded]


def reflow(segments, cfg: AppConfig):
    """重组为自然中文句子。返回 [(text, start, end), ...]"""
    segs = []
    for s in segments:
        ws = _seg_words(s, cfg)
        text = _words_text(ws)
        if text:
            segs.append((text, float(s.start), float(s.end), ws))

    if not segs:
        return []

    sentences = []
    cur_t, cur_s, cur_e, cur_w = segs[0]
    cur_w = list(cur_w)
    for text, s, e, ws in segs[1:]:
        gap = s - cur_e
        ends_sent = cur_t and cur_t[-1] in SENT_END_MARKS
        big_gap = gap > cfg.gap_threshold
        too_long = (
            len(cur_t) >= cfg.max_chars_per_sentence
            or (cur_e - cur_s) >= cfg.max_sentence_duration
        )
        soft_pause = cur_t and cur_t[-1] in SENT_PAUSE_MARKS

        if ends_sent or big_gap or (too_long and soft_pause):
            sentences.append((cur_t, cur_s, cur_e, cur_w))
            cur_t, cur_s, cur_e, cur_w = text, s, e, list(ws)
        else:
            cur_t += text
            cur_e = e
            cur_w.extend(ws)
    sentences.append((cur_t, cur_s, cur_e, cur_w))

    final = []
    for text, start, end, words in sentences:
        if (
            len(text) > cfg.max_chars_per_sentence
            or (end - start) > cfg.max_sentence_duration
        ):
            for sub in _split_words(words, cfg):
                sub_text = _words_text(sub)
                if not sub_text:
                    continue
                sub_start = max(0.0, _word_start(sub[0]))
                sub_end = _word_end(sub[-1])
                if sub_end <= sub_start:
                    sub_end = sub_start + cfg.min_caption_duration
                final.append((sub_text, sub_start, sub_end))
        else:
            final.append((text, max(0.0, start), end))
    return prepare_subtitles(final, cfg)


def _compare_text(text: str) -> str:
    return re.sub(r"[\s，。！？；：、,.!?;:]+", "", text).lower()


def _same_time(a, b) -> bool:
    return abs(a[1] - b[1]) < 0.05 and abs(a[2] - b[2]) < 0.05


def _looks_like_duplicate(a_text: str, b_text: str) -> bool:
    a = _compare_text(a_text)
    b = _compare_text(b_text)
    if not a or not b:
        return False
    return a == b or a in b or b in a


def prepare_subtitles(
    sentences, cfg: AppConfig
) -> list[tuple[str, float, float]]:
    expanded: list[tuple[str, float, float]] = []
    for text, start, end in sentences:
        text = normalize_caption_text(text)
        if not text:
            continue
        start = max(0.0, float(start))
        end = max(float(end), start + cfg.min_caption_duration)
        if len(text) > cfg.max_chars_per_sentence:
            expanded.extend(_split_plain_subtitle(text, start, end, cfg))
        else:
            expanded.append((text, start, end))

    expanded.sort(key=lambda item: (item[1], item[2], item[0]))
    cleaned: list[tuple[str, float, float]] = []
    for text, start, end in expanded:
        current = (text, start, end)
        if cleaned and _same_time(cleaned[-1], current) and _looks_like_duplicate(
            cleaned[-1][0], text
        ):
            prev_text, prev_start, prev_end = cleaned[-1]
            keep_text = min((prev_text, text), key=lambda s: len(_compare_text(s)))
            cleaned[-1] = (keep_text, prev_start, prev_end)
            continue

        if cleaned:
            prev_text, prev_start, prev_end = cleaned[-1]
            min_start = prev_end + cfg.min_caption_gap
            if start < min_start:
                start = min_start
            if end <= start:
                end = start + cfg.min_caption_duration
        cleaned.append((text, start, end))
    return cleaned


def _wrap_line(text: str, cfg: AppConfig) -> str:
    return "\n".join(_split_text_chunks(text, cfg.max_chars_per_line))


def write_srt(sentences, path: Path, cfg: AppConfig):
    prepared = prepare_subtitles(sentences, cfg)
    lines = []
    for i, (text, start, end) in enumerate(prepared, 1):
        lines.append(str(i))
        lines.append(f"{fmt_ts(start)} --> {fmt_ts(end)}")
        lines.append(_wrap_line(text, cfg))
        lines.append("")

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text("\n".join(lines), encoding="utf-8")
    tmp.replace(path)
    return prepared


def parse_srt(path: Path) -> list[tuple[str, float, float]]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    entries: list[tuple[str, float, float]] = []
    i = 0
    while i < len(lines):
        while i < len(lines) and not lines[i].strip():
            i += 1
        if i >= len(lines):
            break
        if not lines[i].strip().isdigit():
            raise ValueError(f"{path}:{i + 1} 不是字幕序号")
        i += 1
        if i >= len(lines):
            raise ValueError(f"{path}:{i + 1} 缺少时间轴")
        match = _TS_RE.match(lines[i].strip())
        if not match:
            raise ValueError(f"{path}:{i + 1} 时间轴格式错误")
        start = parse_ts(":".join(match.groups()[0:3]) + "," + match.group(4))
        end = parse_ts(":".join(match.groups()[4:7]) + "," + match.group(8))
        i += 1
        text_lines = []
        while i < len(lines) and lines[i].strip():
            text_lines.append(lines[i].strip())
            i += 1
        text = normalize_caption_text("".join(text_lines))
        if text:
            entries.append((text, start, end))
    return entries


def is_srt_usable(path: Path) -> bool:
    try:
        return bool(parse_srt(path))
    except Exception:
        return False


def repair_srt_file(path: Path, cfg: AppConfig) -> int:
    entries = parse_srt(path)
    fixed = write_srt(entries, path, cfg)
    return len(fixed)


def cloud_push(local_srt: Path, src_video: Path, cfg: AppConfig, log):
    """把本地 srt 复制到云端视频同目录（同名 .srt）。失败记录到 cloud_failed。"""
    cloud_srt = src_video.with_suffix(".srt")
    data = local_srt.read_bytes()

    def _write():
        cloud_srt.write_bytes(data)

    try:
        with_retry(
            _write,
            desc=f"推送 {cloud_srt.name}",
            max_retries=cfg.io_retry,
            base_delay=cfg.io_retry_delay,
            log=log,
        )
        return True
    except Exception as e:
        log.error(f"  云端推送失败: {e}")
        cfg.cloud_failed.parent.mkdir(parents=True, exist_ok=True)
        with open(cfg.cloud_failed, "a", encoding="utf-8") as f:
            f.write(f"{local_srt}\t{cloud_srt}\n")
        return False


def setup_logging(cfg: AppConfig):
    cfg.log_file.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("srt")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s", "%H:%M:%S")
    fh = logging.FileHandler(cfg.log_file, encoding="utf-8")
    fh.setFormatter(fmt)
    logger.addHandler(fh)
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    logger.addHandler(sh)
    return logger


def find_videos(log, cfg: AppConfig, single: str | None = None, limit: int | None = None):
    """扫描视频；P盘不可用时等待重试。"""
    if single:
        return [_resolve_path(single, Path.cwd())]

    for attempt in range(1, cfg.retry_times + 1):
        try:
            videos = []
            for ext in cfg.video_extensions:
                videos.extend(cfg.src_root.rglob(f"*{ext}"))
            videos = sorted(set(videos), key=lambda p: str(p).lower())
        except Exception as e:
            videos = []
            log.warning(f"扫描视频失败: {e}")

        if videos:
            if limit is not None:
                videos = videos[:limit]
            return videos
        log.warning(
            f"P盘暂无视频（WebDAV可能未恢复），{cfg.retry_wait}秒后重试 "
            f"{attempt}/{cfg.retry_times}"
        )
        time.sleep(cfg.retry_wait)
    log.error(f"P盘等待 {cfg.retry_times} 次仍不可用，退出。")
    return []


def display_rel(v: Path, cfg: AppConfig) -> Path:
    try:
        return v.relative_to(cfg.src_root)
    except ValueError:
        return Path(v.name)


def output_srt_path(v: Path, cfg: AppConfig) -> Path:
    try:
        rel = v.relative_to(cfg.src_root)
        if cfg.preserve_source_root_name:
            rel = Path(cfg.src_root.name) / rel
    except ValueError:
        rel = Path(v.name)
    return cfg.dst_root / rel.with_suffix(".srt")


def _cache_relative_path(src: Path, cfg: AppConfig) -> Path:
    try:
        return src.relative_to(cfg.src_root)
    except ValueError:
        digest = hashlib.sha1(str(src).encode("utf-8")).hexdigest()[:12]
        return Path(f"{digest}_{src.name}")


def materialize_video(src: Path, cfg: AppConfig, log) -> tuple[Path, Path | None]:
    if not cfg.use_local_cache:
        return src, None

    cache_path = cfg.cache_dir / _cache_relative_path(src, cfg)
    cache_path.parent.mkdir(parents=True, exist_ok=True)

    def _copy():
        src_size = src.stat().st_size
        if cache_path.exists() and cache_path.stat().st_size == src_size:
            return cache_path
        tmp = cache_path.with_name(cache_path.name + ".part")
        if tmp.exists():
            tmp.unlink()
        shutil.copy2(src, tmp)
        if tmp.stat().st_size != src_size:
            raise OSError(f"缓存文件大小不一致: {tmp}")
        tmp.replace(cache_path)
        return cache_path

    cached = with_retry(
        _copy,
        desc=f"缓存 {src.name}",
        max_retries=cfg.io_retry,
        base_delay=cfg.io_retry_delay,
        log=log,
    )
    log.info(f"  本地缓存: {cached}")
    return cached, cached


def cleanup_cached_video(cached: Path | None, cfg: AppConfig, log) -> None:
    if not cached or not cfg.delete_cache_after:
        return
    try:
        cached.unlink(missing_ok=True)
    except Exception as e:
        log.warning(f"删除缓存失败 {cached}: {e}")


def process_one(
    model,
    v: Path,
    srt: Path,
    cfg: AppConfig,
    log,
    *,
    progress_enabled: bool = False,
):
    """转录单个视频（带重试）。返回 (sentences, 耗时)。"""
    t0 = time.time()
    emit_progress(progress_enabled, "stage", stage="缓存视频", percent=0)
    work_video, cached = materialize_video(v, cfg, log)
    try:
        def _progress(percent: int, current: float, duration: float) -> None:
            emit_progress(
                progress_enabled,
                "progress",
                stage="转录中",
                percent=percent,
                current=round(current, 2),
                duration=round(duration, 2),
            )

        def _do():
            emit_progress(progress_enabled, "stage", stage="转录中", percent=0)
            segments = transcribe_one(model, work_video, cfg, _progress)
            sentences = reflow(segments, cfg)
            emit_progress(progress_enabled, "stage", stage="写入字幕", percent=100)
            return write_srt(sentences, srt, cfg)

        sentences = with_retry(
            _do,
            desc=f"转录 {v.name}",
            max_retries=cfg.io_retry,
            base_delay=cfg.io_retry_delay,
            log=log,
        )
        return sentences, time.time() - t0
    finally:
        cleanup_cached_video(cached, cfg, log)


def repair_existing_srt(cfg: AppConfig, log) -> None:
    files = sorted(cfg.dst_root.rglob("*.srt"), key=lambda p: str(p).lower())
    ok = fail = 0
    for i, path in enumerate(files, 1):
        try:
            count = repair_srt_file(path, cfg)
            ok += 1
            log.info(f"[{i}/{len(files)}] FIX {count:3d}句 {path}")
        except Exception as e:
            fail += 1
            log.error(f"[{i}/{len(files)}] FAIL {path}: {e}")
    log.info(f"修复完成。成功 {ok} 失败 {fail}")


def build_arg_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=str(DEFAULT_CONFIG_PATH), help="配置文件路径")
    ap.add_argument("--write-default-config", action="store_true", help="写出默认配置")
    ap.add_argument("--file", help="只处理单个视频文件")
    ap.add_argument("--limit", type=int, help="只处理前 N 个")
    ap.add_argument("--force", action="store_true", help="覆盖已有 srt")
    ap.add_argument(
        "--push-cloud",
        action="store_true",
        help="本地写完后同步推送一份到云端(P盘视频同目录)",
    )
    ap.add_argument("--repair-existing", action="store_true", help="修复已有 SRT")
    ap.add_argument("--repair-file", help="只修复一个 SRT 文件")
    ap.add_argument("--emit-progress", action="store_true", help=argparse.SUPPRESS)

    ap.add_argument("--src-root", help="覆盖配置中的视频根目录")
    ap.add_argument("--dst-root", help="覆盖配置中的字幕输出根目录")
    ap.add_argument("--model-base", help="覆盖配置中的 faster-whisper 模型目录")
    ap.add_argument("--cache-dir", help="覆盖配置中的本地视频缓存目录")
    ap.add_argument("--device", help="cuda / cpu")
    ap.add_argument("--compute-type", help="float16 / int8 / float32 等")
    ap.add_argument("--max-chars-per-line", type=int, help="字幕单行最大字数")
    ap.add_argument("--max-chars-per-sentence", type=int, help="单条字幕最大字数")
    ap.add_argument("--max-sentence-duration", type=float, help="单条字幕最大秒数")
    ap.add_argument("--gap-threshold", type=float, help="自然停顿断句阈值")
    ap.add_argument("--no-local-cache", action="store_true", help="禁用本地缓存")
    ap.add_argument("--keep-cache", action="store_true", help="转录后保留本地缓存")
    ap.add_argument(
        "--no-preserve-source-root",
        action="store_true",
        help="输出时不保留视频根目录名",
    )
    return ap


def main():
    args = build_arg_parser().parse_args()
    cfg_path = _resolve_path(args.config, Path.cwd())

    if args.write_default_config:
        write_default_config(cfg_path)
        print(f"已写出默认配置: {cfg_path}")
        return

    cfg = apply_cli_overrides(load_config(cfg_path), args)
    log = setup_logging(cfg)
    log.info(f"使用配置: {cfg_path}")
    cfg.dst_root.mkdir(parents=True, exist_ok=True)

    if args.repair_file:
        path = _resolve_path(args.repair_file, Path.cwd())
        count = repair_srt_file(path, cfg)
        log.info(f"修复完成: {count}句 {path}")
        return

    if args.repair_existing:
        repair_existing_srt(cfg, log)
        return

    if args.push_cloud:
        log.info("已开启云端推送：每个视频完成后同步到 P 盘")
    if cfg.use_local_cache:
        log.info(f"已开启本地视频缓存: {cfg.cache_dir}")

    videos = find_videos(log, cfg, args.file, args.limit)
    if not videos:
        return
    log.info(f"共 {len(videos)} 个视频待处理。加载模型...")
    model = build_model(cfg)
    log.info("模型就绪。开始转录。")

    ok = fail = skip = pushed = 0
    for i, v in enumerate(videos, 1):
        rel = display_rel(v, cfg)
        srt = output_srt_path(v, cfg)
        emit_progress(
            args.emit_progress,
            "video_start",
            index=i,
            total=len(videos),
            name=str(rel),
            percent=0,
        )
        if srt.exists() and not args.force and is_srt_usable(srt):
            if args.push_cloud:
                cloud_srt = v.with_suffix(".srt")
                if not cloud_srt.exists():
                    if cloud_push(srt, v, cfg, log):
                        pushed += 1
            log.info(f"[{i}/{len(videos)}] SKIP {rel}")
            emit_progress(
                args.emit_progress,
                "video_done",
                index=i,
                total=len(videos),
                name=str(rel),
                status="skip",
                percent=100,
            )
            skip += 1
            continue

        try:
            sentences, dt = process_one(
                model,
                v,
                srt,
                cfg,
                log,
                progress_enabled=args.emit_progress,
            )
            ok += 1
            msg = (
                f"[{i}/{len(videos)}] OK  {len(sentences):3d}句 "
                f"{dt:6.1f}s  {rel.name}"
            )
            if args.push_cloud:
                if cloud_push(srt, v, cfg, log):
                    pushed += 1
                    msg += "  [已推云]"
            log.info(msg)
            emit_progress(
                args.emit_progress,
                "video_done",
                index=i,
                total=len(videos),
                name=str(rel),
                status="ok",
                percent=100,
            )
        except Exception as e:
            fail += 1
            log.error(f"[{i}/{len(videos)}] FAIL {rel.name}: {e}")
            emit_progress(
                args.emit_progress,
                "video_done",
                index=i,
                total=len(videos),
                name=str(rel),
                status="fail",
                percent=0,
            )

    log.info(
        f"完成。成功 {ok} 失败 {fail} 跳过 {skip}"
        + (f" 推云 {pushed}" if args.push_cloud else "")
    )
    if cfg.cloud_failed.exists() and cfg.cloud_failed.stat().st_size > 0:
        log.info(f"部分云端推送失败，见 {cfg.cloud_failed}")


if __name__ == "__main__":
    main()
