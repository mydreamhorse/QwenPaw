# One-click build: console -> conda-pack -> NSIS .exe. Run from repo root.
# Requires: conda, node/npm (for console), NSIS (makensis) on PATH.

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
Set-Location $RepoRoot
Write-Host "[build_win] REPO_ROOT=$RepoRoot"
$PackDir = $PSScriptRoot
$Dist = if ($env:DIST) { $env:DIST } else { "dist" }
$Archive = Join-Path $Dist "qwenpaw-env.zip"
$Unpacked = Join-Path $Dist "win-unpacked"
$NsiPath = Join-Path $PackDir "desktop.nsi"

$ForceWheelBuild = $env:FORCE_WHEEL_BUILD -eq "1"
$PackExtras = if ($env:PACK_EXTRAS) { $env:PACK_EXTRAS } else { "local" }
$AppName = if ($env:APP_NAME) { $env:APP_NAME } else { "QwenPaw" }
$AppDisplayName = if ($env:APP_DISPLAY_NAME) { $env:APP_DISPLAY_NAME } else { "QwenPaw Desktop" }
$DesktopTitle = if ($env:QWENPAW_DESKTOP_TITLE) { $env:QWENPAW_DESKTOP_TITLE } else { $AppDisplayName }

# Packages affected by conda-unpack bug on Windows (conda-pack Issue #154)
# conda-unpack corrupts Python string escaping when replacing path prefixes.
# Example: "\\\\?\\" (correct) -> "\\" (SyntaxError)
# Solution: Reinstall these packages after conda-unpack to restore correct files.
# See: issue.md, scripts/pack/WINDOWS_FIX.md
$CondaUnpackAffectedPackages = @(
  "huggingface_hub"  # Uses Windows extended-length path prefix (\\?\)
  "discord.py"       # ARG_NAME_SUBREGEX contains \\?\* which gets corrupted
)

New-Item -ItemType Directory -Force -Path $Dist | Out-Null

Write-Host "== Building wheel (includes console frontend) =="
# Skip wheel_build if dist already has a wheel for current version
$VersionFile = Join-Path $RepoRoot "src\qwenpaw\__version__.py"
$CurrentVersion = ""
if (Test-Path $VersionFile) {
  $m = (Get-Content $VersionFile -Raw) -match '__version__\s*=\s*"([^"]+)"'
  if ($m) { $CurrentVersion = $Matches[1] }
}
$RunWheelBuild = $true
if ($CurrentVersion) {
  $wheelGlob = Join-Path $Dist "qwenpaw-$CurrentVersion-*.whl"
  $existingWheels = Get-ChildItem -Path $wheelGlob -ErrorAction SilentlyContinue
  if ($existingWheels.Count -gt 0) {
    if ($ForceWheelBuild) {
      Write-Host "FORCE_WHEEL_BUILD is set; removing existing wheel files: $($existingWheels | ForEach-Object { $_.Name })"
      $existingWheels | Remove-Item -Force
      # Also clean up any other stale wheels
      $oldWheels = Get-ChildItem -Path (Join-Path $Dist "qwenpaw-*.whl") -ErrorAction SilentlyContinue
      if ($oldWheels.Count -gt 0) {
        Write-Host "Removing old wheel files: $($oldWheels | ForEach-Object { $_.Name })"
        $oldWheels | Remove-Item -Force
      }
    } else {
      Write-Host "dist/ already has wheel for version $CurrentVersion, skipping."
      $RunWheelBuild = $false
    }
  } else {
    # Clean up old wheels to avoid confusion
    $oldWheels = Get-ChildItem -Path (Join-Path $Dist "qwenpaw-*.whl") -ErrorAction SilentlyContinue
    if ($oldWheels.Count -gt 0) {
      Write-Host "Removing old wheel files: $($oldWheels | ForEach-Object { $_.Name })"
      $oldWheels | Remove-Item -Force
    }
  }
}
if ($RunWheelBuild) {
  $WheelBuildScript = Join-Path $RepoRoot "scripts\wheel_build.ps1"
  if (-not (Test-Path $WheelBuildScript)) {
    throw "wheel_build.ps1 not found: $WheelBuildScript"
  }
  & $WheelBuildScript
  if ($LASTEXITCODE -ne 0) { throw "wheel_build.ps1 failed with exit code $LASTEXITCODE" }
}

