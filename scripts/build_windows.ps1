[CmdletBinding()]
param(
    [ValidateSet("source", "pyinstaller")]
    [string]$BackendMode = "pyinstaller",

    [string]$RuntimePath = "",

    [switch]$SkipFlutterBuild,

    [switch]$IncludeModels
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$FlutterRoot = Join-Path $RepoRoot "flutter_app"
$PackageRoot = Join-Path $RepoRoot "dist\Video2Srt"
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

Assert-UnderDirectory -Path $PackageRoot -Parent (Join-Path $RepoRoot "dist")
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
        $pythonExe = Join-Path $resolvedRuntime "python.exe"
        if (-not (Test-Path -LiteralPath $pythonExe)) {
            throw "RuntimePath must point to a directory containing python.exe: $resolvedRuntime"
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

Write-Host "Windows package ready: $PackageRoot"
