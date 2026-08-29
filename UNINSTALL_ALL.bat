@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\UninstallAll.ps1" %*
exit /b %ERRORLEVEL%
