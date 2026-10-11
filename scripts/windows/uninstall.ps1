[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Start-Sleep -Milliseconds 500
$installRoot = Join-Path $env:LOCALAPPDATA "CodexAutoProxy"
$manifestPath = Join-Path $installRoot "shortcut-manifest.json"
$exe = Join-Path $installRoot "CodexAutoProxy.exe"
$configHelper = Join-Path $installRoot 'codex-config.ps1'
if (Test-Path -LiteralPath $configHelper) {
    . $configHelper
    Restore-CodexSystemProxy $installRoot
}

if (Test-Path -LiteralPath $exe) {
    Start-Process -FilePath $exe -ArgumentList "--exit" -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
}
Get-Process -Name "CodexAutoProxy" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$backupPath = "HKCU:\Software\CodexAutoProxy\EnvironmentBackup"
$proxyNames = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")
if (Test-Path -LiteralPath $backupPath) {
    $backup = Get-ItemProperty -LiteralPath $backupPath
    foreach ($name in $proxyNames) {
        $saved = $backup.PSObject.Properties[$name + "_Saved"]
        if (-not $saved) { continue }
        $managedProperty = $backup.PSObject.Properties[$name + "_Managed"]
        $managed = if ($managedProperty) { [string]$managedProperty.Value } else { $null }
        $current = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::User)
        if ($current -ne $managed) { continue }
        $existedProperty = $backup.PSObject.Properties[$name + "_Existed"]
        $existed = $existedProperty -and ([int]$existedProperty.Value -ne 0)
        $originalProperty = $backup.PSObject.Properties[$name + "_Original"]
        $original = if ($originalProperty) { [string]$originalProperty.Value } else { $null }
        [Environment]::SetEnvironmentVariable($name, $(if ($existed) { $original } else { $null }), [EnvironmentVariableTarget]::User)
    }
    Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
}

$envFile = Join-Path $env:USERPROFILE ".codex\.env"
if (Test-Path -LiteralPath $envFile) {
    $begin = "# BEGIN codex-auto-proxy-windows"
    $end = "# END codex-auto-proxy-windows"
    $inside = $false
    $output = New-Object System.Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($envFile, [Text.Encoding]::UTF8)) {
        if ($line.Trim() -eq $begin) { $inside = $true; continue }
        if ($inside -and $line.Trim() -eq $end) { $inside = $false; continue }
        if (-not $inside) { $output.Add($line) }
    }
    while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) { $output.RemoveAt($output.Count - 1) }
    if ($output.Count -eq 0) {
        Remove-Item -LiteralPath $envFile -Force
    } else {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllLines($envFile, $output, $utf8NoBom)
    }
}

if (Test-Path -LiteralPath $manifestPath) {
    $records = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
    foreach ($record in $records) {
        if ($record.Created) {
            if (Test-Path -LiteralPath $record.OriginalPath) { Remove-Item -LiteralPath $record.OriginalPath -Force }
        } elseif ($record.BackupPath -and (Test-Path -LiteralPath $record.BackupPath)) {
            $parent = Split-Path -Parent $record.OriginalPath
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            Copy-Item -LiteralPath $record.BackupPath -Destination $record.OriginalPath -Force
        } else {
            throw "无法恢复快捷方式，备份缺失: $($record.OriginalPath)。安装目录已保留。"
        }
    }
}

$runPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Remove-ItemProperty -Path $runPath -Name "CodexAutoProxy" -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexAutoProxy" -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath "HKCU:\Software\CodexAutoProxy") {
    $children = @(Get-ChildItem -LiteralPath "HKCU:\Software\CodexAutoProxy" -ErrorAction SilentlyContinue)
    if ($children.Count -eq 0) { Remove-Item -LiteralPath "HKCU:\Software\CodexAutoProxy" -Force -ErrorAction SilentlyContinue }
}
$programGroup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Codex Auto Proxy"
Remove-Item -LiteralPath $programGroup -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
    Write-Host "卸载完成。"
} else {
    Write-Host "未发现安装目录；启动项清理已完成。"
}

if ($PSCommandPath -and $env:TEMP -and $PSCommandPath.StartsWith($env:TEMP, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
