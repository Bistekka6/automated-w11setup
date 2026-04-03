@echo off
:: Richiede i privilegi di amministratore in automatico
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Richiesta dei permessi di amministratore...
    PowerShell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Avvio di setup.ps1...
PowerShell -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
