@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\VerifyAll.ps1" %*
exit /b %ERRORLEVEL%
