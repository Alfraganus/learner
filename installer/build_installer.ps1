# Builds the Windows release and the Inno Setup installer.
# Usage: powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1 [-Version 1.0.0] [-SkipBuild]
param([string]$Version = "", [switch]$SkipBuild)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not $Version) {
  $Version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value)
}
if (-not $SkipBuild) { flutter build windows --release; if ($LASTEXITCODE) { exit $LASTEXITCODE } }

# 64-bit MSVC runtime DLLs from this machine (PowerShell here is 64-bit, so System32 is the x64 folder).
$vc = Join-Path $PSScriptRoot "vcruntime"
New-Item -ItemType Directory -Force $vc | Out-Null
foreach ($d in "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll") {
  Copy-Item (Join-Path $env:SystemRoot "System32\$d") $vc -Force
}

$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 not found. Install it: winget install JRSoftware.InnoSetup" }

& $iscc "/DAppVersion=$Version" (Join-Path $PSScriptRoot "learner.iss")
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Get-ChildItem (Join-Path $PSScriptRoot "Output") | Select-Object Name, Length
