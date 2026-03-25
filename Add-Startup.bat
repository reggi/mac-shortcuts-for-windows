@echo off
:: Creates a shortcut to Start-MacKeys-Hidden.vbs in your Startup folder
:: so Mac Keys launches automatically when you log in.

set "SOURCE=%~dp0Start-MacKeys-Hidden.vbs"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "SHORTCUT=%STARTUP%\Mac Keys.lnk"

if not exist "%SOURCE%" (
    echo ERROR: Start-MacKeys-Hidden.vbs not found next to this script.
    pause
    exit /b 1
)

:: Use PowerShell to create a proper .lnk shortcut
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ws = New-Object -ComObject WScript.Shell;" ^
    "$s = $ws.CreateShortcut('%SHORTCUT%');" ^
    "$s.TargetPath = '%SOURCE%';" ^
    "$s.WorkingDirectory = '%~dp0';" ^
    "$s.Description = 'Mac-style keyboard shortcuts for Windows';" ^
    "$s.Save()"

if exist "%SHORTCUT%" (
    echo SUCCESS: Mac Keys will now start automatically when you log in.
    echo Shortcut created at: %SHORTCUT%
) else (
    echo ERROR: Failed to create shortcut.
)

pause
