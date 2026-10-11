[CmdletBinding()]
param(
    [string]$CodexExe,
    [int]$ClashPort = 0,
    [int]$ListenPort = 7898,
    [switch]$StartWithWindows,
    [bool]$LaunchCodexOnStart = $true
)

$ErrorActionPreference = "Stop"
$installRoot = Join-Path $env:LOCALAPPDATA "CodexAutoProxy"
$manifestPath = Join-Path $installRoot "shortcut-manifest.json"

function Get-ShortcutTarget([string]$Path) {
    $shell = New-Object -ComObject WScript.Shell
    return $shell.CreateShortcut($Path).TargetPath
}

function Get-ShortcutPaths {
    $roots = @(
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"),
        ([Environment]::GetFolderPath("Desktop")),
        (Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar")
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue
    }
}

function Resolve-CodexExecutable([string]$Requested) {
    if ($Requested) {
        $resolved = (Resolve-Path -LiteralPath $Requested).Path
        if (-not $resolved.EndsWith(".exe", [StringComparison]::OrdinalIgnoreCase)) { throw "-CodexExe 必须指向 exe 文件。" }
        if ($resolved -match '\\bin\\') { throw '请选择 Codex 桌面应用，不能选择 bin 目录里的 Codex CLI。' }
        return $resolved
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $previousConfig = Join-Path $installRoot "config.ini"
    if (Test-Path -LiteralPath $previousConfig) {
        $previous = Get-Content -LiteralPath $previousConfig | Where-Object { $_ -like "CodexExe=*" } | Select-Object -First 1
        if ($previous) { $candidates.Add($previous.Substring("CodexExe=".Length)) }
    }
    foreach ($processName in @("Codex", "ChatGPT")) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue | ForEach-Object {
            try { if ($_.Path) { $candidates.Add($_.Path) } } catch {}
        }
    }
    foreach ($shortcut in Get-ShortcutPaths) {
        try {
            $target = Get-ShortcutTarget $shortcut.FullName
            if ($target -and (($shortcut.BaseName -match "Codex|ChatGPT") -or ($target -match "Codex|ChatGPT"))) {
                $candidates.Add($target)
            }
        } catch {}
    }
    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Codex\Codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\ChatGPT\ChatGPT.exe"),
        (Join-Path $env:LOCALAPPDATA "Codex\Codex.exe"),
        (Join-Path $env:ProgramFiles "Codex\Codex.exe"),
        (Join-Path $env:ProgramFiles "ChatGPT\ChatGPT.exe")
    )) { if ($path) { $candidates.Add($path) } }

    Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($filename in 'ChatGPT.exe', 'Codex.exe') {
            $candidates.Add((Join-Path $_.InstallLocation "app\$filename"))
        }
    }
    $valid = @($candidates | Where-Object { $_ -and $_ -notmatch '\\bin\\' -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique)
    $found = $valid | Where-Object { ([IO.Path]::GetFileName($_)) -match '^Codex\.exe$' } | Select-Object -First 1
    if (-not $found) { $found = $valid | Select-Object -First 1 }
    if (-not $found) { throw "未找到 Codex Desktop。请重新运行并传入 -CodexExe 'C:\路径\Codex.exe'。" }
    return (Resolve-Path -LiteralPath $found).Path
}

function Resolve-ClashPort([int]$Requested) {
    if ($Requested -gt 0 -and $Requested -le 65535) { return $Requested }
    $configs = @(
        (Join-Path $env:APPDATA "io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml"),
        (Join-Path $env:APPDATA "clash-verge-rev\clash-verge.yaml"),
        (Join-Path $env:LOCALAPPDATA "io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml")
    )
    foreach ($config in $configs) {
        if (-not (Test-Path -LiteralPath $config)) { continue }
        $match = [regex]::Match(([IO.File]::ReadAllText($config)), '(?m)^\s*mixed-port\s*:\s*(\d+)')
        if ($match.Success) {
            $value = [int]$match.Groups[1].Value
            if ($value -gt 0 -and $value -le 65535) { return $value }
        }
    }
    Write-Warning "未发现 Clash Verge mixed-port，暂用 7897。端口不同请传入 -ClashPort。"
    return 7897
}

if ($ListenPort -lt 1 -or $ListenPort -gt 65535) { throw "-ListenPort 必须在 1 到 65535 之间。" }
$CodexExe = Resolve-CodexExecutable $CodexExe
$ClashPort = Resolve-ClashPort $ClashPort
if ($ListenPort -eq $ClashPort) { throw '桥接端口和 Clash 端口不能相同。' }

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

