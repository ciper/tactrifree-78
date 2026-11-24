@echo off
rem installer.cmd - installs TactriFree on Windows 7 / 8 / 8.1: starts TactriFree-Run.cmd as Administrator (Windows asks for permission).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~dp0TactriFree-Run.cmd' -ArgumentList 'install'"
if errorlevel 1 (echo. & echo Could not start the installer as Administrator. & pause)
