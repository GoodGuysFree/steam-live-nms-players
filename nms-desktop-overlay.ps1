#requires -Version 5.1
<#
  No Man's Sky - Live Steam Player Count as an always-on-top DESKTOP overlay.

  A transparent, click-through window that floats the current concurrent Steam
  player count on top of your game. Meant for Discord "Go Live" when you share
  your WHOLE SCREEN / MONITOR (the "Screens" tab) -- it composites like anything
  else on that display.

  Extras:
    - Current number turns GREEN at the session high, YELLOW at the session low.
    - Beat the all-time record (-Threshold) and you get a 20s full-screen
      fireworks show plus a glow on the current + high numbers.

  IMPORTANT:
    - Run the game in BORDERLESS / WINDOWED mode. Exclusive-fullscreen games
      hide all overlays and can't be captured by Discord on Windows 11.
    - Discord "Applications" (single-window) share will NOT show this overlay.
      Use whole-screen share.

  Standalone: talks straight to Steam's public API. No OBS, no server, no
  installs. Close it from the console window it launches (or press Ctrl+C there).
#>

param(
    [int]    $AppId          = 275850,      # 275850 = No Man's Sky
    [int]    $RefreshSeconds = 60,          # how often to hit Steam (matches the OBS server default)
    [ValidateSet('TopRight','TopLeft','BottomRight','BottomLeft')]
    [string] $Corner         = 'TopLeft',
    [int]    $Margin         = 24,          # gap from the screen edge (device-independent px)
    [int]    $Monitor        = -1,          # 0-based display index; -1 = primary
    [int]    $Threshold      = 212613       # beat this live -> fireworks (NMS all-time concurrent record)
)

$ErrorActionPreference = 'Stop'
$SteamUrl = "https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid=$AppId"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

# --- native interop: DPI awareness + click-through -------------------------
if (-not ('Native' -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Native {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", SetLastError=true)] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", SetLastError=true)] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
"@
}
[void][Native]::SetProcessDPIAware()

function Set-ClickThrough($window) {
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
    $GWL_EXSTYLE = -20
    $ex = [Native]::GetWindowLong($hwnd, $GWL_EXSTYLE)
    # WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
    $ex = $ex -bor 0x20 -bor 0x80000 -bor 0x80 -bor 0x08000000
    [void][Native]::SetWindowLong($hwnd, $GWL_EXSTYLE, $ex)
}

function Get-Screen {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($Monitor -ge 0 -and $Monitor -lt $screens.Count) { return $screens[$Monitor] }
    return [System.Windows.Forms.Screen]::PrimaryScreen
}

# --- shared state, written by the background poller ------------------------
$sync = [hashtable]::Synchronized(@{
    count = $null; high = $null; low = $null; ok = $false; at = [DateTime]::MinValue
    stop = $false; threshold = $Threshold; threshApplied = $false
    wasAbove = $false; record = $false; recordSeq = 0
})

# --- background poller (own runspace so the UI never blocks on the network) -
$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = 'MTA'
$rs.Open()
$rs.SessionStateProxy.SetVariable('sync', $sync)
$rs.SessionStateProxy.SetVariable('SteamUrl', $SteamUrl)
$rs.SessionStateProxy.SetVariable('RefreshSeconds', $RefreshSeconds)
$poller = [powershell]::Create()
$poller.Runspace = $rs
[void]$poller.AddScript({
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    while (-not $sync.stop) {
        try {
            $r = Invoke-RestMethod -Uri $SteamUrl -TimeoutSec 10
            if ($r.response -and $r.response.result -eq 1) {
                $c = [int]$r.response.player_count
                $sync.count = $c
                $sync.ok    = $true
                $sync.at    = [DateTime]::UtcNow
                if ($null -eq $sync.high -or $c -gt $sync.high) { $sync.high = $c }
                if ($null -eq $sync.low  -or $c -lt $sync.low ) { $sync.low  = $c }

                # --- TEST ONLY: on the first reading, drop the threshold to (value+1)
                #     so the next uptick trips the fireworks. Delete for production. ---
                if (-not $sync.threshApplied) { $sync.threshold = $c + 1; $sync.threshApplied = $true }
                # --- end TEST ---

                $above = $c -gt [int]$sync.threshold
                if ($above -and -not $sync.wasAbove) { $sync.recordSeq = [int]$sync.recordSeq + 1 }
                $sync.wasAbove = $above
                $sync.record   = $above
            }
        } catch { }
        $slept = 0
        while ($slept -lt $RefreshSeconds -and -not $sync.stop) { Start-Sleep -Seconds 1; $slept++ }
    }
})
[void]$poller.BeginInvoke()

