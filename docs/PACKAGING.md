# Windows Packaging

Video2Srt has a Flutter desktop frontend and a local Python backend. The app
starts the backend as a subprocess; it does not require a local HTTP service.

## Recommended Public Build

Use the default PyInstaller package for a release that does not depend on the
target machine having Python installed:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\scripts\build_windows.ps1 -PackageProfile cpu
```

The result is placed in `dist\Video2Srt`. Start `Video2Srt.exe`; the backend is
in `backend\transcribe.exe`.

The package intentionally excludes models. On first use, download a model in
the GUI's model page. This keeps the release smaller and avoids redistributing
large model files by accident.

## CPU And CUDA

The default package profile is `cpu`. This is the safest public target:

- `device: auto` selects `cuda + float16` when CTranslate2 can see a CUDA
  device.
- It selects `cpu + int8` otherwise.
- If CUDA initialization fails while using `auto`, the backend retries with
  CPU `int8`.

`-PackageProfile cuda` records that the package was built for CUDA-oriented
deployment:

```powershell
.\scripts\build_windows.ps1 -PackageProfile cuda
```

It does not bundle a GPU driver or create CUDA support by itself. Build the
backend in an environment with the intended CTranslate2/CUDA dependencies, and
test it on a machine with compatible NVIDIA drivers and runtime libraries.

The GUI exposes `auto`, `cuda`, and `cpu`. Users should keep `auto` unless
they deliberately want to force a device.

## Source And Runtime Packages

A source package copies `transcribe.py` and uses Python found on the target:

```powershell
.\scripts\build_windows.ps1 -BackendMode source
```

To include a Python runtime alongside the source backend:

```powershell
.\scripts\build_windows.ps1 -BackendMode source -RuntimePath "D:\portable-python"
```

`RuntimePath` may contain `python.exe`, `Scripts\python.exe`, or
`bin\python.exe`. A copied virtual environment can be convenient for testing,
but a dedicated relocatable Python runtime is more reliable for distribution.

## Verification

The build script runs a backend self-check for PyInstaller packages and for
source packages with a bundled runtime. Run it manually after moving a package:

```powershell
.\dist\Video2Srt\backend\transcribe.exe `
  --config .\dist\Video2Srt\backend\config.example.json `
  --check-runtime
```

The report includes frozen/runtime paths, dependency availability, CUDA device
count, recommended device/compute type, and whether a model is ready. A missing
model is expected before the first download; it does not make the backend
dependency check fail.

Each package contains `backend\backend_manifest.json` with the backend mode,
package profile, model inclusion state, build time, and source commit.

## Release Checklist

- Build from a clean working tree.
- Run the packaged `--check-runtime` command on a CPU-only machine when
  possible.
- Download and transcribe a short public test clip on the intended target.
- Keep `models`, `config.json`, logs, caches, videos, and generated SRT files
  out of the release archive unless they are intentionally included.
- Add a license before publishing source code.
