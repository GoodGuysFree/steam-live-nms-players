# Steam Live Players Overlay

A tiny, zero-install overlay that shows a game's **current concurrent Steam player count**
on screen. Defaults to **No Man's Sky**, but works for **any Steam game** via a single flag.

No API key. No pip / npm / installs. Nothing leaves your machine except one public Steam
API call. Native PowerShell (Windows). It comes in two flavors:

- **A — OBS browser source:** a transparent web widget you add to OBS / Streamlabs. Best for
  recording/streaming through OBS.
- **B — Desktop overlay:** an always-on-top, click-through window that floats over your game.
  Best for **Discord "Go Live" when you share your whole screen** (no OBS needed).

Use either or both — they read the same Steam data.

---

## Option A — OBS browser source

Steam's public endpoint sends no CORS headers, so an HTML overlay can't fetch it directly from
inside OBS's browser. So `nms-overlay-server.ps1` runs a tiny local web server that fetches
Steam **server-side** and serves both the widget and a same-origin `/count` endpoint. OBS just
points at `http://localhost:9011/` — no CORS, no external proxy.

```
OBS Browser Source  ->  http://localhost:9011/         (the widget)
widget (in OBS)     ->  http://localhost:9011/count    (same-origin JSON, no CORS)
local server        ->  api.steampowered.com           (the only outbound call)
```

**Quick start**

1. Double-click **`Start-NMS-Overlay.cmd`**. A console window opens and stays open — that's the
   server. Leave it running while you record.
2. In OBS: **Sources → + → Browser Source → new**. URL `http://localhost:9011/`, size `380 × 118`.
3. Position it in your scene. Stop it by closing the console window (or **Ctrl+C**).
4. *(Optional)* For the record-break **fireworks**, add a **second** Browser Source pointing at
   `http://localhost:9011/?mode=fireworks`, sized to your full canvas (e.g. `1920 × 1080`). It's
   transparent and only draws during a celebration. The card source doesn't show fireworks
   (it's too small); this full-screen source is what puts them in the middle of the screen.

**Options**

```powershell
powershell -ExecutionPolicy Bypass -File nms-overlay-server.ps1 -AppId 730 -Port 9011 -RefreshSeconds 60
```

| Flag              | Default    | Meaning                                                            |
|-------------------|------------|--------------------------------------------------------------------|
| `-AppId`          | `275850`   | Steam AppID. `275850` = No Man's Sky. Use any game's ID.           |
| `-Port`           | `9011`     | Local server port (update the OBS URL to match if you change it).  |
| `-RefreshSeconds` | `60`       | How often the server hits Steam.                                   |
| `-Threshold`      | `212613`   | Beat this live and the fireworks fire (NMS all-time concurrent record). |

---

## Option B — Desktop overlay (for Discord whole-screen share)

`nms-desktop-overlay.ps1` opens a transparent, always-on-top, **click-through** window (mouse
clicks pass straight through to the game) showing the same count. It talks straight to Steam —
no OBS, no server.

**Quick start**

1. Double-click **`Start-NMS-Desktop-Overlay.cmd`**. The overlay appears in a screen corner; a
   console window stays open.
2. In your game, use **Borderless / Windowed** display mode.
3. In Discord, **Go Live / Screen Share → "Screens" tab → pick the monitor** the game is on.
4. To remove the overlay: close the console window (or **Ctrl+C** in it).

**Options**

```powershell
powershell -ExecutionPolicy Bypass -STA -File nms-desktop-overlay.ps1 -Corner TopRight -Monitor 1
```

| Flag              | Default    | Meaning                                                          |
|-------------------|------------|------------------------------------------------------------------|
| `-AppId`          | `275850`   | Steam AppID (any game).                                          |
| `-RefreshSeconds` | `60`       | How often it hits Steam (matches the OBS server).               |
| `-Corner`         | `TopLeft`  | `TopLeft` / `TopRight` / `BottomRight` / `BottomLeft`.           |
| `-Margin`         | `24`       | Gap from the screen edge (device-independent pixels).           |
| `-Monitor`        | primary    | 0-based display index to place the overlay on.                  |
| `-Threshold`      | `212613`   | Beat this live -> 20s full-screen fireworks (NMS all-time record). |

The desktop overlay's fireworks are **built in** — when the record breaks it plays a 20-second
full-screen show on the same monitor automatically. No extra setup.

### ⚠️ Will Discord actually show it?

Discord has two share modes and they behave differently:

- ✅ **"Screens" (whole monitor)** — composites everything on that display, so the overlay
  **shows**. The game must be **Borderless / Windowed** (Discord can't capture exclusive
  fullscreen on Windows 11).
- ❌ **"Applications" (single game window)** — Discord captures only that window's own pixels,
  so **no external overlay can appear** (this applies to any overlay tool, not just this one).
  Use whole-screen share instead.

---

## Notes

- Backgrounds are transparent — only the panel shows over your game.
- **HIGH / LOW** are the session peak and trough — the highest and lowest counts seen since you
  started the overlay. They reset when you restart it.
- **Colours:** the current number turns **green** when it's at the session high, **yellow** when
  it's at the session low, and white in between.
- **Record celebration:** if the live count beats `-Threshold`, the current + high numbers get a
  glow and a 20-second fireworks show plays (desktop: automatic; OBS: via the fireworks source).
- A dot shows live (green) vs. stale/reconnecting (red); the last known number stays on screen
  if Steam can't be reached.
- Steam caches the count for ~5 minutes, so the number won't change faster than that no matter
  how often you poll. Both tools stay far under Steam's 100,000-calls/day limit.

## Disclaimer

This is an unofficial, fan-made tool. It is **not affiliated with, endorsed by, or sponsored
by** Hello Games (No Man's Sky) or Valve Corporation (Steam). "No Man's Sky", "Steam", and all
related names are trademarks of their respective owners and are used here only descriptively.
The tool uses Steam's public Web API. The bundled `nms10-logo.png` is a community-made asset
(not an official Hello Games asset), included with permission from the NMS10 organizers.

## License

[MIT](LICENSE) © 2026 GoodGuysFree (Amit Margalit)
