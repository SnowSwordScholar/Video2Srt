[CmdletBinding()]
param(
    [ValidateSet("source", "pyinstaller")]
    [string]$BackendMode = "pyinstaller",

    [ValidateSet("cpu", "cuda", "auto")]
    [string]$PackageProfile = "auto",

    [string]$RuntimePath = "",

    [string]$PackageRoot = "",

    [switch]$SkipFlutterBuild,

    [switch]$IncludeModels,

    [switch]$SkipBackendCheck
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$FlutterRoot = Join-Path $RepoRoot "flutter_app"
$PackageRoot = if ($PackageRoot) {
    $rawPackageRoot = if ([System.IO.Path]::IsPathRooted($PackageRoot)) {
        $PackageRoot
    }
    else {
        Join-Path $RepoRoot $PackageRoot
    }
    [System.IO.Path]::GetFullPath($rawPackageRoot)
}
else {
    Join-Path $RepoRoot "dist\Video2Srt"
}
$BackendRoot = Join-Path $PackageRoot "backend"
$FlutterRelease = Join-Path $FlutterRoot "build\windows\x64\runner\Release"

function Assert-UnderDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside $fullParent`: $fullPath"
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Missing directory: $Source"
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force |
        Copy-Item -Destination $Destination -Recurse -Force
}

function Get-RuntimePython {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot
    )

    $candidates = @(
        (Join-Path $RuntimeRoot "python.exe"),
        (Join-Path $RuntimeRoot "Scripts\python.exe"),
        (Join-Path $RuntimeRoot "bin\python.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Write-BackendManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][bool]$ModelsIncluded,
        [string]$Runtime = ""
    )

    $gitCommit = ""
    try {
        $gitCommit = (& git -C $RepoRoot rev-parse --short HEAD 2>$null)
    }
    catch {
        $gitCommit = ""
    }

    $manifest = [ordered]@{
        name = "Video2Srt backend"
        backend_mode = $Mode
        package_profile = $Profile
        models_included = $ModelsIncluded
        runtime_path = $Runtime
        git_commit = $gitCommit
        created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
        notes = @(
            "The auto profile selects CUDA when it is available, otherwise CPU.",
            "CUDA support still depends on the packaged dependencies and the target machine NVIDIA runtime.",
            "Models are intentionally excluded unless IncludeModels is set."
        )
    }
    $manifest |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-BackendCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [string]$Runtime = ""
    )

    if ($SkipBackendCheck) {
        return
    }

    $config = Join-Path $BackendRoot "config.example.json"
    if ($Mode -eq "pyinstaller") {
        $backendExe = Join-Path $BackendRoot "transcribe.exe"
        & $backendExe --config $config --check-runtime
        if ($LASTEXITCODE -ne 0) {
            throw "Packaged backend runtime check failed."
        }
        return
    }

    if (-not $Runtime) {
        Write-Host "Skipping backend runtime check because source mode has no bundled runtime."
        return
    }

    $pythonExe = Get-RuntimePython -RuntimeRoot $Runtime
    if (-not $pythonExe) {
        throw "No python executable found in bundled runtime: $Runtime"
    }
    & $pythonExe (Join-Path $BackendRoot "transcribe.py") --config $config --check-runtime
    if ($LASTEXITCODE -ne 0) {
        throw "Bundled Python backend runtime check failed."
    }
}

if (-not $SkipFlutterBuild) {
    Push-Location $FlutterRoot
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build failed."
        }
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $FlutterRelease)) {
    throw "Flutter release output not found: $FlutterRelease"
}

Assert-UnderDirectory -Path $PackageRoot -Parent $RepoRoot
if (Test-Path -LiteralPath $PackageRoot) {
    Remove-Item -LiteralPath $PackageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $BackendRoot | Out-Null

Copy-DirectoryContents -Source $FlutterRelease -Destination $PackageRoot

Copy-Item -LiteralPath (Join-Path $RepoRoot "config.example.json") -Destination $BackendRoot -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "requirements.txt") -Destination $BackendRoot -Force
if (Test-Path -LiteralPath (Join-Path $RepoRoot "README.md")) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot "README.md") -Destination $PackageRoot -Force
}
if (Test-Path -LiteralPath (Join-Path $RepoRoot "LICENSE")) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot "LICENSE") -Destination $PackageRoot -Force
}

if ($BackendMode -eq "source") {
    Copy-Item -LiteralPath (Join-Path $RepoRoot "transcribe.py") -Destination $BackendRoot -Force

    if ($RuntimePath) {
        $resolvedRuntime = (Resolve-Path $RuntimePath).Path
        $pythonExe = Get-RuntimePython -RuntimeRoot $resolvedRuntime
        if (-not $pythonExe) {
            throw "RuntimePath must contain python.exe, Scripts\python.exe, or bin\python.exe: $resolvedRuntime"
        }
        Copy-DirectoryContents -Source $resolvedRuntime -Destination (Join-Path $BackendRoot "runtime")
    }
}
else {
    $python = Join-Path $RepoRoot ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $python)) {
        $python = "python"
    }

    & $python -c "import PyInstaller" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller is not installed. Run: $python -m pip install pyinstaller"
    }

    $pyinstallerDist = Join-Path $RepoRoot "build\pyinstaller_dist"
    $pyinstallerWork = Join-Path $RepoRoot "build\pyinstaller_work"
    $pyinstallerSpec = Join-Path $RepoRoot "build\pyinstaller_spec"

    & $python -m PyInstaller `
        --noconfirm `
        --clean `
        --onedir `
        --name transcribe `
        --distpath $pyinstallerDist `
        --workpath $pyinstallerWork `
        --specpath $pyinstallerSpec `
        --collect-all faster_whisper `
        --collect-all ctranslate2 `
        --collect-all tokenizers `
        --collect-all huggingface_hub `
        --collect-all av `
        --copy-metadata faster-whisper `
        --copy-metadata ctranslate2 `
        --copy-metadata tokenizers `
        --copy-metadata huggingface-hub `
        --copy-metadata av `
        (Join-Path $RepoRoot "transcribe.py")
    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller build failed."
    }

    Copy-DirectoryContents -Source (Join-Path $pyinstallerDist "transcribe") -Destination $BackendRoot
}

if ($IncludeModels) {
    $models = Join-Path $RepoRoot "models"
    if (Test-Path -LiteralPath $models) {
        Copy-DirectoryContents -Source $models -Destination (Join-Path $BackendRoot "models")
    }
}

$bundledRuntime = ""
if ($BackendMode -eq "source" -and $RuntimePath) {
    $bundledRuntime = Join-Path $BackendRoot "runtime"
}
Write-BackendManifest `
    -Path (Join-Path $BackendRoot "backend_manifest.json") `
    -Mode $BackendMode `
    -Profile $PackageProfile `
    -ModelsIncluded ([bool]$IncludeModels) `
    -Runtime $bundledRuntime

Invoke-BackendCheck -Mode $BackendMode -Runtime $bundledRuntime

Write-Host "Windows package ready: $PackageRoot"
