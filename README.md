# Steam Live Players Overlay

A tiny, zero-install overlay that shows a game's **current concurrent Steam player count**
as a clean widget you can drop into OBS / Streamlabs as a Browser Source. Defaults to
**No Man's Sky**, but works for **any Steam game** via a single flag.

No API key. No pip / npm / installs. Nothing leaves your machine except one public Steam
API call. It's a single native PowerShell script (Windows).

## How it works

Steam's public player-count endpoint sends no CORS headers, so an HTML overlay can't fetch
it directly from inside OBS's browser. Instead, the script runs a tiny local web server that
fetches Steam **server-side** and serves both the widget and a same-origin `/count` endpoint.
OBS just points at `http://localhost:9011/` — no CORS, no external proxy, no data leaving
your PC beyond the one Steam call.

```
OBS Browser Source  ->  http://localhost:9011/         (the widget)
widget (in OBS)     ->  http://localhost:9011/count    (same-origin JSON, no CORS)
local server        ->  api.steampowered.com           (the only outbound call)
```

## Quick start

1. Double-click **`Start-NMS-Overlay.cmd`**. A console window opens and stays open — that's
   the little server. Leave it running while you record. (Or run the `.ps1` directly.)
2. In OBS: **Sources → + → Browser Source → new**.
   - URL: `http://localhost:9011/`
   - Width `360`, Height `90`
3. Position it in your scene. The number updates itself live.

Stop it by closing the console window (or pressing **Ctrl+C** in it).

## Options

Run the script from a terminal to change defaults:

```powershell
powershell -ExecutionPolicy Bypass -File nms-overlay-server.ps1 -AppId 730 -Port 9011 -RefreshSeconds 60
```

| Flag              | Default  | Meaning                                                            |
|-------------------|----------|--------------------------------------------------------------------|
| `-AppId`          | `275850` | Steam AppID. `275850` = No Man's Sky. Use any game's ID.           |
| `-Port`           | `9011`   | Local server port (update the OBS URL to match if you change it).  |
| `-RefreshSeconds` | `60`     | How often the server actually hits Steam (the count moves slowly). |

Find any game's AppID in its Steam store URL: `store.steampowered.com/app/<AppID>/`.

## Notes

- The card background is transparent, so only the panel shows over your footage.
- A green dot pulses while data is live; it turns red (and keeps the last known number on
  screen) if Steam can't be reached.
- The widget re-polls the local server every 30s; the server hits Steam at most once per
  `-RefreshSeconds`. Well within Steam's 100,000-calls/day limit.

## Disclaimer

This is an unofficial, fan-made tool. It is **not affiliated with, endorsed by, or sponsored
by** Hello Games (No Man's Sky) or Valve Corporation (Steam). "No Man's Sky", "Steam", and all
related names are trademarks of their respective owners and are used here only descriptively.
The tool uses Steam's public Web API and bundles no game assets.

## License

[MIT](LICENSE) © 2026 Amit Margalit
