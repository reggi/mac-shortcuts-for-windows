@echo off
:: Double-click this to start Mac Keys in a console window.
:: Close the window or press Ctrl+C to stop.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0src\MacKeysConsoleHost.ps1"
pause
