# Video2Srt

批量把课程视频转成中文字幕 SRT。默认使用 `faster-whisper`，支持断点跳过、本地缓存转录、云端补推、已有字幕修复和 Tkinter 图形界面。

## 环境

```powershell
.venv\Scripts\python.exe -m pip install -r requirements.txt
```

模型默认读取 Buzz 缓存里的 `Systran/faster-whisper-large-v2`，路径写在 `config.json` 的 `model_base`。

## 命令行

```powershell
# 批量转录，跳过已有且格式可解析的 SRT
.venv\Scripts\python.exe transcribe.py

# 只处理一个视频
.venv\Scripts\python.exe transcribe.py --file "P:\path\to\video.mp4"

# 只处理前 3 个
.venv\Scripts\python.exe transcribe.py --limit 3

# 覆盖已有字幕
.venv\Scripts\python.exe transcribe.py --force

# 转完后把 SRT 推回视频同目录
.venv\Scripts\python.exe transcribe.py --push-cloud

# 修复已有字幕的时间轴、重复片段和换行，不重新转录
.venv\Scripts\python.exe transcribe.py --repair-existing
```

## GUI

```powershell
.venv\Scripts\python.exe gui.py
```

GUI 可以选择视频根目录、字幕输出目录、模型版本、模型目录和缓存目录，也可以调节单行字数、单条字幕字数、单条字幕秒数、停顿断句阈值，并启动批量转录、单文件转录或修复已有字幕。运行时会显示当前视频的转录进度条。模型版本内置 `large-v2`、`large-v3` 和 `自定义`，选择 `large-v3` 会自动填入本机 Buzz 缓存中的 v3 路径。

## 配置

主要配置在 `config.json`：

- `src_root`: 视频根目录。
- `dst_root`: 字幕输出根目录。
- `preserve_source_root_name`: 默认 `true`，输出时保留视频根目录名，方便和原课程目录合并。
- `use_local_cache`: 默认 `true`，先把视频复制到本地缓存再转录，减少 WebDAV/P 盘抖动影响。
- `delete_cache_after`: 默认 `true`，转录完成后删除本地视频缓存。
- `max_chars_per_line`: 单行最大字数，默认 `18`。
- `max_chars_per_sentence`: 单条字幕最大字数，默认 `32`。
- `max_sentence_duration`: 单条字幕最大秒数，默认 `5.5`。
- `gap_threshold`: segment 间隔超过该秒数时视为自然停顿，默认 `0.55`。

如需重新生成默认配置：

```powershell
.venv\Scripts\python.exe transcribe.py --write-default-config
```

## 输出与恢复

写 SRT 时会先写 `.tmp` 文件，再原子替换到目标路径，避免中途失败留下半个字幕文件。已存在的 SRT 会先做基本格式解析，能解析才跳过；格式坏掉的文件会被重新生成。

初始项目状态已经提交到 Git，基线提交为 `77dd00b`。