# --- the overlay card (XAML) -----------------------------------------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight">
  <Border Padding="16,12,20,12" CornerRadius="14" Background="#9E0A0E16"
          BorderBrush="#59FFB347" BorderThickness="1">
    <Border.Effect>
      <DropShadowEffect BlurRadius="22" ShadowDepth="3" Opacity="0.5" Color="#000000"/>
    </Border.Effect>
    <StackPanel Orientation="Horizontal">
      <Grid Width="34" Height="34" Margin="0,0,14,0" VerticalAlignment="Center">
        <Ellipse Stroke="#FFB347" StrokeThickness="1.6" Width="26" Height="26"/>
        <Ellipse Stroke="#FFB347" StrokeThickness="1.6" Width="33" Height="12"
                 RenderTransformOrigin="0.5,0.5">
          <Ellipse.RenderTransform><RotateTransform Angle="-20"/></Ellipse.RenderTransform>
        </Ellipse>
      </Grid>
      <StackPanel VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
          <Ellipse x:Name="Dot" Width="8" Height="8" Fill="#4EE06A" Margin="0,0,7,0" VerticalAlignment="Center"/>
          <TextBlock Text="PLAYERS ONLINE &#183; NO MAN'S SKY" Foreground="#FFB347"
                     FontSize="11" FontWeight="SemiBold" FontFamily="Segoe UI"/>
        </StackPanel>
        <TextBlock x:Name="Num" Text="&#8212;" Foreground="White" FontSize="30"
                   FontWeight="Bold" FontFamily="Segoe UI"/>
        <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
          <TextBlock Text="&#9650; HIGH " Foreground="#7FD48F" FontSize="14"
                     FontWeight="Bold" FontFamily="Segoe UI"/>
          <TextBlock x:Name="Hi" Text="&#8212;" Foreground="#D9FFFFFF" FontSize="14"
                     FontWeight="SemiBold" FontFamily="Segoe UI" Margin="0,0,12,0"/>
          <TextBlock Text="&#9660; LOW " Foreground="#E79A94" FontSize="14"
                     FontWeight="Bold" FontFamily="Segoe UI"/>
          <TextBlock x:Name="Lo" Text="&#8212;" Foreground="#D9FFFFFF" FontSize="14"
                     FontWeight="SemiBold" FontFamily="Segoe UI"/>
        </StackPanel>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$num = $win.FindName('Num')
$dot = $win.FindName('Dot')
$hi  = $win.FindName('Hi')
$lo  = $win.FindName('Lo')

# --- brushes + record glow --------------------------------------------------
$bc = [Windows.Media.BrushConverter]::new()
$brushGreen  = $bc.ConvertFromString('#4EE06A'); $brushGreen.Freeze()
$brushYellow = $bc.ConvertFromString('#FFD84D'); $brushYellow.Freeze()
$brushWhite  = $bc.ConvertFromString('#FFFFFF'); $brushWhite.Freeze()
$brushRed    = $bc.ConvertFromString('#E0574E'); $brushRed.Freeze()
$glow = New-Object System.Windows.Media.Effects.DropShadowEffect
$glow.Color = [Windows.Media.ColorConverter]::ConvertFromString('#FFB347')
$glow.BlurRadius = 22; $glow.ShadowDepth = 0; $glow.Opacity = 0.95
$glow.Freeze()

# --- full-screen fireworks window ------------------------------------------
[xml]$fxXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize">
  <Canvas x:Name="Fx" IsHitTestVisible="False"/>
