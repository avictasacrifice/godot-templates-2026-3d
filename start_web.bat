@echo off
setlocal
cd /d "%~dp0"

set "PY="
python --version >nul 2>&1 && set "PY=python"
if not defined PY (
    py -3 --version >nul 2>&1 && set "PY=py -3"
)

if not defined PY (
    echo Python 3 not found.
    echo Install it from https://www.python.org/downloads/
    echo and tick "Add python.exe to PATH" in the installer.
    echo If Python is installed, disable the Microsoft Store alias:
    echo Settings - Apps - Advanced app settings - App execution aliases
    pause
    exit /b 1
)

%PY% "%~dp0serve.py"
if errorlevel 1 pause
