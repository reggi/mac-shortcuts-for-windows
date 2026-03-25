@echo off
:: Double-click this to start Mac Keys in the system tray (by the clock).
:: Right-click the blue ⌘ icon to access Preferences / Pause / Exit.
start "" powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0MacKeysTray.ps1"
