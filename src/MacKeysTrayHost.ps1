<#
.SYNOPSIS
    Mac-style keyboard shortcuts for Windows — system tray version.
    Sits in the notification area (by the clock) with a ⌘ icon.
    Right-click the icon for Preferences / Pause / Exit.
    Auto-disables when excluded apps (e.g. Steam, games) are in the foreground.
    No console window.
#>

$engineCode = Get-Content "$PSScriptRoot\MacKeysEngine.cs" -Raw
$trayCode   = Get-Content "$PSScriptRoot\MacKeysTray.cs" -Raw

Add-Type -TypeDefinition ($engineCode + $trayCode) -ReferencedAssemblies System.Windows.Forms, System.Drawing

[MacKeysTray]::VbsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "RunTray.vbs"
[MacKeysTray]::Main()
