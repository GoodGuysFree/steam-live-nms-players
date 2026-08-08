#requires -Version 5.1
<#
  No Man's Sky - Live Steam Player Count overlay for OBS.

  Starts a tiny local web server that:
    - fetches the current concurrent Steam player count (keyless public API)
    - serves the overlay widget at  http://localhost:8787/
    - serves live JSON at           http://localhost:8787/count

  Add "http://localhost:8787/" as a Browser Source in OBS. Done.

  Nothing leaves this machine except the single Steam API call. No pip / npm / installs.
#>

param(
    [int]    $Port  = 9011,
    [int]    $AppId = 275850,     # 275850 = No Man's Sky
    [int]    $RefreshSeconds = 60 # how often to actually hit Steam (count moves slowly)
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$SteamUrl = "https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid=$AppId"

# ---- cache -----------------------------------------------------------------
$script:Count   = $null
$script:High    = $null       # session peak since this server started
$script:Low     = $null       # session trough since this server started
$script:At      = [DateTime]::MinValue
$script:Ok      = $false

function Get-PlayerCount {
    $age = ([DateTime]::UtcNow - $script:At).TotalSeconds
    if ($script:Ok -and $age -lt $RefreshSeconds) { return }   # serve cache
    try {
        $resp = Invoke-RestMethod -Uri $SteamUrl -TimeoutSec 10
        if ($resp.response -and $resp.response.result -eq 1) {
            $script:Count = [int]$resp.response.player_count
            $script:At    = [DateTime]::UtcNow
            $script:Ok    = $true
            if ($null -eq $script:High -or $script:Count -gt $script:High) { $script:High = $script:Count }
            if ($null -eq $script:Low  -or $script:Count -lt $script:Low ) { $script:Low  = $script:Count }
        }
    } catch {
        # keep last known good value; mark stale only if we never had one
        Write-Host ("[{0}] Steam fetch failed: {1}" -f (Get-Date -Format T), $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

# ---- overlay page (single-quoted here-string => no PS interpolation) --------
$Html = @'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>NMS Live Players</title>
<style>
  :root{ --amber:#ffb347; --amber-dim:#e8922e; --panel:rgba(8,14,22,.62); }
  html,body{ margin:0; background:transparent; overflow:hidden;
             font-family:"Segoe UI",Roboto,system-ui,sans-serif; }
  #card{
    display:inline-flex; align-items:center; gap:14px;
    margin:16px; padding:14px 20px 14px 16px;
    background:var(--panel);
    border:1px solid rgba(255,179,71,.35);
    border-radius:14px;
    box-shadow:0 6px 26px rgba(0,0,0,.45), inset 0 0 0 1px rgba(255,255,255,.03);
    -webkit-backdrop-filter:blur(3px); backdrop-filter:blur(3px);
  }
  #glyph{ width:34px; height:34px; flex:0 0 auto; opacity:.95;
          filter:drop-shadow(0 0 6px rgba(255,179,71,.4)); }
  #text{ line-height:1; }
  #label{ font-size:11px; letter-spacing:.22em; text-transform:uppercase;
          color:var(--amber); font-weight:600; margin-bottom:6px;
          display:flex; align-items:center; gap:7px; }
  #dot{ width:8px; height:8px; border-radius:50%; background:#4ee06a;
        box-shadow:0 0 8px #4ee06a; animation:pulse 2s infinite; }
  #dot.stale{ background:#e0574e; box-shadow:0 0 8px #e0574e; animation:none; }
  @keyframes pulse{ 0%,100%{opacity:1} 50%{opacity:.35} }
  #num{ font-size:34px; font-weight:800; color:#fff; letter-spacing:.01em;
        font-variant-numeric:tabular-nums;
        text-shadow:0 1px 2px rgba(0,0,0,.6); }
  #hilo{ font-size:12px; margin-top:6px; color:rgba(255,255,255,.62);
         font-variant-numeric:tabular-nums; letter-spacing:.03em;
         display:flex; gap:12px; }
  #hilo .k{ font-weight:700; margin-right:3px; }
  #hilo .hi .k{ color:#7fd48f; }
  #hilo .lo .k{ color:#e79a94; }
  #hilo b{ color:rgba(255,255,255,.85); font-weight:600; }
