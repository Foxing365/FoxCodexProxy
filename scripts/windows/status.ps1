[CmdletBinding()]
param()

$installRoot = Join-Path $env:LOCALAPPDATA "CodexAutoProxy"
$exe = Join-Path $installRoot "CodexAutoProxy.exe"
$config = Join-Path $installRoot "config.ini"
$runPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

Write-Host "安装目录: $installRoot"
Write-Host "程序文件: $(if (Test-Path $exe) { '存在' } else { '缺失' })"
Write-Host "配置文件: $(if (Test-Path $config) { '存在' } else { '缺失' })"

$process = Get-Process -Name "CodexAutoProxy" -ErrorAction SilentlyContinue
Write-Host "托盘进程: $(if ($process) { '运行中 (PID ' + (($process.Id -join ',') ) + ')' } else { '未运行' })"

$listenPort = 7898
if (Test-Path -LiteralPath $config) {
    $portLine = Get-Content -LiteralPath $config | Where-Object { $_ -match '^ListenPort=\d+$' } | Select-Object -First 1
    if ($portLine) { $listenPort = [int]($portLine.Split('=')[1]) }
}
$expectedProxy = "http://127.0.0.1:$listenPort"
$userProxy = [Environment]::GetEnvironmentVariable("HTTPS_PROXY", [EnvironmentVariableTarget]::User)
$managedEnv = $userProxy -eq $expectedProxy
Write-Host "代理方式: 仅注入托盘启动的 Codex 进程"
Write-Host "旧版用户代理残留: $(if ($managedEnv) { '存在，请重启代理完成迁移' } else { '无' })"
if (-not $process -and $managedEnv) {
    Write-Warning "托盘未运行但用户代理环境仍指向本地桥接。运行 CodexAutoProxy.exe --exit 或卸载器可恢复。"
}

$startup = $false
try { $startup = $null -ne (Get-ItemPropertyValue -Path $runPath -Name "CodexAutoProxy" -ErrorAction Stop) } catch {}
Write-Host "随 Windows 启动: $(if ($startup) { '是' } else { '否' })"

if (Test-Path $config) {
    $items = @{}
    Get-Content -LiteralPath $config | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') { $items[$matches[1].Trim()] = $matches[2].Trim() }
    }
    Write-Host "Codex: $($items.CodexExe)"
    Write-Host "本地桥接端口: $($items.ListenPort)"
    Write-Host "Clash mixed-port: $($items.ClashPort)"
    Write-Host "代理启动时启动 Codex: $(if ($items.LaunchCodexOnStart -ne 'false') { '是' } else { '否' })"
    foreach ($probe in @(
        @{ Name = "本地桥接"; Host = "127.0.0.1"; Port = [int]$items.ListenPort },
        @{ Name = "Clash"; Host = "127.0.0.1"; Port = [int]$items.ClashPort }
    )) {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $result = $client.BeginConnect($probe.Host, $probe.Port, $null, $null)
            $open = $result.AsyncWaitHandle.WaitOne(800) -and $client.Connected
            Write-Host "$($probe.Name): $(if ($open) { '可连接' } else { '不可连接' })"
        } catch { Write-Host "$($probe.Name): 不可连接" } finally { $client.Close() }
    }
}