Write-Host "== Building conda-packed env =="
if ($env:SKIP_ENV_BUILD -and (Test-Path $Archive)) {
  Write-Host "SKIP_ENV_BUILD is set; reusing $Archive"
} else {
  & python $PackDir\build_common.py --output $Archive --format zip --cache-wheels --extras $PackExtras
  if ($LASTEXITCODE -ne 0) {
    throw "build_common.py failed with exit code $LASTEXITCODE"
  }
  if (-not (Test-Path $Archive)) {
    throw "Archive not created: $Archive"
  }
}

Write-Host "== Unpacking env =="
if (Test-Path $Unpacked) { Remove-Item -Recurse -Force $Unpacked }
Expand-Archive -Path $Archive -DestinationPath $Unpacked -Force
$unpackedRoot = Get-ChildItem -Path $Unpacked -ErrorAction SilentlyContinue | Measure-Object
Write-Host "[build_win] Unpacked entries in $Unpacked : $($unpackedRoot.Count)"

# Resolve env root: conda-pack usually puts python.exe at archive root; allow one nested dir.
$EnvRoot = $Unpacked
if (-not (Test-Path (Join-Path $EnvRoot "python.exe"))) {
  $found = Get-ChildItem -Path $Unpacked -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "python.exe") } |
    Select-Object -First 1
  if ($found) { $EnvRoot = $found.FullName; Write-Host "[build_win] Env root: $EnvRoot" }
}
if (-not (Test-Path (Join-Path $EnvRoot "python.exe"))) {
  throw "python.exe not found in unpacked env (checked $Unpacked and one level down)."
}
if (-not [System.IO.Path]::IsPathRooted($EnvRoot)) {
  $EnvRoot = Join-Path $RepoRoot $EnvRoot
}
Write-Host "[build_win] python.exe found at env root: $EnvRoot"

