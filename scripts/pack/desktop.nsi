; QwenPaw Desktop NSIS installer. Run makensis from repo root after
; building dist/win-unpacked (see scripts/pack/build_win.ps1).
; Usage: makensis /DQWENPAW_VERSION=1.2.3 /DOUTPUT_EXE=dist\QwenPaw-Setup-1.2.3.exe scripts\pack\desktop.nsi

!include "MUI2.nsh"
!define MUI_ABORTWARNING
; Use custom icon from unpacked env (copied by build_win.ps1)
!define MUI_ICON "${UNPACKED}\icon.ico"
!define MUI_UNICON "${UNPACKED}\icon.ico"

!ifndef QWENPAW_VERSION
  !define QWENPAW_VERSION "0.0.0"
!endif
!ifndef APP_NAME
  !define APP_NAME "QwenPaw"
!endif
!ifndef APP_DISPLAY_NAME
  !define APP_DISPLAY_NAME "QwenPaw Desktop"
!endif
!ifndef OUTPUT_EXE
  !define OUTPUT_EXE "dist\${APP_NAME}-Setup-${QWENPAW_VERSION}.exe"
!endif

Name "${APP_DISPLAY_NAME}"
OutFile "${OUTPUT_EXE}"
InstallDir "$LOCALAPPDATA\${APP_NAME}"
InstallDirRegKey HKCU "Software\${APP_NAME}" "InstallPath"
RequestExecutionLevel user

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

; Pass /DUNPACKED=full_path from build_win.ps1 so path works when cwd != repo root
!ifndef UNPACKED
  !define UNPACKED "dist\win-unpacked"
!endif

Section "${APP_DISPLAY_NAME}" SEC01
  SetOutPath "$INSTDIR"

  ; Kill any running QwenPaw processes before writing files.
  ; python.exe / python3.dll / msvcp140.dll stay locked while the app runs,
  ; causing "cannot open file for writing" errors during upgrade installs.
  DetailPrint "Stopping ${APP_DISPLAY_NAME} if currently running..."
  FileOpen $R0 "$TEMP\qwenpaw_kill.ps1" w
  FileWrite $R0 "Get-Process python* -ErrorAction SilentlyContinue | Where-Object { $$_.Path -like '*${APP_NAME}*' } | Stop-Process -Force -ErrorAction SilentlyContinue$\nStart-Sleep -Milliseconds 1500"
  FileClose $R0
  ExecWait 'powershell -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "$TEMP\qwenpaw_kill.ps1"'
  Delete "$TEMP\qwenpaw_kill.ps1"

  File /r "${UNPACKED}\*.*"
  WriteRegStr HKCU "Software\${APP_NAME}" "InstallPath" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Main shortcut - uses VBS to hide console window
  CreateShortcut "$SMPROGRAMS\${APP_DISPLAY_NAME}.lnk" "$INSTDIR\${APP_DISPLAY_NAME}.vbs" "" "$INSTDIR\icon.ico" 0
  CreateShortcut "$DESKTOP\${APP_DISPLAY_NAME}.lnk" "$INSTDIR\${APP_DISPLAY_NAME}.vbs" "" "$INSTDIR\icon.ico" 0
  
  ; Debug shortcut - shows console window for troubleshooting
  CreateShortcut "$SMPROGRAMS\${APP_DISPLAY_NAME} (Debug).lnk" "$INSTDIR\${APP_DISPLAY_NAME} (Debug).bat" "" "$INSTDIR\icon.ico" 0
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${APP_DISPLAY_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_DISPLAY_NAME} (Debug).lnk"
  Delete "$DESKTOP\${APP_DISPLAY_NAME}.lnk"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "Software\${APP_NAME}"
SectionEnd
