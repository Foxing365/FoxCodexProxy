[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "build")
)

$ErrorActionPreference = "Stop"

$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "找不到 .NET Framework 4.x C# 编译器 csc.exe。请在 Windows 功能中启用 .NET Framework 4.x。"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$source = Join-Path $PSScriptRoot "CodexAutoProxy.cs"
$output = Join-Path $OutputDirectory "CodexAutoProxy.exe"
$compileSource = Join-Path $OutputDirectory "CodexAutoProxy.compile.cs"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($compileSource, [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8), $utf8Bom)

try {
    & $compiler /nologo /target:winexe /optimize+ /platform:anycpu `
        /reference:System.dll `
        /reference:System.Core.dll `
        /reference:System.Drawing.dll `
        /reference:System.Windows.Forms.dll `
        "/out:$output" $compileSource
} finally {
    Remove-Item -LiteralPath $compileSource -Force -ErrorAction SilentlyContinue
}

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $output)) {
    throw "编译 CodexAutoProxy.exe 失败，退出代码 $LASTEXITCODE。"
}

Write-Host "已生成 $output"
