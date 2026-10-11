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
Write-Host '启动入口: 请用代理托盘启动 Codex；原图标启动不保证经过桥接。'
Write-Host 'Codex 设置策略: CLI 支持时关闭实验性 respect_system_proxy，原值由安装器保存供卸载恢复。'
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
    Write-Host "Auto 优先 Clash: $(if ($items.PreferClash -eq 'true') { '是' } else { '否' })"
    $managedConfigured = -not [string]::IsNullOrWhiteSpace($items.UpstreamExe) -and -not [string]::IsNullOrWhiteSpace($items.UpstreamConfig)
    Write-Host "Codex 专用出口: $(if ($managedConfigured) { '已配置（不改变主 Clash）' } else { '未配置，使用普通 Clash 出口' })"
    if ($managedConfigured) {
        Write-Host "专用内核文件: $(if (Test-Path -LiteralPath $items.UpstreamExe) { '存在' } else { '缺失，请重新配置' })"
        Write-Host "本机私有节点配置: $(if (Test-Path -LiteralPath $items.UpstreamConfig) { '存在（内容不显示）' } else { '缺失，请重新配置' })"
        $verifiedManaged = $false
        $pidFile = Join-Path $installRoot 'managed-upstream.pid'
        if (Test-Path -LiteralPath $pidFile) {
            try {
                $pidRecord = [IO.File]::ReadAllLines($pidFile)
                if ($pidRecord.Length -ge 3 -and $pidRecord[2] -eq $items.UpstreamConfig) {
                    $upstreamId = 0
                    $upstreamTicks = [long]0
                    if ([int]::TryParse($pidRecord[0], [ref]$upstreamId) -and [long]::TryParse($pidRecord[1], [ref]$upstreamTicks)) {
                        $managedProcess = Get-Process -Id $upstreamId -ErrorAction Stop
                        $managedDetails = Get-CimInstance Win32_Process -Filter "ProcessId=$upstreamId" -ErrorAction Stop
                        $verifiedManaged = $managedProcess.StartTime.ToUniversalTime().Ticks -eq $upstreamTicks -and
                            $managedDetails.ExecutablePath -eq $items.UpstreamExe -and
                            $managedDetails.CommandLine.IndexOf($items.UpstreamConfig, [StringComparison]::OrdinalIgnoreCase) -ge 0
                    }
                }
            } catch { $verifiedManaged = $false }
        }
        Write-Host "专用出口托管进程: $(if ($verifiedManaged) { '运行中（PID ' + $upstreamId + '，身份已核对）' } else { '未确认运行，请检查托盘诊断日志' })"
    }
    Write-Host "代理启动时启动 Codex: $(if ($items.LaunchCodexOnStart -ne 'false') { '是' } else { '否' })"
    foreach ($probe in @(
        @{ Name = "本地桥接"; Host = "127.0.0.1"; Port = [int]$items.ListenPort },
        @{ Name = "Clash"; Host = "127.0.0.1"; Port = [int]$items.ClashPort }
    )) {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $result = $client.BeginConnect($probe.Host, $probe.Port, $null, $null)
            $open = $result.AsyncWaitHandle.WaitOne(800) -and $client.Connected
            Write-Host "$($probe.Name): $(if ($open) { 'TCP 可连接（不等于 TLS/模型可用）' } else { '不可连接' })"
        } catch { Write-Host "$($probe.Name): 不可连接" } finally { $client.Close() }
    }
}

$statusPath = Join-Path $installRoot 'status.json'
if (Test-Path -LiteralPath $statusPath) {
    try {
        $snapshot = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        # PowerShell 7 can deserialize ISO timestamps as DateTime; preserve its UTC kind.
        $updated = if ($snapshot.updatedUtc -is [datetime]) { $snapshot.updatedUtc.ToUniversalTime() } else {
            [datetime]::Parse([string]$snapshot.updatedUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        }
        $ageSeconds = ([datetime]::UtcNow - $updated).TotalSeconds
        $fresh = $ageSeconds -ge -5 -and $ageSeconds -lt 90
        $probeTime = if ($snapshot.lastProbeUtc -is [datetime]) { $snapshot.lastProbeUtc.ToUniversalTime().ToString('o') } else { $snapshot.lastProbeUtc }
        Write-Host "路由快照: $($snapshot.mode) / $($snapshot.route)（$(if ($fresh) { '近期状态' } else { '过期，不能作为当前证据' })）"
        Write-Host "探测时间（UTC）: $probeTime"
        Write-Host '探测和端口状态不代表账户认证成功；上游 TLS 或服务端错误仍可能导致重试。'
    } catch { Write-Warning '无法读取路由状态快照。' }
}
