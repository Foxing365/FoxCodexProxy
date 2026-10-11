$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $env:TEMP ('FoxCodexProxy-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$exe = Join-Path $testRoot 'BridgeCheck.exe'
& $compiler /nologo /target:exe /main:CodexAutoProxy.BridgeCheck /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll "/out:$exe" (Join-Path $root 'scripts\windows\CodexAutoProxy.cs') (Join-Path $PSScriptRoot 'BridgeCheck.cs')
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }
& $exe
if ($LASTEXITCODE -ne 0) { throw 'Bridge regression test failed.' }
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'scripts\windows') -Filter '*.ps1') {
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw ($file.Name + ($errors | Out-String)) }
}
Write-Output 'POWERSHELL_PARSE_OK'
