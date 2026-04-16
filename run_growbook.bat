@echo off
set PATH=C:\flutter\bin;%PATH%
cd /d "%~dp0"

:: Start scanner in a minimized background window
start /min "GrowBook Scanner" "%~dp0run_scanner.bat"

flutter run -d chrome
pause
