# Shared by install/uninstall; resolve the same user configuration as Codex.
function Enable-CodexSystemProxy([string]$InstallRoot, [string]$Executable) {
    $cli = Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cli) {
        $bundled = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\*\codex.exe') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($bundled) { $cli = [pscustomobject]@{ Source = $bundled.FullName } }
    }
    if (-not $cli) {
        Write-Warning '未找到 Codex CLI，跳过系统代理开关。请通过托盘的“启动 Codex”打开应用。'
        return
    }
    $features = & $cli.Source features list 2>$null
    if ($LASTEXITCODE -ne 0 -or -not ($features -match '^respect_system_proxy\s+')) { return }
    $configRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $configPath = Join-Path $configRoot 'config.toml'
    $statePath = Join-Path $InstallRoot 'codex-config-state.json'
    $existingState = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
    $content = if (Test-Path -LiteralPath $configPath) { [IO.File]::ReadAllText($configPath) } else { '' }
    $section = [regex]::Match($content, '(?ms)^\[features\][^\r\n]*\r?\n(?<body>.*?)(?=^\[|\z)')
    $old = if ($section.Success) { [regex]::Match($section.Groups['body'].Value, '(?m)^\s*respect_system_proxy\s*=\s*(true|false)[^\r\n]*') } else { $null }
    if ($old -and $old.Success -and $old.Groups[1].Value -eq 'false' -and -not $existingState) { return }
    $state = @{ ConfigPath = $configPath; ManagedValue = 'false'; PreviousLine = if ($existingState -and $existingState.ConfigPath -eq $configPath) { $existingState.PreviousLine } elseif ($old -and $old.Success) { $old.Value } else { $null } }
    # Explicit process proxies must not be overridden by the experimental OS proxy resolver.
    # Preserve the pre-install value across upgrades, including older managed=true releases.
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    & $cli.Source features disable respect_system_proxy
    if ($LASTEXITCODE -ne 0) { throw 'Codex 系统代理开关配置失败。' }
    Write-Host "已关闭实验性系统代理优先，使用托盘进程代理: $configPath"
}

function Restore-CodexSystemProxy([string]$InstallRoot) {
    $statePath = Join-Path $InstallRoot 'codex-config-state.json'
    if (-not (Test-Path -LiteralPath $statePath)) { return }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (Test-Path -LiteralPath $state.ConfigPath) {
        $content = [IO.File]::ReadAllText($state.ConfigPath)
        $section = [regex]::Match($content, '(?ms)^\[features\][^\r\n]*\r?\n(?<body>.*?)(?=^\[|\z)')
        if ($section.Success) {
            $managedValue = if ($state.ManagedValue) { [string]$state.ManagedValue } else { 'true' }
            $line = [regex]::Match($section.Groups['body'].Value, '(?m)^\s*respect_system_proxy\s*=\s*'+$managedValue+'[^\r\n]*(?:\r?\n|\z)')
            if ($line.Success) {
                $offset = $section.Groups['body'].Index + $line.Index
                $replacement = if ($null -ne $state.PreviousLine) { [string]$state.PreviousLine + "`r`n" } else { '' }
                $content = $content.Remove($offset, $line.Length).Insert($offset, $replacement)
                [IO.File]::WriteAllText($state.ConfigPath, $content, (New-Object Text.UTF8Encoding($false)))
            }
        }
    }
}
