<#
.SYNOPSIS
    Mac-style keyboard shortcuts for Windows — console version.
    The Command key (left of spacebar) registers as Left Win on Windows.
    This script intercepts it and makes it behave like Mac Command.
    Uses ONLY built-in Windows components — zero third-party software.
#>

$engineCode  = Get-Content "$PSScriptRoot\MacKeysEngine.cs" -Raw
$consoleCode = Get-Content "$PSScriptRoot\MacKeysConsole.cs" -Raw

Add-Type -TypeDefinition ($engineCode + $consoleCode) -ReferencedAssemblies System.Windows.Forms, System.Drawing

[MacKeysConsole]::Run()
