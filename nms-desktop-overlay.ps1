#requires -Version 5.1
<#
  No Man's Sky - Live Steam Player Count as an always-on-top DESKTOP overlay.

  A transparent, click-through window that floats the current concurrent Steam
  player count on top of your game. Meant for Discord "Go Live" when you share
  your WHOLE SCREEN / MONITOR (the "Screens" tab) -- it composites like anything
  else on that display.

  IMPORTANT:
    - Run the game in BORDERLESS / WINDOWED mode. Exclusive-fullscreen games
      hide all overlays and can't be captured by Discord on Windows 11.
    - Discord "Applications" (single-window) share will NOT show this overlay
      (it captures only that window's pixels). Use whole-screen share.

  Standalone: talks straight to Steam's public API. No OBS, no server, no
  installs. Close it from the console window it launches (or press Ctrl+C there).
#>

param(
    [int]    $AppId          = 275850,      # 275850 = No Man's Sky
    [int]    $RefreshSeconds = 300,         # Steam caches the count ~5 min; no point polling faster
    [ValidateSet('TopRight','TopLeft','BottomRight','BottomLeft')]
    [string] $Corner         = 'TopRight',
    [int]    $Margin         = 24,          # gap from the screen edge (device-independent px)
    [int]    $Monitor        = -1           # 0-based display index; -1 = primary
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

# --- shared state, written by the background poller ------------------------
$sync = [hashtable]::Synchronized(@{ count = $null; ok = $false; at = [DateTime]::MinValue; stop = $false })

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
                $sync.count = [int]$r.response.player_count
                $sync.ok    = $true
                $sync.at    = [DateTime]::UtcNow
            }
        } catch { }
        $slept = 0
        while ($slept -lt $RefreshSeconds -and -not $sync.stop) { Start-Sleep -Seconds 1; $slept++ }
    }
})
[void]$poller.BeginInvoke()

# --- the overlay window (XAML) ---------------------------------------------
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
        <TextBlock x:Name="Sub" Text="live on Steam" Foreground="#8CFFFFFF"
                   FontSize="11" Margin="0,4,0,0" FontFamily="Segoe UI"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$num = $win.FindName('Num')
$dot = $win.FindName('Dot')
$sub = $win.FindName('Sub')

$brushGreen = [Windows.Media.BrushConverter]::new().ConvertFromString('#4EE06A')
$brushRed   = [Windows.Media.BrushConverter]::new().ConvertFromString('#E0574E')
$brushGreen.Freeze(); $brushRed.Freeze()

# make the window click-through + never-activate, once it has a handle
$win.Add_SourceInitialized({
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
    $GWL_EXSTYLE   = -20
    $WS_EX_TRANSPARENT = 0x20; $WS_EX_LAYERED = 0x80000
    $WS_EX_TOOLWINDOW  = 0x80; $WS_EX_NOACTIVATE = 0x08000000
    $ex = [Native]::GetWindowLong($hwnd, $GWL_EXSTYLE)
    $ex = $ex -bor $WS_EX_TRANSPARENT -bor $WS_EX_LAYERED -bor $WS_EX_TOOLWINDOW -bor $WS_EX_NOACTIVATE
    [void][Native]::SetWindowLong($hwnd, $GWL_EXSTYLE, $ex)
})

# position into the chosen corner of the chosen monitor (DPI-correct)
$win.Add_ContentRendered({
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($Monitor -ge 0 -and $Monitor -lt $screens.Count) { $scr = $screens[$Monitor] }
    else { $scr = [System.Windows.Forms.Screen]::PrimaryScreen }
    $wa  = $scr.WorkingArea                                    # physical pixels
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    $t   = $src.CompositionTarget.TransformFromDevice          # px -> device-independent
    $L = $wa.Left * $t.M11; $R = $wa.Right * $t.M11
    $T = $wa.Top  * $t.M22; $B = $wa.Bottom * $t.M22
    $w = $win.ActualWidth;  $h = $win.ActualHeight
    switch ($Corner) {
        'TopLeft'     { $win.Left = $L + $Margin;          $win.Top = $T + $Margin }
        'BottomRight' { $win.Left = $R - $w - $Margin;     $win.Top = $B - $h - $Margin }
        'BottomLeft'  { $win.Left = $L + $Margin;          $win.Top = $B - $h - $Margin }
        default       { $win.Left = $R - $w - $Margin;     $win.Top = $T + $Margin }   # TopRight
    }
})

# UI refresh (reads cached value only -- no network on the UI thread)
$script:shown = $null
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({
    if (-not $sync.ok -or $null -eq $sync.count) { return }
    $target = [int]$sync.count
    if ($null -eq $script:shown) { $script:shown = $target }
    elseif ($script:shown -ne $target) {
        $step = [int](($target - $script:shown) * 0.35)
        if ([math]::Abs($target - $script:shown) -le 2 -or $step -eq 0) { $script:shown = $target }
        else { $script:shown += $step }
    }
    $num.Text = '{0:N0}' -f $script:shown
    $stale = (([DateTime]::UtcNow - $sync.at).TotalSeconds -gt ($RefreshSeconds * 3))
    $dot.Fill = if ($stale) { $brushRed } else { $brushGreen }
    $sub.Text = if ($stale) { 'live on Steam (reconnecting)' } else { 'live on Steam' }
})
$timer.Start()

$win.Add_Closed({
    $sync.stop = $true
    $timer.Stop()
    try { $poller.Stop() } catch { }
    try { $rs.Close() }    catch { }
})

Write-Host ""
Write-Host "  NMS live-players DESKTOP overlay is running ($Corner)." -ForegroundColor Green
Write-Host "  Discord: share your WHOLE SCREEN (Screens tab); run the game Borderless/Windowed." -ForegroundColor Cyan
Write-Host "  To stop: close THIS window, or press Ctrl+C here." -ForegroundColor DarkGray
Write-Host ""

[void]$win.ShowDialog()

# cleanup if the window closed on its own
$sync.stop = $true
try { $poller.Stop(); $poller.Dispose() } catch { }
try { $rs.Close(); $rs.Dispose() }        catch { }
