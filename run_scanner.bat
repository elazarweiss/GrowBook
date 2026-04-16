@echo off
setlocal
cd /d "%~dp0"

:: Load .env file
for /f "usebackq tokens=1* delims==" %%a in (".env") do (
    if "%%a"=="ANTHROPIC_API_KEY" set ANTHROPIC_API_KEY=%%b
)

if "%ANTHROPIC_API_KEY%"=="" (
    echo ERROR: ANTHROPIC_API_KEY not found in .env
    pause
    exit /b 1
)

echo Starting GrowBook Scanner...
python growbook_scanner.py
pause