</Window>
'@
$fxWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $fxXaml))
$script:fxCanvas = $fxWindow.FindName('Fx')
$script:fxWhite  = $bc.ConvertFromString('#FFFFFF'); $script:fxWhite.Freeze()
$script:fxRunning = $false
$script:fxEnd = [DateTime]::MinValue
$script:fxBurstTimer = $null

$fxWindow.Add_SourceInitialized({ Set-ClickThrough $fxWindow })
$fxWindow.Add_Loaded({
    $scr = Get-Screen
    $b   = $scr.Bounds                                            # full monitor (physical px)
    $src = [System.Windows.PresentationSource]::FromVisual($fxWindow)
    $t   = $src.CompositionTarget.TransformFromDevice
    $fxWindow.Left   = $b.Left   * $t.M11
    $fxWindow.Top    = $b.Top    * $t.M22
    $fxWindow.Width  = $b.Width  * $t.M11
    $fxWindow.Height = $b.Height * $t.M22
})

function Add-Particle($cx, $cy, $col) {
    $angle = (Get-Random -Minimum 0 -Maximum 6283) / 1000.0
    $speed = 50 + (Get-Random -Minimum 0 -Maximum 230)
    $life  = 1.1 + (Get-Random -Minimum 0 -Maximum 90) / 100.0
    $vx = [math]::Cos($angle) * $speed
    $vy = [math]::Sin($angle) * $speed
    $g  = 320.0
    $endX = $cx + $vx * $life
    $endY = $cy + $vy * $life + 0.5 * $g * $life * $life
    $r = 2 + (Get-Random -Minimum 0 -Maximum 2)
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = $r * 2; $e.Height = $r * 2
    if ((Get-Random -Minimum 0 -Maximum 100) -lt 15) { $e.Fill = $script:fxWhite }
    else { $b2 = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($col)); $b2.Freeze(); $e.Fill = $b2 }
    [System.Windows.Controls.Canvas]::SetLeft($e, $cx)
    [System.Windows.Controls.Canvas]::SetTop($e, $cy)
    [void]$script:fxCanvas.Children.Add($e)
    $dur = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds($life))
    $ax = New-Object System.Windows.Media.Animation.DoubleAnimation $cx, $endX, $dur
    $ay = New-Object System.Windows.Media.Animation.DoubleAnimation $cy, $endY, $dur
    $eIn = New-Object System.Windows.Media.Animation.QuadraticEase; $eIn.EasingMode = 'EaseIn'
    $ay.EasingFunction = $eIn
    $ao = New-Object System.Windows.Media.Animation.DoubleAnimation 1.0, 0.0, $dur
    $eIn2 = New-Object System.Windows.Media.Animation.QuadraticEase; $eIn2.EasingMode = 'EaseIn'
    $ao.EasingFunction = $eIn2
    $el = $e; $canvas = $script:fxCanvas   # capture as locals so GetNewClosure snapshots them
    $ao.Add_Completed(({ [void]$canvas.Children.Remove($el) }).GetNewClosure())
    $e.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, $ax)
    $e.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $ay)
    $e.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $ao)
}

function Invoke-Burst {
    $w = $script:fxCanvas.ActualWidth;  if ($w -lt 50) { $w = 1280 }
    $h = $script:fxCanvas.ActualHeight; if ($h -lt 50) { $h = 720 }
    $cx = $w * (0.30 + (Get-Random -Minimum 0 -Maximum 40) / 100.0)
    $cy = $h * (0.22 + (Get-Random -Minimum 0 -Maximum 34) / 100.0)
    $palette = @('#FFD84D','#FFB347','#FF6B6B','#4EE06A','#5BD6FF','#C78BFF')
    $col = $palette[(Get-Random -Minimum 0 -Maximum $palette.Count)]
    for ($i = 0; $i -lt 46; $i++) { Add-Particle $cx $cy $col }
}

function Start-Fireworks {
    if ($script:fxRunning) { return }
    $script:fxRunning = $true
    $script:fxEnd = [DateTime]::UtcNow.AddSeconds(20)
    Invoke-Burst
    $script:fxBurstTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:fxBurstTimer.Interval = [TimeSpan]::FromMilliseconds(550)
    $script:fxBurstTimer.Add_Tick({
        if ([DateTime]::UtcNow -ge $script:fxEnd) { $script:fxBurstTimer.Stop(); $script:fxRunning = $false; return }
        Invoke-Burst
    })
    $script:fxBurstTimer.Start()
}

