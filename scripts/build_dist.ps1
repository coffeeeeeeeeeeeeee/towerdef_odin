# Builds a release binary and packages it with the runtime assets into a
# distributable zip. Run this on an actual Windows machine — the Linux
# counterpart (scripts/build_dist.sh) cannot cross-link a working Windows
# .exe (see the note at the bottom of that script for why).
param(
    [string]$Version = (Get-Date -Format "yyyyMMdd")
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$Name = "towerdef-first-impact"
$Dist = "dist"
$Stage = "$Dist\windows\$Name"

Write-Host "==> Cleaning $Stage"
Remove-Item -Recurse -Force $Stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

Write-Host "==> Compiling (windows, release)"
odin build . -out:"$Stage\towerdef.exe" -o:speed

Write-Host "==> Copying runtime assets"
Copy-Item -Recurse -Path images,fonts,audio,music,assets,maps -Destination $Stage
Copy-Item -Path translations.txt,campaign.bin,README.md -Destination $Stage
# savegame.bin / settings.bin deliberately NOT copied: those are per-player
# state (progress, settings), not game content.

Write-Host "==> Zipping"
$ZipPath = "$Dist\$Name-windows-$Version.zip"
Remove-Item -Force $ZipPath -ErrorAction SilentlyContinue
Compress-Archive -Path $Stage -DestinationPath $ZipPath

Write-Host ""
Write-Host "Done: $ZipPath"
