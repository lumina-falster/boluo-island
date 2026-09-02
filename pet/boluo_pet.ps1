param([switch]$SelfTest)
# 菠萝岛桌宠（Windows，PowerShell + WPF，零依赖）
# 操作：拖动=移动位置 | 单击=展开/收起详情 | 右键=菜单（刷新/网页/设置/退出）
# 数据：只读同步自 GitHub 仓库 data.json；修改请在手机网页上操作
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationFramework

$Base      = Split-Path -Parent $MyInvocation.MyCommand.Path
$CfgFile   = Join-Path $Base 'pet_config.json'
$StateFile = Join-Path $Base 'pet_state.json'

$cfg = @{ owner = 'lumina-falster'; repo = 'boluo-island'; remindMinutes = 10; pollSeconds = 180 }
if (Test-Path $CfgFile) {
    try {
        $o = Get-Content $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $o.PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value }
    } catch {}
}
$script:seen = @{}
if (Test-Path $StateFile) {
    try {
        (Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $script:seen[$_.Name] = $_.Value }
    } catch {}
}

function Save-Cfg { $cfg | ConvertTo-Json | Out-File -FilePath $CfgFile -Encoding utf8 }
function NowMs { [double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function Format-Left([double]$ms) {
    if ($ms -le 0) { return '已成熟' }
    $s = [int][math]::Floor($ms / 1000)
    $d = [int][math]::Floor($s / 86400); $s = $s % 86400
    $h = [int][math]::Floor($s / 3600);  $s = $s % 3600
    $m = [int][math]::Floor($s / 60)
    if ($d -gt 0) { '{0}天{1:00}:{2:00}:{3:00}' -f $d, $h, $m, ($s % 60) }
    else { '{0:00}:{1:00}:{2:00}' -f $h, $m, ($s % 60) }
}

function Show-Toast([string]$title, [string]$msg) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml(('<toast><visual><binding template="ToastGeneric"><text>{0}</text><text>{1}</text></binding></visual></toast>' -f $title, $msg))
        $t = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('菠萝岛桌宠').Show($t)
    } catch {
        try { [console]::beep(800, 300) } catch {}
    }
}

function Get-IslandData {
    $url = 'https://api.github.com/repos/{0}/{1}/contents/data.json' -f $cfg['owner'], $cfg['repo']
    $hdr = @{ Accept = 'application/vnd.github.raw+json'; 'User-Agent' = 'boluo-pet' }
    $raw = Invoke-RestMethod -Uri $url -Headers $hdr -TimeoutSec 15
    if ($raw -is [string]) { $raw | ConvertFrom-Json } else { $raw }
}

