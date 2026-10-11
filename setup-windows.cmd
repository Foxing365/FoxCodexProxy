@echo off
setlocal
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0scripts\windows\setup.ps1"
endlocal