$running = Get-Process -Name "CodexAutoProxy" -ErrorAction SilentlyContinue
if ($running) {
    $oldExe = Join-Path $installRoot "CodexAutoProxy.exe"
    if (Test-Path -LiteralPath $oldExe) { Start-Process -FilePath $oldExe -ArgumentList "--exit" -WindowStyle Hidden }
    $stopDeadline = (Get-Date).AddSeconds(8)
    do { Start-Sleep -Milliseconds 200 } while ((Get-Process -Name 'CodexAutoProxy' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $stopDeadline)
    Get-Process -Name "CodexAutoProxy" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

$prebuiltRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\bin\windows"))
$prebuiltExe = Join-Path $prebuiltRoot "CodexAutoProxy.exe"
if (Test-Path -LiteralPath $prebuiltExe) {
    Copy-Item -LiteralPath $prebuiltExe -Destination (Join-Path $installRoot "CodexAutoProxy.exe") -Force
    $prebuiltConfig = Join-Path $prebuiltRoot "CodexAutoProxy.exe.config"
    if (Test-Path -LiteralPath $prebuiltConfig) {
        Copy-Item -LiteralPath $prebuiltConfig -Destination (Join-Path $installRoot "CodexAutoProxy.exe.config") -Force
    }
} else {
    & (Join-Path $PSScriptRoot "build.ps1") -OutputDirectory $installRoot
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "构建失败。" }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "CodexAutoProxy.cs") -Destination $installRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "uninstall.ps1") -Destination $installRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "uninstall.cmd") -Destination $installRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "status.ps1") -Destination $installRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "status.cmd") -Destination $installRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "codex-config.ps1") -Destination $installRoot -Force
. (Join-Path $installRoot 'codex-config.ps1')
Enable-CodexSystemProxy $installRoot $CodexExe

$config = @(
    "CodexExe=$CodexExe",
    "ClashHost=127.0.0.1",
    "ClashPort=$ClashPort",
    "ListenPort=$ListenPort",
    "ProbeSeconds=30",
    "LaunchCodexOnStart=$($LaunchCodexOnStart.ToString().ToLowerInvariant())"
)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines((Join-Path $installRoot "config.ini"), $config, $utf8NoBom)

# Migrate v1/v2 installations that redirected Codex shortcuts. The current
# design leaves every Codex shortcut untouched and uses proxy environment variables.
if (Test-Path -LiteralPath $manifestPath) {
    $records = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
    foreach ($record in $records) {
        if ($record.Created) {
            if (Test-Path -LiteralPath $record.OriginalPath) { Remove-Item -LiteralPath $record.OriginalPath -Force }
        } elseif ($record.BackupPath -and (Test-Path -LiteralPath $record.BackupPath)) {
            Copy-Item -LiteralPath $record.BackupPath -Destination $record.OriginalPath -Force
        } else {
            throw "旧版本快捷方式备份缺失，已停止升级: $($record.OriginalPath)"
        }
    }
    Remove-Item -LiteralPath $manifestPath -Force
    $legacyBackupRoot = Join-Path $installRoot "shortcut-backups"
    if (Test-Path -LiteralPath $legacyBackupRoot) { Remove-Item -LiteralPath $legacyBackupRoot -Recurse -Force }
}

$proxyExe = Join-Path $installRoot "CodexAutoProxy.exe"

$runPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
if ($StartWithWindows) {
    New-Item -Path $runPath -Force | Out-Null
    Set-ItemProperty -Path $runPath -Name "CodexAutoProxy" -Value ('"' + $proxyExe + '"')
} else {
    Remove-ItemProperty -Path $runPath -Name "CodexAutoProxy" -ErrorAction SilentlyContinue
}

$programGroup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Codex Auto Proxy"
New-Item -ItemType Directory -Path $programGroup -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$startLink = $shell.CreateShortcut((Join-Path $programGroup "Start Codex Auto Proxy.lnk"))
$startLink.TargetPath = $proxyExe
$startLink.WorkingDirectory = $installRoot
$startLink.IconLocation = "$proxyExe,0"
$startLink.Save()
$uninstallLink = $shell.CreateShortcut((Join-Path $programGroup "Uninstall Codex Auto Proxy.lnk"))
$uninstallLink.TargetPath = (Join-Path $installRoot "uninstall.cmd")
$uninstallLink.WorkingDirectory = $installRoot
$uninstallLink.IconLocation = "$proxyExe,0"
$uninstallLink.Save()
$statusLink = $shell.CreateShortcut((Join-Path $programGroup "Codex Auto Proxy Status.lnk"))
$statusLink.TargetPath = (Join-Path $installRoot "status.cmd")
$statusLink.WorkingDirectory = $installRoot
$statusLink.IconLocation = "$proxyExe,0"
$statusLink.Save()

$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexAutoProxy"
New-Item -Path $uninstallKey -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "DisplayName" -Value "Codex Auto Proxy" -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "DisplayVersion" -Value "2.2.0" -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "Publisher" -Value "Local installation" -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "InstallLocation" -Value $installRoot -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "DisplayIcon" -Value $proxyExe -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "UninstallString" -Value ('"' + (Join-Path $installRoot "uninstall.cmd") + '"') -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "NoModify" -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "NoRepair" -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "EstimatedSize" -PropertyType DWord -Value 256 -Force | Out-Null

Start-Process -FilePath $proxyExe -WindowStyle Hidden
Write-Host "安装完成。"
Write-Host "Codex: $CodexExe"
Write-Host "本地桥接: 127.0.0.1:$ListenPort"
Write-Host "Clash: 127.0.0.1:$ClashPort"
Write-Host '自动启动行为按两项启动设置执行。当前已打开的 Codex 需要完全退出后，从托盘“启动 Codex”重开一次。'
Write-Host "代理仅传给从托盘启动的 Codex，不再接管用户级代理变量。原图标启动仍可使用 Clash 系统代理。"
Write-Host "请在 Windows 设置 → 应用 → 启动中关闭 Codex/ChatGPT 自己的启动项，保留 Codex Auto Proxy；同时关闭 Codex 应用内的登录时启动选项（若有）。"
