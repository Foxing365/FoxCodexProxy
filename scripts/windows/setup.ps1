[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$installedValues = @{}
$installedConfig = Join-Path $env:LOCALAPPDATA 'CodexAutoProxy\config.ini'
if (Test-Path -LiteralPath $installedConfig) {
    foreach ($line in [IO.File]::ReadAllLines($installedConfig)) {
        if ($line -match '^([^=#]+)=(.*)$') { $installedValues[$matches[1]] = $matches[2] }
    }
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = "安装 Codex 自动代理"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object Drawing.Size(540, 305)

$codexLabel = New-Object Windows.Forms.Label
$codexLabel.Text = "Codex 程序（可留空自动识别）："
$codexLabel.AutoSize = $true
$codexLabel.Location = New-Object Drawing.Point(20, 25)
$form.Controls.Add($codexLabel)

$codexBox = New-Object Windows.Forms.TextBox
$codexBox.Location = New-Object Drawing.Point(20, 48)
$codexBox.Size = New-Object Drawing.Size(405, 24)
$form.Controls.Add($codexBox)

$browse = New-Object Windows.Forms.Button
$browse.Text = "浏览…"
$browse.Location = New-Object Drawing.Point(435, 46)
$browse.Size = New-Object Drawing.Size(82, 27)
$browse.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = "Windows 程序 (*.exe)|*.exe"
    $dialog.Title = "选择 Codex.exe"
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $codexBox.Text = $dialog.FileName }
})
$form.Controls.Add($browse)

$portLabel = New-Object Windows.Forms.Label
$portLabel.Text = "Clash Verge mixed port："
$portLabel.AutoSize = $true
$portLabel.Location = New-Object Drawing.Point(20, 95)
$form.Controls.Add($portLabel)

$port = New-Object Windows.Forms.NumericUpDown
$port.Minimum = 1
$port.Maximum = 65535
$port.Value = 7897
$clashConfigs = @(
    (Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml'),
    (Join-Path $env:APPDATA 'clash-verge-rev\clash-verge.yaml'),
    (Join-Path $env:LOCALAPPDATA 'io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml')
)
foreach ($config in $clashConfigs) {
    if (-not (Test-Path -LiteralPath $config)) { continue }
    $match = [regex]::Match([IO.File]::ReadAllText($config), '(?m)^\s*mixed-port\s*:\s*(\d+)')
    if ($match.Success) {
        $detectedPort = [int]$match.Groups[1].Value
        if ($detectedPort -ge 1 -and $detectedPort -le 65535) { $port.Value = $detectedPort; break }
    }
}
if ($installedValues.ClashPort) {
    $savedPort = 0
    if ([int]::TryParse($installedValues.ClashPort, [ref]$savedPort) -and $savedPort -ge 1 -and $savedPort -le 65535) {
        $port.Value = $savedPort
    }
}
if ($installedValues.UpstreamExe -and $installedValues.UpstreamConfig) {
    $portLabel.Text = 'Codex 专用出口端口：'
}
$port.Location = New-Object Drawing.Point(205, 91)
$port.Size = New-Object Drawing.Size(100, 24)
$form.Controls.Add($port)

$startup = New-Object Windows.Forms.CheckBox
$startup.Text = "随 Windows 登录启动代理（推荐）"
$startup.AutoSize = $true
$startup.Checked = $true
if (Test-Path -LiteralPath $installedConfig) {
    $startup.Checked = [bool](Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name CodexAutoProxy -ErrorAction SilentlyContinue).CodexAutoProxy
}
$startup.Location = New-Object Drawing.Point(20, 135)
$form.Controls.Add($startup)
$launchCodex = New-Object Windows.Forms.CheckBox
$launchCodex.Text = "代理启动时同时启动 Codex（推荐）"
$launchCodex.AutoSize = $true
$launchCodex.Checked = $true
if ($installedValues.ContainsKey('LaunchCodexOnStart')) {
    $launchCodex.Checked = $installedValues.LaunchCodexOnStart -eq 'true'
}
$launchCodex.Location = New-Object Drawing.Point(20, 165)
$form.Controls.Add($launchCodex)

$location = New-Object Windows.Forms.Label
$location.Text = "安装位置：" + (Join-Path $env:LOCALAPPDATA "CodexAutoProxy")
$location.AutoSize = $true
$location.ForeColor = [Drawing.SystemColors]::GrayText
$location.Location = New-Object Drawing.Point(20, 202)
$form.Controls.Add($location)

$install = New-Object Windows.Forms.Button
$install.Text = "安装"
$install.Location = New-Object Drawing.Point(345, 253)
$install.Size = New-Object Drawing.Size(82, 30)
$form.AcceptButton = $install
$form.Controls.Add($install)

$cancel = New-Object Windows.Forms.Button
$cancel.Text = "取消"
$cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
$cancel.Location = New-Object Drawing.Point(435, 253)
$cancel.Size = New-Object Drawing.Size(82, 30)
$form.CancelButton = $cancel
$form.Controls.Add($cancel)

$install.Add_Click({
    try {
        $install.Enabled = $false
        $install.Text = "安装中…"
        $arguments = @{ ClashPort = [int]$port.Value; LaunchCodexOnStart = [bool]$launchCodex.Checked; StartWithWindows = [bool]$startup.Checked }
        if ($codexBox.Text.Trim()) { $arguments.CodexExe = $codexBox.Text.Trim() }
        & (Join-Path $PSScriptRoot "install.ps1") @arguments
        [Windows.Forms.MessageBox]::Show('安装完成。请完全退出已打开的 Codex，再从代理托盘的“启动 Codex”打开。请在 Windows 设置 → 应用 → 启动中关闭 Codex/ChatGPT 自己的自启，并关闭应用内的登录启动选项（若有）；保留 Clash 与代理自启。自动启动行为按你勾选的两项设置执行。', "Codex 自动代理", "OK", "Information") | Out-Null
        $form.DialogResult = [Windows.Forms.DialogResult]::OK
        $form.Close()
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, "安装失败", "OK", "Error") | Out-Null
        $install.Enabled = $true
        $install.Text = "安装"
    }
})

[void]$form.ShowDialog()
