@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\DevTool.ps1" %*
exit /b %ERRORLEVEL%