# --- card placement + click-through ----------------------------------------
$win.Add_SourceInitialized({ Set-ClickThrough $win })
$win.Add_ContentRendered({
    $scr = Get-Screen
    $wa  = $scr.WorkingArea
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    $t   = $src.CompositionTarget.TransformFromDevice
    $L = $wa.Left * $t.M11; $R = $wa.Right * $t.M11
    $T = $wa.Top  * $t.M22; $B = $wa.Bottom * $t.M22
    $w = $win.ActualWidth;  $h = $win.ActualHeight
    switch ($Corner) {
        'TopLeft'     { $win.Left = $L + $Margin;      $win.Top = $T + $Margin }
        'BottomRight' { $win.Left = $R - $w - $Margin; $win.Top = $B - $h - $Margin }
        'BottomLeft'  { $win.Left = $L + $Margin;      $win.Top = $B - $h - $Margin }
        default       { $win.Left = $R - $w - $Margin; $win.Top = $T + $Margin }   # TopRight
    }
})

# --- UI refresh (reads cached values only -- no network on the UI thread) ---
$script:shown = $null
$script:lastSeq = 0
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    if (-not $sync.ok -or $null -eq $sync.count) { return }
    $target = [int]$sync.count

    # smooth roll toward the latest value
    if ($null -eq $script:shown) { $script:shown = $target }
    elseif ($script:shown -ne $target) {
        $step = [int](($target - $script:shown) * 0.35)
        if ([math]::Abs($target - $script:shown) -le 2 -or $step -eq 0) { $script:shown = $target }
        else { $script:shown += $step }
    }
    $num.Text = '{0:N0}' -f $script:shown
    if ($null -ne $sync.high) { $hi.Text = '{0:N0}' -f [int]$sync.high }
    if ($null -ne $sync.low ) { $lo.Text = '{0:N0}' -f [int]$sync.low }

    # colour: green at the high, yellow at the low, white otherwise
    if     ($null -ne $sync.high -and $target -eq [int]$sync.high) { $num.Foreground = $brushGreen }
    elseif ($null -ne $sync.low  -and $target -eq [int]$sync.low -and [int]$sync.high -gt [int]$sync.low) { $num.Foreground = $brushYellow }
    else   { $num.Foreground = $brushWhite }

    # record glow on current + high
    if ($sync.record -eq $true) { $num.Effect = $glow; $hi.Effect = $glow }
    else { $num.Effect = $null; $hi.Effect = $null }

    # dot: live vs stale
    $stale = (([DateTime]::UtcNow - $sync.at).TotalSeconds -gt ($RefreshSeconds * 3))
    $dot.Fill = if ($stale) { $brushRed } else { $brushGreen }

    # fire the fireworks once per record crossing
    if ([int]$sync.recordSeq -ne $script:lastSeq) {
        $script:lastSeq = [int]$sync.recordSeq
        if ([int]$sync.recordSeq -gt 0) { Start-Fireworks }
    }
})
$timer.Start()

$win.Add_Closed({
    $sync.stop = $true
    $timer.Stop()
    if ($script:fxBurstTimer) { $script:fxBurstTimer.Stop() }
    try { $fxWindow.Close() } catch { }
    try { $poller.Stop() }    catch { }
    try { $rs.Close() }       catch { }
    $win.Dispatcher.InvokeShutdown()
})

Write-Host ""
Write-Host "  NMS live-players DESKTOP overlay is running ($Corner)." -ForegroundColor Green
Write-Host "  Discord: share your WHOLE SCREEN (Screens tab); run the game Borderless/Windowed." -ForegroundColor Cyan
Write-Host "  To stop: close THIS window, or press Ctrl+C here." -ForegroundColor DarkGray
Write-Host ""

$win.Show()
$fxWindow.Show()
[System.Windows.Threading.Dispatcher]::Run()

# cleanup
$sync.stop = $true
try { $poller.Stop(); $poller.Dispose() } catch { }
try { $rs.Close(); $rs.Dispose() }        catch { }
