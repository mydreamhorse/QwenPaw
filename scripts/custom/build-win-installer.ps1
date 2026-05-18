# Custom Windows installer builder for the Luobotou (AI工作台) fork.
# Runs scripts/pack/build_win.ps1 with Luobotou branding.
# Run from repo root or any directory — the script resolves paths automatically.

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
Set-Location $RepoRoot

if (-not $env:APP_NAME)              { $env:APP_NAME = "Luobotou" }
if (-not $env:APP_DISPLAY_NAME)      { $env:APP_DISPLAY_NAME = "AI工作台" }
if (-not $env:QWENPAW_DESKTOP_TITLE) { $env:QWENPAW_DESKTOP_TITLE = $env:APP_DISPLAY_NAME }
if (-not $env:FORCE_WHEEL_BUILD)     { $env:FORCE_WHEEL_BUILD = "1" }
if (-not $env:PACK_EXTRAS)           { $env:PACK_EXTRAS = "local" }

& "$RepoRoot\scripts\pack\build_win.ps1"