# ---------------- 主窗口 ----------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="180" Height="208" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        WindowStartupLocation="Manual" Title="菠萝岛桌宠">
  <Window.ContextMenu>
    <ContextMenu>
      <MenuItem Header="立即刷新" Name="MRefresh"/>
      <MenuItem Header="打开管理网页" Name="MWeb"/>
      <MenuItem Header="设置仓库…" Name="MSetup"/>
      <Separator/>
      <MenuItem Header="退出" Name="MExit"/>
    </ContextMenu>
  </Window.ContextMenu>
  <Canvas Background="Transparent">
    <Border Canvas.Left="8" Canvas.Top="4" Width="164" CornerRadius="10" Background="#FFFFFF"
            BorderBrush="#E3D9BD" BorderThickness="1" Padding="6,5">
      <StackPanel>
        <TextBlock Name="T1" FontFamily="Microsoft YaHei UI" FontSize="11" FontWeight="Bold"
                   Foreground="#4A4436" HorizontalAlignment="Center" Text="连接中…"/>
        <TextBlock Name="T2" FontFamily="Microsoft YaHei UI" FontSize="10"
                   Foreground="#6B6455" HorizontalAlignment="Center" Text=""/>
      </StackPanel>
    </Border>
    <Path Fill="#FFFFFF" Data="M 90,66 L 82,52 L 98,52 Z"/>
    <Canvas Name="Pet">
      <Polygon Points="90,58 80,118 100,118" Fill="#37A05E" Stroke="#2E8B4F"/>
      <Polygon Points="62,72 74,122 84,112" Fill="#2E9E5B" Stroke="#2E8B4F"/>
      <Polygon Points="118,72 106,122 96,112" Fill="#2E9E5B" Stroke="#2E8B4F"/>
      <Ellipse Canvas.Left="52" Canvas.Top="116" Width="76" Height="78" Fill="#F6A938" Stroke="#D98C0A" StrokeThickness="2"/>
      <Ellipse Canvas.Left="59" Canvas.Top="124" Width="5" Height="5" Fill="#E08C12"/>
      <Ellipse Canvas.Left="116" Canvas.Top="124" Width="5" Height="5" Fill="#E08C12"/>
      <Ellipse Canvas.Left="54" Canvas.Top="152" Width="5" Height="5" Fill="#E08C12"/>
      <Ellipse Canvas.Left="121" Canvas.Top="152" Width="5" Height="5" Fill="#E08C12"/>
      <Ellipse Canvas.Left="61" Canvas.Top="178" Width="5" Height="5" Fill="#E08C12"/>
      <Ellipse Canvas.Left="114" Canvas.Top="178" Width="5" Height="5" Fill="#E08C12"/>
      <Ellipse Canvas.Left="85" Canvas.Top="185" Width="5" Height="5" Fill="#E08C12"/>
      <Canvas Name="FaceSleep">
        <Line X1="75" Y1="146" X2="85" Y2="146" Stroke="#7A5B16" StrokeThickness="2"/>
        <Line X1="95" Y1="146" X2="105" Y2="146" Stroke="#7A5B16" StrokeThickness="2"/>
        <Ellipse Canvas.Left="86" Canvas.Top="153" Width="8" Height="8" Stroke="#7A5B16" StrokeThickness="2"/>
        <TextBlock Canvas.Left="132" Canvas.Top="94" Text="z Z" Foreground="#9AA0A6"
                   FontFamily="Microsoft YaHei UI" FontSize="10" FontWeight="Bold"/>
      </Canvas>
      <Canvas Name="FaceGrow" Visibility="Collapsed">
        <Ellipse Canvas.Left="78" Canvas.Top="143" Width="5" Height="5" Fill="#5B4A12"/>
        <Ellipse Canvas.Left="97" Canvas.Top="143" Width="5" Height="5" Fill="#5B4A12"/>
        <Path Stroke="#7A5B16" StrokeThickness="2" Data="M 81,156 Q 90,163 99,156"/>
      </Canvas>
      <Canvas Name="FaceHot" Visibility="Collapsed">
        <Path Stroke="#7A5B16" StrokeThickness="2" Data="M 76,148 Q 80,142 84,148"/>
        <Path Stroke="#7A5B16" StrokeThickness="2" Data="M 96,148 Q 100,142 104,148"/>
        <Path Stroke="#7A5B16" StrokeThickness="2.5" Data="M 79,155 Q 90,167 101,155"/>
        <Ellipse Canvas.Left="60" Canvas.Top="152" Width="9" Height="6" Fill="#FFB3A0"/>
        <Ellipse Canvas.Left="111" Canvas.Top="152" Width="9" Height="6" Fill="#FFB3A0"/>
      </Canvas>
    </Canvas>
  </Canvas>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Parse($xaml)
$T1 = $window.FindName('T1'); $T2 = $window.FindName('T2')
$FaceSleep = $window.FindName('FaceSleep'); $FaceGrow = $window.FindName('FaceGrow'); $FaceHot = $window.FindName('FaceHot')
$Pet = $window.FindName('Pet')
$PetT = New-Object System.Windows.Media.TranslateTransform
$Pet.RenderTransform = $PetT

# ---------------- 详情窗口 ----------------
$xamlD = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="252" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        WindowStartupLocation="Manual" Title="菠萝岛详情">
  <Border CornerRadius="12" Background="#FFFDF6" BorderBrush="#E3D9BD" BorderThickness="1" Padding="12,10">
    <StackPanel>
      <TextBlock Text="菠萝岛详情" FontFamily="Microsoft YaHei UI" FontSize="12" FontWeight="Bold"
                 Foreground="#8A6D1F" HorizontalAlignment="Center" Margin="0,0,0,6"/>
      <TextBlock Name="DText" FontFamily="Microsoft YaHei UI" FontSize="11" Foreground="#4A4436" LineHeight="19" Text=""/>
      <Button Name="DClose" Content="收起" Margin="0,8,0,0" Padding="14,3" FontFamily="Microsoft YaHei UI"
              FontSize="11" HorizontalAlignment="Center"/>
    </StackPanel>
  </Border>
