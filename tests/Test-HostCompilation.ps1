$ErrorActionPreference = "Stop"

$sourceDirectory = Join-Path $PSScriptRoot "..\src"
$sourceFiles = @(
    "MacKeysEngine.cs",
    "MacKeysRules.cs",
    "MacKeysConsole.cs",
    "MacKeysTray.cs"
)

$source = ($sourceFiles | ForEach-Object {
    Get-Content (Join-Path $sourceDirectory $_) -Raw
}) -join [Environment]::NewLine

$outputAssembly = Join-Path ([System.IO.Path]::GetTempPath()) (
    "MacKeys.CompileTest.{0}.dll" -f [Guid]::NewGuid().ToString("N")
)

try {
    Add-Type `
        -TypeDefinition $source `
        -ReferencedAssemblies System.Windows.Forms, System.Drawing `
        -OutputAssembly $outputAssembly

    if (-not (Test-Path $outputAssembly)) {
        throw "The host compilation did not produce an assembly."
    }

    Write-Host "PowerShell host sources compiled successfully."
}
finally {
    Remove-Item $outputAssembly -Force -ErrorAction SilentlyContinue
}