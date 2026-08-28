@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\GitHubSetup.ps1" %*
set "EC=%ERRORLEVEL%"
echo.
if not "%EC%"=="0" echo GitHub setup ended with error code %EC%.
pause
exit /b %EC%
