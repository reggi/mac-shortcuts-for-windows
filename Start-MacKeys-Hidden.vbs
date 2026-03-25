Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\MacKeysTray.ps1""", 0, False
