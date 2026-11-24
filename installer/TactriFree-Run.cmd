@echo off
rem TactriFree-Run.cmd - runs TactriFree-Setup.ps1 in 64-bit PowerShell and ALWAYS keeps the window open at the end,
rem even when PowerShell cannot start the script. Started as Administrator by installer.cmd / "Uninstall TactriFree.cmd".
rem   TactriFree-Run.cmd install | uninstall
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "ARG="
if /i "%~1"=="uninstall" set "ARG=-Uninstall"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0TactriFree-Setup.ps1" %ARG% -NoPause
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (echo Setup finished OK.) else (echo Setup FAILED ^(exit code %RC%^). Please send this whole window to the TactriFree developer.)
echo.
pause
