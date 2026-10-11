@echo off
setlocal
set "TEMP_UNINSTALL=%TEMP%\CodexAutoProxy-uninstall.ps1"
copy /Y "%~dp0uninstall.ps1" "%TEMP_UNINSTALL%" >nul
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP_UNINSTALL%"
endlocal & exit /b 0
