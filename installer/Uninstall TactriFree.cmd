@echo off
rem Uninstall TactriFree.cmd - removes TactriFree on Windows 7 / 8 / 8.1: starts TactriFree-Run.cmd as Administrator.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~dp0TactriFree-Run.cmd' -ArgumentList 'uninstall'"
if errorlevel 1 (echo. & echo Could not start the uninstaller as Administrator. & pause)
