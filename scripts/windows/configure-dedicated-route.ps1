[CmdletBinding()]
param(
    [string]$NodeName,
    [string]$ClashConfig = (Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml'),
    [string]$CorePath = (Join-Path $env:ProgramFiles 'Clash Verge\verge-mihomo.exe'),
    [string]$InterfaceAlias,
    [int]$Port = 17897,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'CodexAutoProxy'),
    [switch]$Disable,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$configPath = Join-Path $InstallRoot 'config.ini'
$backup = Join-Path $InstallRoot 'dedicated-route-backup.ini'
$proxyExe = Join-Path $InstallRoot 'CodexAutoProxy.exe'
if (-not (Test-Path -LiteralPath $configPath)) { throw '请先安装 FoxCodexProxy。' }
$original = [IO.File]::ReadAllText($configPath)
$pendingConfig = $null
function Set-IniValue([string]$Text,[string]$Key,[string]$Value) {
    $pattern = '(?m)^' + [regex]::Escape($Key) + '=[^\r\n]*'
    if ($Text -match $pattern) { return [regex]::Replace($Text,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $Key+'='+$Value}) }
    return $Text.TrimEnd() + "`r`n" + $Key+'='+$Value+"`r`n"
}
if ($Disable) {
    if (-not (Test-Path -LiteralPath $backup)) { throw '没有专用出口备份，未更改当前配置。' }
    $saved = [IO.File]::ReadAllText($backup)
    $updated = $original
    foreach ($key in 'ClashHost','ClashPort','PreferClash','UpstreamExe','UpstreamConfig') {
        $match = [regex]::Match($saved,'(?m)^'+$key+'=([^\r\n]*)')
        $value = if ($match.Success) { $match.Groups[1].Value } elseif ($key -eq 'PreferClash') { 'false' } else { '' }
        $updated = Set-IniValue $updated $key $value
    }
} else {
    if (-not $NodeName) { throw '请用 -NodeName 指定本机已实测稳定的 Clash 节点，不要直接复制他人的节点名称。' }
    if ($Port -lt 1 -or $Port -gt 65535) { throw '专用端口必须在 1 到 65535 之间。' }
    $bridge = [regex]::Match($original,'(?m)^ListenPort=(\d+)')
    if ($bridge.Success -and [int]$bridge.Groups[1].Value -eq $Port) { throw '专用端口不能与桥接端口相同。' }
    if (-not (Test-Path -LiteralPath $CorePath)) { throw '找不到本机 Clash 内核，请用 -CorePath 指定。' }
    $lines = [IO.File]::ReadAllLines($ClashConfig)
    $inside = $false; $start = -1; $finish = -1; $listIndent = -1
    for ($i=0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^proxies:\s*$') { $inside=$true; continue }
        if (-not $inside) { continue }
        if ($lines[$i] -match '^(\s*)-\s+name:\s*(.+)$') {
            $indent=$matches[1].Length
            if ($listIndent -lt 0) { $listIndent=$indent }
            if ($indent -ne $listIndent) { continue }
            if ($start -ge 0) { $finish=$i; break }
            $name=$matches[2].Trim()
            if ($name.StartsWith('"')) { $name=$name | ConvertFrom-Json }
            elseif ($name.StartsWith("'")) { $name=$name.Trim("'").Replace("''", "'") }
            if ($name -eq $NodeName) { $start=$i }
        } elseif ($lines[$i] -match '^[a-zA-Z][a-zA-Z0-9_-]*:') {
            if ($start -ge 0) { $finish=$i }; break
        }
    }
    if ($start -ge 0 -and $finish -lt 0) { $finish=$lines.Length }
    if ($start -lt 0 -or $finish -le $start) { throw '找不到该节点的独立配置块；动态 provider 或其他 YAML 格式需由 agent 检查后配置。' }
    $block=$lines[$start..($finish-1)] -join "`n"
    if ($block -match '(?m)^\s*dialer-proxy:') { throw '该节点依赖其他出口，不能直接导出为独立节点。' }
    if (-not $InterfaceAlias) {
        $nic=Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } | Select-Object -First 1
        if (-not $nic) { throw '未找到活动物理网卡，请用 -InterfaceAlias 指定。' }
        $InterfaceAlias=$nic.Name
    }
    $privateRoot=Join-Path $InstallRoot 'dedicated-route'
    New-Item -ItemType Directory -Path $privateRoot -Force | Out-Null
    $privateConfig=Join-Path $privateRoot 'config.yaml'
    $pendingConfig=Join-Path $privateRoot ('candidate-'+[guid]::NewGuid().ToString('N')+'.yaml')
    $interfaceJson=$InterfaceAlias | ConvertTo-Json -Compress
    $ruleJson=('MATCH,'+$NodeName) | ConvertTo-Json -Compress
    $prefix=@"
mixed-port: $Port
bind-address: 127.0.0.1
allow-lan: false
mode: rule
log-level: warning
ipv6: false
interface-name: $interfaceJson
external-controller: ''
external-controller-pipe: ''
tun:
  enable: false
dns:
  enable: true
  ipv6: false
  enhanced-mode: redir-host
  nameserver:
  - 223.5.5.5
  - 119.29.29.29
proxies:
"@
    # Mechanically extract a private node from the local Clash configuration.
    # Credentials remain under LOCALAPPDATA, never in the public repository or logs.
    [IO.File]::WriteAllText($pendingConfig,($prefix+"`n"+$block+"`nrules:`n- "+$ruleJson+"`n"),(New-Object Text.UTF8Encoding($false)))
    $check=& $CorePath -t -d $privateRoot -f $pendingConfig 2>&1
    if ($LASTEXITCODE -ne 0) { throw '专用节点配置未通过内核检查；当前桥接配置未改变。' }
    $updated=Set-IniValue $original 'ClashHost' '127.0.0.1'
    $updated=Set-IniValue $updated 'ClashPort' ([string]$Port)
    $updated=Set-IniValue $updated 'PreferClash' 'true'
    $updated=Set-IniValue $updated 'UpstreamExe' ([IO.Path]::GetFullPath($CorePath))
    $updated=Set-IniValue $updated 'UpstreamConfig' $privateConfig
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $configPath -Destination $backup }
}
if (-not $NoRestart) {
    & $proxyExe --exit
    $deadline=(Get-Date).AddSeconds(15)
    do { Start-Sleep -Milliseconds 200; $running=@(Get-CimInstance Win32_Process -Filter "Name='CodexAutoProxy.exe'" | Where-Object ExecutablePath -eq $proxyExe) } while ($running.Count -and (Get-Date) -lt $deadline)
    if ($running.Count) { throw '代理未正常退出，尚未改写 config.ini。' }
}
if ($pendingConfig) {
    if (Test-Path -LiteralPath $privateConfig) {
        [IO.File]::Replace($pendingConfig,$privateConfig,(Join-Path $privateRoot ('config-before-'+[guid]::NewGuid().ToString('N')+'.yaml')))
    } else { Move-Item -LiteralPath $pendingConfig -Destination $privateConfig }
}
[IO.File]::WriteAllText($configPath,$updated,(New-Object Text.UTF8Encoding($false)))
if (-not $NoRestart) { Start-Process -FilePath $proxyExe -ArgumentList '--no-launch' -WindowStyle Hidden }
Write-Output $(if ($Disable) { '已恢复普通 Clash 出口；当前 Codex 会话未关闭。' } else { '已配置 Codex 专用出口；主 Clash 的节点、TUN 和系统代理未更改。' })
