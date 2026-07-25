#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk


PROJECT_ROOT = Path(__file__).resolve().parent
CONFIG_PATH = PROJECT_ROOT / "config.json"
TRANSCRIBE = PROJECT_ROOT / "transcribe.py"
PROGRESS_PREFIX = "__VIDEO2SRT_PROGRESS__ "
MODELS_DIR = PROJECT_ROOT / "models"
MODEL_PRESETS = {
    "large-v2": str(MODELS_DIR / "large-v2"),
    "large-v3": str(MODELS_DIR / "large-v3"),
}
CUSTOM_MODEL_LABEL = "自定义"


def python_exe() -> str:
    local = PROJECT_ROOT / ".venv" / "Scripts" / "python.exe"
    if local.exists():
        return str(local)
    return sys.executable


def load_config() -> dict:
    if CONFIG_PATH.exists():
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    return {
        "src_root": "",
        "dst_root": str(PROJECT_ROOT),
        "model_base": "",
        "cache_dir": str(PROJECT_ROOT / ".cache" / "videos"),
        "preserve_source_root_name": True,
        "use_local_cache": True,
        "delete_cache_after": True,
        "max_chars_per_line": 18,
        "max_chars_per_sentence": 32,
        "max_sentence_duration": 5.5,
        "gap_threshold": 0.55,
    }


