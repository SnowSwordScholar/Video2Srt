[CmdletBinding()]
param(
    [string]$PackageRoot = "build\Video2Srt-package",

    [string]$OutputDir = "dist\installer",

    [string]$Version = "",

    [switch]$SkipPackageBuild
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$IssPath = Join-Path $PSScriptRoot "installer.iss"

function Resolve-InRepoPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rawPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $RepoRoot $Path
    }
    return [System.IO.Path]::GetFullPath($rawPath)
}

function Get-FlutterVersion {
    $pubspec = Join-Path $RepoRoot "flutter_app\pubspec.yaml"
    $match = Select-String -LiteralPath $pubspec -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
    if ($match) {
        return $match.Matches[0].Groups[1].Value
    }
    return "1.0.0"
}

$packageFullPath = Resolve-InRepoPath -Path $PackageRoot
$outputFullPath = Resolve-InRepoPath -Path $OutputDir
$appVersion = if ($Version) { $Version } else { Get-FlutterVersion }
$versionInfoVersion = "$appVersion.0"
$outputBaseFilename = "Video2Srt-$appVersion-Setup"

if (-not $SkipPackageBuild) {
    & (Join-Path $PSScriptRoot "build_windows.ps1") -PackageRoot $packageFullPath -PackageProfile auto
    if ($LASTEXITCODE -ne 0) {
        throw "Windows package build failed."
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $packageFullPath "Video2Srt.exe"))) {
    throw "Package root does not contain Video2Srt.exe: $packageFullPath"
}

New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null

& iscc `
    "/DAppVersion=$appVersion" `
    "/DVersionInfoVersion=$versionInfoVersion" `
    "/DPackageRoot=$packageFullPath" `
    "/DOutputDir=$outputFullPath" `
    "/DOutputBaseFilename=$outputBaseFilename" `
    $IssPath

if ($LASTEXITCODE -ne 0) {
    throw "Installer build failed."
}

$installer = Join-Path $outputFullPath "$outputBaseFilename.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer was not created: $installer"
}

Write-Host "Installer ready: $installer"
