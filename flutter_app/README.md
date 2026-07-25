# Video2Srt Flutter App

Video2Srt 的 Windows Material 3 桌面界面。它通过本地子进程调用项目后端：

- 开发模式：项目根目录中的 `transcribe.py`。
- 便携 Python 模式：`backend/transcribe.py` 与 `backend/runtime/python.exe`。
- 发布模式：`backend/transcribe.exe`。

运行开发版：

```powershell
flutter pub get
flutter run -d windows
```

完整的使用和打包说明见项目根目录的 `README.md`。