class Video2SrtGui(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Video2Srt")
        self.geometry("980x720")
        self.minsize(840, 620)

        self.proc: subprocess.Popen | None = None
        self.output_queue: queue.Queue[str] = queue.Queue()
        self.config_data = load_config()

        self.vars: dict[str, tk.Variable] = {}
        self.file_var = tk.StringVar()
        self.limit_var = tk.StringVar()
        self.force_var = tk.BooleanVar(value=False)
        self.push_cloud_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="就绪")
        self.model_preset_var = tk.StringVar(value=self._infer_model_preset())
        self.current_video_var = tk.StringVar(value="当前视频：-")
        self.progress_text_var = tk.StringVar(value="0%")
        self.progress_value = tk.DoubleVar(value=0)

        self._build_ui()
        self.after(100, self._poll_output)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill=tk.BOTH, expand=True)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(5, weight=1)

        paths = ttk.LabelFrame(root, text="路径")
        paths.grid(row=0, column=0, sticky="ew")
        paths.columnconfigure(1, weight=1)
        self._path_row(paths, 0, "视频根目录", "src_root", directory=True)
        self._path_row(paths, 1, "字幕输出目录", "dst_root", directory=True)
        self._model_preset_row(paths, 2)
        self._path_row(paths, 3, "模型目录", "model_base", directory=True)
        self._path_row(paths, 4, "本地缓存目录", "cache_dir", directory=True)
        self._path_row(paths, 5, "单个视频", "file", directory=False, optional=True)

        params = ttk.LabelFrame(root, text="断句")
        params.grid(row=1, column=0, sticky="ew", pady=(10, 0))
        for i in range(4):
            params.columnconfigure(i * 2 + 1, weight=1)
        self._entry(params, 0, 0, "单行字数", "max_chars_per_line")
        self._entry(params, 0, 2, "单条字数", "max_chars_per_sentence")
        self._entry(params, 1, 0, "单条秒数", "max_sentence_duration")
        self._entry(params, 1, 2, "停顿阈值", "gap_threshold")

        options = ttk.Frame(root)
        options.grid(row=2, column=0, sticky="ew", pady=(10, 0))
        self._check(options, "保留视频根目录名", "preserve_source_root_name", 0)
        self._check(options, "使用本地缓存", "use_local_cache", 1)
        self._check(options, "完成后删除缓存", "delete_cache_after", 2)
        ttk.Checkbutton(options, text="覆盖已有字幕", variable=self.force_var).grid(
            row=0, column=3, padx=(18, 0), sticky="w"
        )
        ttk.Checkbutton(options, text="推送到云端", variable=self.push_cloud_var).grid(
            row=0, column=4, padx=(18, 0), sticky="w"
        )
        ttk.Label(options, text="数量").grid(row=0, column=5, padx=(18, 4))
        ttk.Entry(options, textvariable=self.limit_var, width=8).grid(row=0, column=6)

        buttons = ttk.Frame(root)
        buttons.grid(row=3, column=0, sticky="ew", pady=(10, 0))
        ttk.Button(buttons, text="保存配置", command=self.save_config).pack(
            side=tk.LEFT
        )
        ttk.Button(buttons, text="批量转录", command=self.start_batch).pack(
            side=tk.LEFT, padx=(8, 0)
        )
        ttk.Button(buttons, text="单文件转录", command=self.start_single).pack(
            side=tk.LEFT, padx=(8, 0)
        )
        ttk.Button(buttons, text="修复已有字幕", command=self.start_repair).pack(
            side=tk.LEFT, padx=(8, 0)
        )
        ttk.Button(buttons, text="停止", command=self.stop_process).pack(
            side=tk.LEFT, padx=(8, 0)
        )
        ttk.Label(buttons, textvariable=self.status_var).pack(side=tk.RIGHT)

        progress = ttk.Frame(root)
        progress.grid(row=4, column=0, sticky="ew", pady=(10, 0))
        progress.columnconfigure(1, weight=1)
        ttk.Label(progress, textvariable=self.current_video_var).grid(
            row=0, column=0, columnspan=3, sticky="w", pady=(0, 4)
        )
        self.progress_bar = ttk.Progressbar(
            progress,
            variable=self.progress_value,
            maximum=100,
            mode="determinate",
        )
        self.progress_bar.grid(row=1, column=0, columnspan=2, sticky="ew")
        ttk.Label(progress, textvariable=self.progress_text_var, width=14).grid(
            row=1, column=2, sticky="e", padx=(8, 0)
        )

        log_frame = ttk.LabelFrame(root, text="日志")
        log_frame.grid(row=5, column=0, sticky="nsew", pady=(10, 0))
        log_frame.rowconfigure(0, weight=1)
        log_frame.columnconfigure(0, weight=1)
        self.output = tk.Text(log_frame, wrap="word", height=18)
        self.output.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(log_frame, command=self.output.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.output.configure(yscrollcommand=scroll.set)

    def _infer_model_preset(self) -> str:
        model_base = str(self.config_data.get("model_base", ""))
        for name, path in MODEL_PRESETS.items():
            if model_base.casefold() == path.casefold():
                return name
        return CUSTOM_MODEL_LABEL

    def _model_preset_row(self, parent: ttk.Frame, row: int) -> None:
        ttk.Label(parent, text="模型版本").grid(row=row, column=0, sticky="w", pady=3)
        combo = ttk.Combobox(
            parent,
            textvariable=self.model_preset_var,
            values=[*MODEL_PRESETS.keys(), CUSTOM_MODEL_LABEL],
            state="readonly",
        )
        combo.grid(row=row, column=1, sticky="ew", padx=(8, 8), pady=3)
        combo.bind("<<ComboboxSelected>>", self._on_model_preset_changed)

    def _on_model_preset_changed(self, _event=None) -> None:
        preset = self.model_preset_var.get()
        if preset in MODEL_PRESETS and "model_base" in self.vars:
            self.vars["model_base"].set(MODEL_PRESETS[preset])

    def _path_row(
        self,
        parent: ttk.Frame,
        row: int,
        label: str,
        key: str,
        *,
        directory: bool,
        optional: bool = False,
    ) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", pady=3)
        if key == "file":
            var = self.file_var
        else:
            var = tk.StringVar(value=str(self.config_data.get(key, "")))
            self.vars[key] = var
        entry = ttk.Entry(parent, textvariable=var)
        entry.grid(row=row, column=1, sticky="ew", padx=(8, 8), pady=3)
        if directory:
            command = lambda v=var: self._browse_dir(v)
        else:
            command = lambda v=var: self._browse_file(v)
        ttk.Button(parent, text="选择", command=command).grid(
            row=row, column=2, sticky="e", pady=3
        )
        if optional:
            ttk.Button(parent, text="清空", command=lambda: var.set("")).grid(
                row=row, column=3, padx=(6, 0), pady=3
            )

    def _entry(
        self, parent: ttk.Frame, row: int, col: int, label: str, key: str
    ) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=col, sticky="w", pady=3)
        var = tk.StringVar(value=str(self.config_data.get(key, "")))
        self.vars[key] = var
        ttk.Entry(parent, textvariable=var, width=12).grid(
            row=row, column=col + 1, sticky="ew", padx=(8, 18), pady=3
        )

    def _check(self, parent: ttk.Frame, label: str, key: str, col: int) -> None:
        var = tk.BooleanVar(value=bool(self.config_data.get(key, False)))
        self.vars[key] = var
        ttk.Checkbutton(parent, text=label, variable=var).grid(
            row=0, column=col, sticky="w", padx=(0 if col == 0 else 18, 0)
        )

    def _browse_dir(self, var: tk.StringVar) -> None:
        selected = filedialog.askdirectory(initialdir=var.get() or str(PROJECT_ROOT))
        if selected:
            var.set(selected)
            if var is self.vars.get("model_base"):
                self.model_preset_var.set(self._infer_model_preset_from_value(selected))

    def _infer_model_preset_from_value(self, value: str) -> str:
        for name, path in MODEL_PRESETS.items():
            if value.casefold() == path.casefold():
                return name
        return CUSTOM_MODEL_LABEL

    def _browse_file(self, var: tk.StringVar) -> None:
        selected = filedialog.askopenfilename(
            initialdir=str(PROJECT_ROOT),
            filetypes=[
                ("视频文件", "*.mp4 *.mkv *.avi *.mov *.m4a *.mp3 *.wav"),
                ("所有文件", "*.*"),
            ],
        )
        if selected:
            var.set(selected)

    def save_config(self) -> bool:
        data = dict(self.config_data)
        try:
            for key, var in self.vars.items():
                value = var.get()
                if key in {
                    "max_chars_per_line",
                    "max_chars_per_sentence",
                }:
                    value = int(value)
                elif key in {"max_sentence_duration", "gap_threshold"}:
                    value = float(value)
                data[key] = value
        except ValueError as e:
            messagebox.showwarning("Video2Srt", f"参数格式不正确: {e}")
            return False
        data["model_preset"] = self.model_preset_var.get()
        CONFIG_PATH.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        self.config_data = data
        self.status_var.set("配置已保存")
        return True

    def _base_cmd(self) -> list[str] | None:
        if not self.save_config():
            return None
        return [
            python_exe(),
            str(TRANSCRIBE),
            "--config",
            str(CONFIG_PATH),
            "--emit-progress",
        ]

    def _add_common_flags(self, cmd: list[str]) -> list[str]:
        if self.force_var.get():
            cmd.append("--force")
        if self.push_cloud_var.get():
            cmd.append("--push-cloud")
        limit = self.limit_var.get().strip()
        if limit:
            cmd.extend(["--limit", limit])
        return cmd

    def start_batch(self) -> None:
        cmd = self._base_cmd()
        if cmd is None:
            return
        cmd = self._add_common_flags(cmd)
        self._start(cmd)

    def start_single(self) -> None:
        file_path = self.file_var.get().strip()
        if not file_path:
            messagebox.showwarning("Video2Srt", "请选择单个视频文件")
            return
        cmd = self._base_cmd()
        if cmd is None:
            return
        cmd = self._add_common_flags(cmd)
        cmd.extend(["--file", file_path])
        self._start(cmd)

    def start_repair(self) -> None:
        cmd = self._base_cmd()
        if cmd is None:
            return
        cmd.append("--repair-existing")
        self._start(cmd)

    def _start(self, cmd: list[str]) -> None:
        if self.proc and self.proc.poll() is None:
            messagebox.showinfo("Video2Srt", "任务仍在运行")
            return
        self.output.insert(tk.END, "\n> " + " ".join(cmd) + "\n")
        self.output.see(tk.END)
        self.current_video_var.set("当前视频：准备中")
        self.progress_text_var.set("0%")
        self.progress_value.set(0)
        self.status_var.set("运行中")
        thread = threading.Thread(target=self._run_process, args=(cmd,), daemon=True)
        thread.start()

    def _run_process(self, cmd: list[str]) -> None:
        try:
            env = os.environ.copy()
            env["PYTHONIOENCODING"] = "utf-8"
            env["PYTHONUTF8"] = "1"
            self.proc = subprocess.Popen(
                cmd,
                cwd=PROJECT_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
            assert self.proc.stdout is not None
            for line in self.proc.stdout:
                self.output_queue.put(line)
            code = self.proc.wait()
            self.output_queue.put(f"\n进程结束，退出码 {code}\n")
        except Exception as e:
            self.output_queue.put(f"\n启动失败: {e}\n")
        finally:
            self.proc = None
            self.output_queue.put("__STATUS_DONE__")

    def _poll_output(self) -> None:
        try:
            while True:
                line = self.output_queue.get_nowait()
                if line == "__STATUS_DONE__":
                    self.status_var.set("就绪")
                    continue
                if line.startswith(PROGRESS_PREFIX):
                    self._handle_progress_line(line)
                    continue
                self.output.insert(tk.END, line)
                self.output.see(tk.END)
        except queue.Empty:
            pass
        self.after(100, self._poll_output)

    def stop_process(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            self.status_var.set("正在停止")

    def _handle_progress_line(self, line: str) -> None:
        try:
            data = json.loads(line[len(PROGRESS_PREFIX):])
        except json.JSONDecodeError:
            return

        event = data.get("event")
        if event == "video_start":
            index = data.get("index", 0)
            total = data.get("total", 0)
            name = data.get("name", "")
            self.current_video_var.set(f"当前视频：[{index}/{total}] {name}")
            self.progress_value.set(0)
            self.progress_text_var.set("0%")
            return

        if event in {"stage", "progress"}:
            stage = data.get("stage", "处理中")
            percent = float(data.get("percent", 0))
            self.progress_value.set(percent)
            if event == "progress" and data.get("duration"):
                current = float(data.get("current", 0))
                duration = float(data.get("duration", 0))
                self.progress_text_var.set(
                    f"{percent:.0f}%  {current:.0f}/{duration:.0f}s"
                )
            else:
                self.progress_text_var.set(f"{stage}  {percent:.0f}%")
            return

        if event == "video_done":
            status = data.get("status", "")
            percent = float(data.get("percent", 100))
            self.progress_value.set(percent)
            self.progress_text_var.set(f"{status}  {percent:.0f}%")


if __name__ == "__main__":
    Video2SrtGui().mainloop()
