@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\VerifyAll.ps1" %*
set EXITCODE=%ERRORLEVEL%
echo.
if %EXITCODE%==0 (
    echo Finished successfully.
) else (
    echo Finished with errors ^(exit code %EXITCODE%^). Scroll up to see what failed.
)
pause
exit /b %EXITCODE%
