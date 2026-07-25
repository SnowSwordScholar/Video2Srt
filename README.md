# Video2Srt

本地批量转录视频并生成中文字幕 SRT 的 Windows 工具。后端使用
`faster-whisper`，桌面端使用 Flutter Material 3。

## 功能

- 批量转录、单文件转录、已有 SRT 修复。
- 直接下载 `large-v2` 与 `large-v3` 的 faster-whisper 模型。
- 每个视频都有转录进度，日志以 UTF-8 输出。
- 输出时保留视频根目录名，方便把字幕目录合并回原课程目录。
- 支持本地视频缓存、失败重试、跳过已完成字幕和可选的源目录回写。
- `device: auto` 会优先使用可用的 CUDA；没有 CUDA 或 CUDA 初始化失败时自动使用 CPU。

## 快速开始

需要 Windows、Python 3.10+。CUDA 不是必需条件。

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item config.example.json config.json
```

编辑 `config.json`，至少设置 `src_root`。所有相对路径都相对于配置文件所在目录。

下载模型：

```powershell
.\.venv\Scripts\python.exe transcribe.py --download-model large-v3
```

开始批量转录：

```powershell
.\.venv\Scripts\python.exe transcribe.py
```

常用命令：

```powershell
# 单文件
.\.venv\Scripts\python.exe transcribe.py --file "D:\Videos\lesson.mp4"

# 只处理前 3 个
.\.venv\Scripts\python.exe transcribe.py --limit 3

# 覆盖已有字幕
.\.venv\Scripts\python.exe transcribe.py --force

# 把完成的字幕同步到源视频所在目录
.\.venv\Scripts\python.exe transcribe.py --push-cloud

# 只修复已有 SRT 的时间轴、重复片段和换行
.\.venv\Scripts\python.exe transcribe.py --repair-existing
```

## 桌面 GUI

推荐使用新的 Flutter 桌面程序：

```powershell
Set-Location flutter_app
flutter pub get
flutter run -d windows
```

它会自动找到项目根目录下的 Python 后端。GUI 可以选择视频、输出、模型和缓存目录，管理模型下载，并调整硬件与断句参数。

旧的 Tkinter GUI 仍可通过 `.\.venv\Scripts\python.exe gui.py` 启动，但不再是主界面。

## CPU 与 CUDA

默认配置使用：

```json
{
  "device": "auto",
  "compute_type": "default"
}
```

- `auto`：检测到 CUDA 时使用 `cuda + float16`；否则使用 `cpu + int8`。
- `cuda`：只使用 CUDA，适合已确认驱动和运行库正常的机器。
- `cpu`：强制使用 CPU。`int8` 是大模型在 CPU 上更实用的默认精度。
- CUDA 在自动模式下初始化失败时，后端会记录原因并自动回落到 CPU `int8`。

CPU 可以正常运行，但 `large-v3` 对长视频会明显更慢；可按机器性能改用 `large-v2`。

## 配置

`config.example.json` 是可提交的模板，实际使用的 `config.json` 不会进入 Git。

常用项：

- `src_root`：视频根目录，留空表示尚未选择。
- `dst_root`：字幕输出目录，默认 `output`。
- `model_base`：模型目录，默认 `models/large-v3`。
- `preserve_source_root_name`：默认 `true`，保留源目录最外层名称。
- `use_local_cache`：先复制视频到本地缓存后转录，适合网络盘或 WebDAV。
- `max_chars_per_line`、`max_chars_per_sentence`、`max_sentence_duration`、`gap_threshold`：控制字幕长度和断句。

重新生成模板配置：

```powershell
.\.venv\Scripts\python.exe transcribe.py --write-default-config
```

检查当前后端依赖、模型和 CPU/CUDA 选择：

```powershell
.\.venv\Scripts\python.exe transcribe.py --check-runtime
```

## Windows 发布包

发布脚本会先构建 Flutter，再把后端放入 `dist\Video2Srt\backend`。模型默认不随包分发，用户可以在 GUI 的“模型”页下载。

默认会构建不依赖目标机器 Python 的 PyInstaller 发布包，并把发布意图写入
`backend\backend_manifest.json`：

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\scripts\build_windows.ps1
```

推荐公开发布先使用默认的 `-PackageProfile cpu`。它仍会在用户机器上按配置执行
`device: auto`：能用 CUDA 时尝试 CUDA，不能用时回到 CPU `int8`。

如果要发布面向 CUDA 的包，可以标记：

```powershell
.\scripts\build_windows.ps1 -PackageProfile cuda
```

这个标记只记录发布意图；实际 CUDA 能力取决于打包环境中安装的
`ctranslate2`/相关运行库，以及目标机器的 NVIDIA 驱动和 CUDA 运行库。

如需生成源码后端的便携包，可显式选择 `source` 模式；它会调用随包 runtime 或系统 Python：

```powershell
.\scripts\build_windows.ps1 -BackendMode source
```

也可以把一个可重定位的 Python runtime 目录放进源码后端包：

```powershell
.\scripts\build_windows.ps1 -RuntimePath "D:\runtime\python"
```

`RuntimePath` 可以是带 `python.exe` 的便携 Python，也可以是包含
`Scripts\python.exe` 的虚拟环境目录。真正对外分发时更推荐 PyInstaller 或可重定位的
Python runtime；普通 venv 在不同机器上未必完全可移植。

`-IncludeModels` 会把本地 `models` 目录一起复制到发布包；默认关闭，避免意外打入体积很大的模型文件。

更完整的发布说明见 [docs/PACKAGING.md](docs/PACKAGING.md)。

## Git 与隐私

`.gitignore` 已排除本地配置、日志、缓存、模型、输出字幕和发布产物。不要提交真实视频、模型或生成的 SRT。

发布到公开仓库前还需要由项目所有者选择并添加合适的开源许可证。由于早期本地提交可能包含真实路径或生成字幕，公开发布建议从当前干净工作树创建一个新的首个提交，或在发布前重写历史。
