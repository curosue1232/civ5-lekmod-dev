@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\InstallAll.ps1" %*
exit /b %ERRORLEVEL%