</style>
</head>
<body>
  <div id="card">
    <svg id="glyph" viewBox="0 0 24 24" fill="none" stroke="#ffb347" stroke-width="1.6"
         stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="9"/>
      <ellipse cx="12" cy="12" rx="9" ry="3.6"/>
      <path d="M4 9.5c3 1.6 13 1.6 16 0M4 14.5c3-1.6 13-1.6 16 0"/>
    </svg>
    <div id="text">
      <div id="label"><span id="dot"></span>Players Online &middot; No Man's Sky</div>
      <div id="num">&mdash;</div>
      <div id="hilo">
        <span class="hi"><span class="k">&#9650; HIGH</span><b id="hi">&mdash;</b></span>
        <span class="lo"><span class="k">&#9660; LOW</span><b id="lo">&mdash;</b></span>
      </div>
    </div>
  </div>

<script>
  var numEl = document.getElementById('num');
  var dotEl = document.getElementById('dot');
  var hiEl  = document.getElementById('hi');
  var loEl  = document.getElementById('lo');
  var shown = 0;

  function fmt(n){ return (typeof n === 'number') ? n.toLocaleString('en-US') : '—'; }

  function animateTo(target){
    var start = shown, t0 = null, dur = 700;
    function step(ts){
      if(!t0) t0 = ts;
      var p = Math.min(1, (ts - t0) / dur);
      var e = 1 - Math.pow(1 - p, 3);              // ease-out cubic
      var val = Math.round(start + (target - start) * e);
      numEl.textContent = val.toLocaleString('en-US');
      if(p < 1) requestAnimationFrame(step); else shown = target;
    }
    requestAnimationFrame(step);
  }

  function tick(){
    fetch('/count', {cache:'no-store'})
      .then(function(r){ return r.json(); })
      .then(function(d){
        if(d && d.ok && typeof d.count === 'number'){
          animateTo(d.count);
          hiEl.textContent = fmt(d.high);
          loEl.textContent = fmt(d.low);
          dotEl.classList.toggle('stale', d.stale === true);
        } else {
          dotEl.classList.add('stale');
        }
      })
      .catch(function(){ dotEl.classList.add('stale'); });
  }

  tick();
  setInterval(tick, 30000);   // widget re-polls the local server every 30s
</script>
</body>
</html>
'@

# ---- HTTP server ------------------------------------------------------------
$listener = [System.Net.HttpListener]::new()
$prefix   = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "Could not start server on $prefix" -ForegroundColor Red
    Write-Host "Another program may be using port $Port. Re-run with:  -Port 9012" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "  No Man's Sky live-players overlay is running." -ForegroundColor Green
Write-Host "  In OBS: add a Browser Source ->  $prefix" -ForegroundColor Cyan
Write-Host "  (suggested size: 380 x 118)" -ForegroundColor DarkGray
Write-Host "  Press Ctrl+C in this window to stop." -ForegroundColor DarkGray
Write-Host ""

$htmlBytes = [Text.Encoding]::UTF8.GetBytes($Html)

try {
    while ($listener.IsListening) {
        # GetContextAsync + polled wait so Ctrl+C can interrupt between slices.
        # (Plain GetContext() is a native blocking call that swallows Ctrl+C
        #  until the next request arrives.)
        $task = $listener.GetContextAsync()
        while (-not $task.Wait(200)) { }
        $ctx  = $task.Result
        $req  = $ctx.Request
        $res  = $ctx.Response
        $path = $req.Url.AbsolutePath

        try {
            if ($path -eq '/count') {
                Get-PlayerCount
                $stale = (([DateTime]::UtcNow - $script:At).TotalSeconds -gt ($RefreshSeconds * 3))
                $payload = @{
                    ok    = [bool]$script:Ok
                    count = $script:Count
                    high  = $script:High
                    low   = $script:Low
                    stale = [bool]$stale
                } | ConvertTo-Json -Compress
                $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
                $res.ContentType = 'application/json'
                $res.Headers.Add('Cache-Control','no-store')
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            elseif ($path -eq '/' -or $path -eq '/index.html') {
                $res.ContentType = 'text/html; charset=utf-8'
                $res.OutputStream.Write($htmlBytes, 0, $htmlBytes.Length)
            }
            else {
                $res.StatusCode = 404
            }
        } catch {
            $res.StatusCode = 500
        } finally {
            $res.Close()
        }
    }
} finally {
    Write-Host "`n  Stopping overlay server..." -ForegroundColor DarkGray
    $listener.Stop()
    $listener.Close()
}
