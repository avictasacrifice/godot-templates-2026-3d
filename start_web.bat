@echo off
chcp 65001 >nul
setlocal

cd /d "%~dp0"

python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python не найден. Установите Python 3 и попробуйте снова.
    pause
    exit /b 1
)

echo Запуск локального сервера для веб-версии Godot...
echo После запуска откройте: http://localhost:8060
echo Чтобы остановить сервер — закройте это окно.
echo.

REM Открываем браузер с задержкой 2 сек, чтобы сервер успел подняться
start "" cmd /c "timeout /t 2 >nul & start http://localhost:8060"

python "%~dp0serve.py"

pause