</Window>
'@
$DWindow = [Windows.Markup.XamlReader]::Parse($xamlD)
$DText = $DWindow.FindName('DText')
$DWindow.FindName('DClose').Add_Click({ $DWindow.Hide() })

# ---------------- 状态 ----------------
$script:plots = @()
$script:total = 64
$script:offline = $false
$script:booted = $false
$script:mood = 'sleep'

# ---------------- 逻辑 ----------------
function Update-Data {
    try {
        $d = Get-IslandData
        $script:plots = @($d.plots | Where-Object { $_.ripenAt })
        $script:total = @($d.plots).Count
        $script:offline = $false
        $now = NowMs
        $rm = [double]$cfg['remindMinutes'] * 60000
        $changed = $false
        foreach ($p in $script:plots) {
            $left = [double]$p.ripenAt - $now
            $st = ''
            if ($left -le 0) { $st = 'ripe' } elseif ($left -le $rm) { $st = 'soon' }
            if ($st -and $script:booted -and $script:seen[$p.id] -ne $st) {
                if ($st -eq 'ripe') {
                    Show-Toast '菠萝岛成熟提醒' ('{0} {1} 已成熟，快去收获！' -f $p.name, $p.fruit)
                } else {
                    Show-Toast '菠萝岛快熟提醒' ('{0} {1} 约 {2} 分钟后成熟' -f $p.name, $p.fruit, [int][math]::Ceiling($left / 60000))
                }
            }
            if ($script:seen[$p.id] -ne $st) { $script:seen[$p.id] = $st; $changed = $true }
        }
        if ($changed -and $script:seen.Count -gt 0) {
            $script:seen | ConvertTo-Json | Out-File -FilePath $StateFile -Encoding utf8
        }
        $script:booted = $true
    } catch {
        $script:offline = $true
    }
}

function Update-Tick {
    $now = NowMs
    $rm = [double]$cfg['remindMinutes'] * 60000
    $ripe = 0; $soon = 0; $grow = 0; $nxt = $null
    foreach ($p in $script:plots) {
        $left = [double]$p.ripenAt - $now
        if ($left -le 0) { $ripe++ } elseif ($left -le $rm) { $soon++ } else { $grow++ }
        if (-not $nxt -or [double]$p.ripenAt -lt [double]$nxt.ripenAt) { $nxt = $p }
    }
    $mood = if ($ripe) { 'ripe' } elseif ($soon) { 'soon' } elseif ($grow) { 'grow' } else { 'sleep' }
    if ($mood -ne $script:mood) {
        $script:mood = $mood
        $FaceSleep.Visibility = if ($mood -eq 'sleep') { 'Visible' } else { 'Collapsed' }
        $FaceGrow.Visibility  = if ($mood -eq 'grow')  { 'Visible' } else { 'Collapsed' }
        $FaceHot.Visibility   = if ($mood -in 'soon', 'ripe') { 'Visible' } else { 'Collapsed' }
    }
    if ($mood -eq 'ripe') { $T1.Foreground = '#D33' }
    elseif ($mood -eq 'soon') { $T1.Foreground = '#C07800' }
    elseif ($mood -eq 'grow') { $T1.Foreground = '#2E7D4F' }
    else { $T1.Foreground = '#8A8577' }
    $off = if ($script:offline) { '离线 | ' } else { '' }
    if ($mood -eq 'ripe') { $T1.Text = '{0}熟了 {1} 块，快收！' -f $off, $ripe }
    elseif ($mood -eq 'soon') { $T1.Text = '{0}快熟 {1} · 生长 {2}' -f $off, $soon, $grow }
    elseif ($mood -eq 'grow') { $T1.Text = '{0}生长中 {1} 块' -f $off, $grow }
    else { $T1.Text = '岛上空空的…' }
    if ($mood -eq 'sleep') { $T2.Text = '右键打开网页去种植' }
    elseif ($nxt) { $T2.Text = '{0}·{1} 剩 {2}' -f $nxt.name, $nxt.fruit, (Format-Left ([double]$nxt.ripenAt - $now)) }
    else { $T2.Text = '' }
    $PetT.Y = if ($mood -eq 'ripe') { [math]::Sin([DateTime]::Now.TimeOfDay.TotalSeconds * 5) * 3 } else { 0 }
    if ($DWindow.Visibility -eq 'Visible') {
        $lines = @('已熟 {0}   快熟 {1}   生长 {2}   空 {3}' -f $ripe, $soon, $grow, ($script:total - $ripe - $soon - $grow))
        $lines += ('─' * 20)
        $ups = $script:plots | Sort-Object { [double]$_.ripenAt } | Select-Object -First 8
        foreach ($p in $ups) { $lines += '{0,-5} {1,-4} {2}' -f $p.name, $p.fruit, (Format-Left ([double]$p.ripenAt - $now)) }
        if (-not $ups) { $lines += '（暂无种植，去手机网页录一块吧）' }
        if ($script:offline) { $lines += '离线中，显示的是上次同步数据' }
        $DText.Text = $lines -join "`n"
    }
}