# Rewrite prefix in packed env so paths point to current location (required after move).
$CondaUnpack = Join-Path $EnvRoot "Scripts\conda-unpack.exe"
if (Test-Path $CondaUnpack) {
  Write-Host "[build_win] Running conda-unpack..."
  & $CondaUnpack
  if ($LASTEXITCODE -ne 0) { throw "conda-unpack failed with exit code $LASTEXITCODE" }
  
  # Fix conda-unpack bug: it corrupts Python string escaping on Windows
  # See: issue.md and https://github.com/conda/conda-pack/issues/154
  # Solution: Reinstall affected packages using cached wheels
  Write-Host "[build_win] Fixing conda-unpack corruption by reinstalling affected packages..."
  $WheelsCache = Join-Path $RepoRoot ".cache\conda_unpack_wheels"
  if (Test-Path $WheelsCache) {
    $pythonExe = Join-Path $EnvRoot "python.exe"
    
    foreach ($pkg in $CondaUnpackAffectedPackages) {
      Write-Host "  Reinstalling $pkg..."
      & $pythonExe -m pip install --force-reinstall --no-deps `
        --find-links $WheelsCache --no-index $pkg
      if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARN: Failed to reinstall $pkg (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
      }
    }
    
    # Verify the fix worked
    Write-Host "[build_win] Verifying fix..."
    & $pythonExe -c "from huggingface_hub import file_download; print('✓ huggingface_hub import OK')"
    if ($LASTEXITCODE -ne 0) {
      throw "CRITICAL: huggingface_hub still has import errors after reinstall. See issue.md"
    }
    & $pythonExe -c "import discord; print('✓ discord.py import OK')"
    if ($LASTEXITCODE -ne 0) {
      throw "CRITICAL: discord.py still has import errors after reinstall."
    }
    Write-Host "[build_win] ✓ conda-unpack corruption fixed successfully."
  } else {
    Write-Host "[build_win] WARN: wheels_cache not found at $WheelsCache" -ForegroundColor Yellow
    Write-Host "[build_win] WARN: Cannot fix conda-unpack corruption. App may fail to start." -ForegroundColor Yellow
  }
} else {
  Write-Host "[build_win] WARN: conda-unpack.exe not found at $CondaUnpack, skipping."
}

Write-Host "== Pre-compiling Python bytecode for faster startup =="
$pythonExe = Join-Path $EnvRoot "python.exe"
if (Test-Path $pythonExe) {
  Write-Host "[build_win] Compiling all .py files to .pyc..."
  $compileStart = Get-Date
  
  # Compile all Python files to bytecode
  # -q: quiet mode (only show errors)
  # -j 0: use all CPU cores for parallel compilation
  & $pythonExe -m compileall -q -j 0 $EnvRoot
  
  if ($LASTEXITCODE -eq 0) {
    $compileEnd = Get-Date
    $compileTime = ($compileEnd - $compileStart).TotalSeconds
    Write-Host "[build_win] ✓ Bytecode compilation completed in $($compileTime.ToString('F1')) seconds"
    
    # Count compiled files for reporting
    $pycCount = (Get-ChildItem -Path $EnvRoot -Recurse -Filter "*.pyc" -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "[build_win] Generated $pycCount .pyc files (these will be included in installer)"
  } else {
    Write-Host "[build_win] WARN: Bytecode compilation had some errors (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
    Write-Host "[build_win] This is usually not critical - app will compile on first run" -ForegroundColor Yellow
  }
} else {
  Write-Host "[build_win] WARN: python.exe not found at $pythonExe, skipping bytecode compilation" -ForegroundColor Yellow
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Main launcher .bat (will be hidden by VBS)
$LauncherBat = Join-Path $EnvRoot "$AppDisplayName.bat"
$LauncherBatContent = @"
@echo off
cd /d "%~dp0"

REM Isolate packaged Python from user site-packages to prevent conflicts
set "PYTHONNOUSERSITE=1"

REM Preserve system PATH for accessing system commands
REM Prepend packaged env to PATH so packaged Python takes precedence
set "PATH=%~dp0;%~dp0Scripts;%PATH%"

REM Log level: env var QWENPAW_LOG_LEVEL or default to "info"
if not defined QWENPAW_LOG_LEVEL set "QWENPAW_LOG_LEVEL=info"

REM Desktop window title
if not defined QWENPAW_DESKTOP_TITLE set "QWENPAW_DESKTOP_TITLE=$DesktopTitle"

REM Set SSL certificate paths for packaged environment
REM Use temp file to avoid for /f blocking issue in bat scripts
set "CERT_TMP=%TEMP%\qwenpaw_cert_%RANDOM%.txt"
"%~dp0python.exe" -u -c "import certifi; print(certifi.where())" > "%CERT_TMP%" 2>nul
set /p CERT_FILE=<"%CERT_TMP%"
del "%CERT_TMP%" 2>nul
if defined CERT_FILE (
  if exist "%CERT_FILE%" (
    set "SSL_CERT_FILE=%CERT_FILE%"
    set "REQUESTS_CA_BUNDLE=%CERT_FILE%"
    set "CURL_CA_BUNDLE=%CERT_FILE%"
  )
)

if not exist "%USERPROFILE%\.qwenpaw\config.json" (
  "%~dp0python.exe" -u -m qwenpaw init --defaults --accept-security
)
"%~dp0python.exe" -u -m qwenpaw desktop --log-level %QWENPAW_LOG_LEVEL%
"@
[System.IO.File]::WriteAllText($LauncherBat, $LauncherBatContent, $Utf8NoBom)

# Debug launcher .bat (shows console)
$DebugBat = Join-Path $EnvRoot "$AppDisplayName (Debug).bat"
$DebugBatContent = @"
@echo off
cd /d "%~dp0"

REM Isolate packaged Python from user site-packages to prevent conflicts
set "PYTHONNOUSERSITE=1"

REM Preserve system PATH for accessing system commands
REM Prepend packaged env to PATH so packaged Python takes precedence
set "PATH=%~dp0;%~dp0Scripts;%PATH%"

REM Debug mode: use debug log level by default (can override with QWENPAW_LOG_LEVEL)
if not defined QWENPAW_LOG_LEVEL set "QWENPAW_LOG_LEVEL=debug"

REM Desktop window title
if not defined QWENPAW_DESKTOP_TITLE set "QWENPAW_DESKTOP_TITLE=$DesktopTitle"

REM Set SSL certificate paths for packaged environment
REM Use temp file to avoid for /f blocking issue in bat scripts
set "CERT_TMP=%TEMP%\qwenpaw_cert_%RANDOM%.txt"
"%~dp0python.exe" -u -c "import certifi; print(certifi.where())" > "%CERT_TMP%" 2>nul
set /p CERT_FILE=<"%CERT_TMP%"
del "%CERT_TMP%" 2>nul
if defined CERT_FILE (
  if exist "%CERT_FILE%" (
    set "SSL_CERT_FILE=%CERT_FILE%"
    set "REQUESTS_CA_BUNDLE=%CERT_FILE%"
    set "CURL_CA_BUNDLE=%CERT_FILE%"
  )
)

echo ====================================
echo $AppDisplayName - Debug Mode
echo ====================================
echo Working Directory: %cd%
echo Python: "%~dp0python.exe"
echo PATH: %PATH%
echo PYTHONNOUSERSITE: %PYTHONNOUSERSITE%
echo Log Level: %QWENPAW_LOG_LEVEL%
echo QWENPAW_DESKTOP_TITLE: %QWENPAW_DESKTOP_TITLE%
echo SSL_CERT_FILE: %SSL_CERT_FILE%
echo REQUESTS_CA_BUNDLE: %REQUESTS_CA_BUNDLE%
echo CURL_CA_BUNDLE: %CURL_CA_BUNDLE%
echo.
if not exist "%USERPROFILE%\.qwenpaw\config.json" (
  echo [Init] Creating config...
  "%~dp0python.exe" -u -m qwenpaw init --defaults --accept-security
)
echo [Launch] Starting $AppDisplayName with log-level=%QWENPAW_LOG_LEVEL%...
echo Press Ctrl+C to stop
echo.
"%~dp0python.exe" -u -m qwenpaw desktop --log-level %QWENPAW_LOG_LEVEL%
echo.
echo [Exit] $AppDisplayName closed
pause
"@
[System.IO.File]::WriteAllText($DebugBat, $DebugBatContent, $Utf8NoBom)

# VBScript launcher (no console window)
$LauncherVbs = Join-Path $EnvRoot "$AppDisplayName.vbs"
$LauncherVbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
batPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\$AppDisplayName.bat"
WshShell.Run Chr(34) & batPath & Chr(34), 0, False
Set WshShell = Nothing
"@
[System.IO.File]::WriteAllText($LauncherVbs, $LauncherVbsContent, $Utf8NoBom)

# Create qwenpaw.cmd wrapper in env root so "qwenpaw" resolves to this
# instead of Scripts\qwenpaw.exe whose embedded Python path may be stale
# after conda-pack/unpack.
$QwenpawCmd = Join-Path $EnvRoot "qwenpaw.cmd"
@"
@"%~dp0python.exe" -u -m qwenpaw %*
"@ | Set-Content -Path $QwenpawCmd -Encoding ASCII

# Copy icon.ico to env root so NSIS can find it
$IconSrc = Join-Path $PackDir "assets\icon.ico"
if (Test-Path $IconSrc) {
  Copy-Item $IconSrc -Destination $EnvRoot -Force
  Write-Host "[build_win] Copied icon.ico to env root"
} else {
  Write-Host "[build_win] WARN: icon.ico not found at $IconSrc"
}

Write-Host "== Building NSIS installer =="

# Debug: Print EnvRoot directory contents
Write-Host "=== EnvRoot=$EnvRoot ==="
Write-Host "=== EnvRoot top files ==="
Get-ChildItem -LiteralPath $EnvRoot -Force | Select-Object -First 50 | ForEach-Object { Write-Host $_.FullName }

# Prioritize version from __version__.py to ensure accuracy
$Version = $CurrentVersion
if (-not $Version) {
  # Fallback: try to get version from packed env metadata
  try {
    $Version = (& (Join-Path $EnvRoot "python.exe") -c "from importlib.metadata import version; print(version('qwenpaw'))" 2>&1) -replace '\s+$', ''
    Write-Host "[build_win] Using version from packed env metadata: $Version"
  } catch {
    Write-Host "[build_win] version from packed env failed: $_"
  }
}
if (-not $Version) { $Version = "0.0.0"; Write-Host "[build_win] WARN: Using fallback version 0.0.0" }
Write-Host "[build_win] Version determined: $Version"
Write-Host "[build_win] QWENPAW_VERSION=$Version OUTPUT_EXE will be under $Dist"
$OutInstaller = Join-Path (Join-Path $RepoRoot $Dist) "$AppName-Setup-$Version.exe"
# Pass absolute paths to NSIS (keep backslashes).
$UnpackedFull = (Resolve-Path $EnvRoot).Path
$OutputExeNsi = [System.IO.Path]::GetFullPath($OutInstaller)
$nsiArgs = @(
  "/DQWENPAW_VERSION=$Version",
  "/DAPP_NAME=$AppName",
  "/DAPP_DISPLAY_NAME=$AppDisplayName",
  "/DOUTPUT_EXE=$OutputExeNsi",
  "/DUNPACKED=$UnpackedFull",
  $NsiPath
)

# Check makensis availability; auto-add common install locations to PATH if needed
$makensisPath = $null
try { $makensisPath = (Get-Command makensis -ErrorAction Stop).Source } catch {}
if (-not $makensisPath) {
  $nsisSearchPaths = @(
    "D:\tools\NSIS",
    "C:\Program Files (x86)\NSIS",
    "C:\Program Files\NSIS"
  )
  foreach ($p in $nsisSearchPaths) {
    if (Test-Path (Join-Path $p "makensis.exe")) {
      $env:PATH = "$p;$env:PATH"
      $makensisPath = Join-Path $p "makensis.exe"
      Write-Host "[build_win] Auto-added NSIS to PATH from: $p"
      break
    }
  }
}
if (-not $makensisPath) {
  throw "makensis not found. Install NSIS to one of: $($nsisSearchPaths -join ', '), or add makensis.exe to PATH."
}
Write-Host "[build_win] makensis: $makensisPath"

Write-Host "[build_win] Running: makensis $($nsiArgs -join ' ')"
Write-Host "=== NSIS will compile from: $NsiPath ==="
Write-Host "=== NSIS unpacked source: $UnpackedFull ==="
Write-Host "=== NSIS output installer: $OutputExeNsi ==="
$nsisOutput = & makensis @nsiArgs 2>&1 | Out-String
Write-Host "=== NSIS Output Begin ==="
Write-Host $nsisOutput
Write-Host "=== NSIS Output End ==="
$makensisExit = $LASTEXITCODE
Write-Host "[build_win] makensis exit code: $makensisExit"
if ($makensisExit -ne 0) {
  Write-Host "ERROR: makensis compilation failed!"
  Write-Host "Check the NSIS output above for specific errors."
  throw "makensis failed with exit code $makensisExit"
}
if (-not (Test-Path $OutInstaller)) {
  throw "NSIS did not create installer: $OutInstaller"
}
Write-Host "== Built $OutInstaller =="
