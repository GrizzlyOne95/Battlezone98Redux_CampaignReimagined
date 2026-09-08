@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-ModDbHandoff.ps1"
set "HANDOFF_EXIT=%ERRORLEVEL%"
if not "%HANDOFF_EXIT%"=="0" echo Mod DB handoff failed. Review the message above.
pause
exit /b %HANDOFF_EXIT%
