[CmdletBinding()]
param([string]$Version = '2.2.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Use a numeric semantic version.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$stage = Join-Path $dist ('stage-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $stage 'windows'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
foreach ($item in 'scripts','bin','references','setup-windows.cmd','README.md','SKILL.md','AI_GUIDE.md') {
    Copy-Item -LiteralPath (Join-Path $repoRoot $item) -Destination $payload -Recurse -Force
}
$hash = (Get-FileHash -LiteralPath (Join-Path $payload 'bin\windows\CodexAutoProxy.exe')).Hash.ToLowerInvariant()
$expected = (Get-Content -LiteralPath (Join-Path $payload 'bin\windows\SHA256SUMS.txt') -First 1).Split(' ')[0]
if ($hash -ne $expected) { throw 'Tray binary checksum mismatch. Update bin/windows/SHA256SUMS.txt after building.' }
$windowsZip = Join-Path $dist "FoxCodexProxy-Windows-v$Version.zip"
$skillZip = Join-Path $dist "fox-codex-proxy-skill-v$Version.zip"
$setupExe = Join-Path $dist "FoxCodexProxy-Setup-v$Version.exe"
foreach ($output in $windowsZip,$skillZip,$setupExe) {
    if (Test-Path -LiteralPath $output) { throw "Output already exists: $output" }
}
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $windowsZip -CompressionLevel Optimal
$skillFolder = Join-Path $stage 'fox-codex-proxy'
Copy-Item -LiteralPath $payload -Destination $skillFolder -Recurse
Compress-Archive -LiteralPath $skillFolder -DestinationPath $skillZip -CompressionLevel Optimal
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
& $compiler /nologo /target:winexe /optimize+ /platform:anycpu /reference:System.dll /reference:System.Core.dll /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll "/resource:$windowsZip,windows-payload.zip" "/out:$setupExe" (Join-Path $PSScriptRoot 'SetupLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$lines = foreach ($file in $setupExe,$windowsZip,$skillZip) { (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($file) }
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),$lines,(New-Object Text.UTF8Encoding($false)))
Write-Output "Release built: $dist"