function Toggle-Detail {
    if ($DWindow.Visibility -eq 'Visible') { $DWindow.Hide(); return }
    $x = $window.Left + 185
    if ($x + 260 -gt [System.Windows.SystemParameters]::WorkArea.Right) { $x = $window.Left - 265 }
    $DWindow.Left = $x
    $DWindow.Top = $window.Top + 10
    $DWindow.Show()
}

# ---------------- 交互 ----------------
$window.Add_MouseLeftButtonDown({
    $dp = [System.Windows.Input.Mouse]::GetPosition($window)
    try { $window.DragMove() } catch {}
    $up = [System.Windows.Input.Mouse]::GetPosition($window)
    if ([math]::Abs($dp.X - $up.X) -lt 4 -and [math]::Abs($dp.Y - $up.Y) -lt 4) { Toggle-Detail }
})
$window.FindName('MRefresh').Add_Click({ Update-Data })
$window.FindName('MWeb').Add_Click({ Start-Process ('https://{0}.github.io/{1}/' -f $cfg['owner'], $cfg['repo']) })
$window.FindName('MSetup').Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $o = [Microsoft.VisualBasic.Interaction]::InputBox('GitHub 用户名', '菠萝岛桌宠设置', $cfg['owner'])
    if ($o) { $cfg['owner'] = $o.Trim() }
    $r = [Microsoft.VisualBasic.Interaction]::InputBox('仓库名', '菠萝岛桌宠设置', $cfg['repo'])
    if ($r) { $cfg['repo'] = $r.Trim() }
    Save-Cfg
    $script:seen = @{}
    $script:booted = $false
    Update-Data
})
$window.FindName('MExit').Add_Click({ $window.Close() })
$window.Add_Closing({
    $cfg['left'] = $window.Left
    $cfg['top'] = $window.Top
    Save-Cfg
})

# ---------------- 位置与启动 ----------------
if ($cfg.ContainsKey('left') -and $cfg['left']) {
    $window.Left = $cfg['left']; $window.Top = $cfg['top']
} else {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $wa.Right - 195
    $window.Top = $wa.Bottom - 232
}

if ($SelfTest) {
    $script:plots = @(
        [pscustomobject]@{ id = 'g1c1'; name = '1-1'; fruit = '山竹'; ripenAt = [double](NowMs + 3600000) }
        [pscustomobject]@{ id = 'g2c3'; name = '2-3'; fruit = '柠檬'; ripenAt = [double](NowMs + 300000) }
    )
    $script:total = 64
    $closeT = New-Object System.Windows.Threading.DispatcherTimer
    $closeT.Interval = [TimeSpan]::FromMilliseconds(1500)
    $closeT.Add_Tick({ $closeT.Stop(); $window.Close() })
    $closeT.Start()
} else {
    Update-Data
}

$ui = New-Object System.Windows.Threading.DispatcherTimer
$ui.Interval = [TimeSpan]::FromSeconds(1)
$ui.Add_Tick({ Update-Tick })
$ui.Start()

$poll = New-Object System.Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromSeconds([int]$cfg['pollSeconds'])
$poll.Add_Tick({ Update-Data })
$poll.Start()

$window.ShowDialog() | Out-Null
$ui.Stop(); $poll.Stop()
if ($SelfTest) { Write-Host 'PET SELFTEST OK' }
