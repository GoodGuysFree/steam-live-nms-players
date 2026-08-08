# Steam Live Players Overlay

A tiny, zero-install overlay that shows a game's **current concurrent Steam player count**
on screen. Defaults to **No Man's Sky**, but works for **any Steam game** via a single flag.

No API key. No pip / npm / installs. Native PowerShell (Windows). Nothing leaves your machine
except one public Steam API call. It comes in two flavors that share the same data and config:

- **A — OBS browser source** — a transparent web widget you add to OBS / Streamlabs. Best when
  you record/stream through OBS.
- **B — Desktop overlay** — an always-on-top, click-through window that floats over your game.
  Best for **Discord "Go Live" with whole-screen share** (no OBS needed).

Use either or both.

![the card: an icon column on the left, then PLAYERS ONLINE, a large live number, HIGH/LOW, and a next-poll/next-change line]

---

## What it shows

Both flavors render the same card:

- **Live player count**, large and centered.
- **Colour cue** — the number turns **green** at the session **high**, **yellow** at the session
  **low**, and stays white in between.
- **HIGH / LOW** — the session peak and trough (highest/lowest seen since you started it; they
  reset on restart).
- **Next poll / Est. next change** — minutes until the next Steam check, and until the count is
  *likely* to change next (see Polling below).
- **Live dot** — green when data is fresh; red (and it keeps the last known number) if Steam
  can't be reached.
- **Record celebration** — if the live count beats `-Threshold` (default `212613`, NMS's
  all-time concurrent record), the current + HIGH numbers get a glow and a **20-second
  fireworks** show plays.
- **Icons** on the left — your chosen icon (or a built-in planet) on top, with the **NMS10 logo**
  beneath it. Both are configurable (see Configuration).

---

## How polling works (why the number sits still for a while)

Steam does **not** update this number continuously. In practice it republishes the concurrent
count only about **once every ~14 minutes**, and it's the same value in between — so the display
legitimately holds steady for many minutes, then jumps.

To avoid pointless requests, both flavors poll **adaptively**:

1. Take the first reading.
2. Go **quiet for `-QuietMinutes` (12)** — a new value won't appear before then anyway.
3. Then poll every **`-ActivePollSeconds` (60)** until the value actually changes.
4. On a change, go quiet again and repeat.

The **Est. next change** line is simply *last change + `-ChangeIntervalMinutes` (14)*. Both tools
stay far under Steam's limit of 100,000 calls/day.

Each real Steam read is echoed to the console window (timestamp, value, high/low, and whether it
changed) so you can see exactly what's happening.

---

## Option A — OBS browser source

Steam's public endpoint sends no CORS headers, so a page inside OBS's browser can't call it
directly. `nms-overlay-server.ps1` runs a tiny local web server that fetches Steam
**server-side** and serves the widget plus a same-origin `/count` endpoint — OBS just points at
`http://localhost:9011/`.

```
OBS Browser Source  ->  http://localhost:9011/         (the widget)
widget (in OBS)     ->  http://localhost:9011/count    (same-origin JSON, no CORS)
local server        ->  api.steampowered.com           (the only outbound call)
```

**Quick start**

1. Double-click **`Start-NMS-Overlay.cmd`**. A console window opens and stays open — that's the
   server. Leave it running while you record.
2. In OBS: **Sources → + → Browser Source → new**. URL `http://localhost:9011/`, size
   **`400 × 150`** (or right-click the source → **Transform → Fit to content**).
3. Position it in your scene. Stop it by closing the console window (or **Ctrl+C**).
4. *(Optional)* For the record-break **fireworks**, add a **second** Browser Source at
   `http://localhost:9011/?mode=fireworks`, sized to your full canvas (e.g. `1920 × 1080`). It's
   transparent and only draws during a celebration — the small card source can't show
   centre-screen fireworks, so this full-screen source is what places them.

**Options**

```powershell
powershell -ExecutionPolicy Bypass -File nms-overlay-server.ps1 -AppId 730 -Port 9011
```

| Flag                     | Default  | Meaning                                                           |
|--------------------------|----------|-------------------------------------------------------------------|
| `-AppId`                 | `275850` | Steam AppID. `275850` = No Man's Sky. Any game's ID works.        |
| `-Port`                  | `9011`   | Local server port (update the OBS URL to match if you change it). |
| `-ActivePollSeconds`     | `60`     | Poll cadence while waiting to catch a change.                     |
| `-QuietMinutes`          | `12`     | Quiet period after the first read / a change.                     |
| `-ChangeIntervalMinutes` | `14`     | Drives the "Est. next change" estimate.                           |
| `-Threshold`             | `212613` | Beat this live and the fireworks fire.                            |

---

## Option B — Desktop overlay (for Discord whole-screen share)

`nms-desktop-overlay.ps1` opens a transparent, always-on-top, **click-through** window (mouse
clicks pass straight through to the game). It talks straight to Steam — no OBS, no server. Its
fireworks are **built in** (full-screen on the same monitor, automatic on a record).

**Quick start**

1. Double-click **`Start-NMS-Desktop-Overlay.cmd`**. The overlay appears in a screen corner; a
   console window stays open.
2. Set your game to **Borderless / Windowed** display mode.
3. In Discord: **Go Live / Screen Share → "Screens" tab → pick the monitor** the game is on.
4. To remove it: close the console window (or **Ctrl+C**).

**Options** (positioning/scale also settable via the config file below)

```powershell
powershell -ExecutionPolicy Bypass -STA -File nms-desktop-overlay.ps1 -Corner TopRight -Monitor 1
```

| Flag                     | Default   | Meaning                                                        |
|--------------------------|-----------|----------------------------------------------------------------|
| `-AppId`                 | `275850`  | Steam AppID (any game).                                        |
| `-Corner`                | `TopLeft` | `TopLeft` / `TopRight` / `BottomRight` / `BottomLeft`.         |
| `-Margin`                | `24`      | Gap from the screen edge (device-independent pixels).         |
| `-Monitor`               | primary   | 0-based display index to place the overlay on.                |
| `-ActivePollSeconds`     | `60`      | Poll cadence while waiting to catch a change.                 |
| `-QuietMinutes`          | `12`      | Quiet period after the first read / a change.                 |
| `-ChangeIntervalMinutes` | `14`      | Drives the "Est. next change" estimate.                        |
| `-Threshold`             | `212613`  | Beat this live -> 20s full-screen fireworks.                  |

### Sizing across screens

The overlay is DPI-aware: it's measured in device-independent units and scales with the viewer's
**Windows display-scaling %**. On typical setups (a 4K monitor at 200%, a 1080p monitor at 100%)
it takes up the **same fraction of the screen**, so it looks the same relative size. If your
scaling is unusual, use `scale` in the config to dial it in.

### ⚠️ Will Discord actually show it?

- ✅ **"Screens" (whole monitor)** — composites everything on that display, so the overlay
  **shows**. The game must be **Borderless / Windowed** (Discord can't capture exclusive
  fullscreen on Windows 11).
- ❌ **"Applications" (single game window)** — Discord captures only that window's own pixels, so
  **no external overlay can appear** (true of any overlay tool). Use whole-screen share instead.

---

## Configuration (`overlay-config.json`)

Both flavors read an optional `overlay-config.json` in this folder (shared, so they stay in
sync). Copy the template and edit:

```powershell
copy overlay-config.sample.json overlay-config.json
```

| Key             | Applies to      | Meaning                                                                        |
|-----------------|-----------------|--------------------------------------------------------------------------------|
| `icon`          | both            | Top icon: a full path, or a filename in this folder / `assets\`. Empty = the built-in planet. |
| `iconOpacity`   | both            | `0.0`–`1.0` opacity for the stacked icons.                                      |
| `showNms10Logo` | both            | Show the NMS10 logo beneath the top icon (`true`/`false`).                      |
| `nms10Logo`     | both            | Path/name of that logo (ships in `assets\nms10-logo.png`).                      |
| `scale`         | desktop         | Size multiplier for the whole card, independent of screen DPI.                  |
| `corner`        | desktop         | `TopLeft` / `TopRight` / `BottomRight` / `BottomLeft`.                          |
| `margin`        | desktop         | Gap from the screen edge (device-independent pixels).                           |
| `monitor`       | desktop         | 0-based display index. `-1` = primary.                                          |

Explicit `-Corner` / `-Margin` / `-Monitor` command-line params override the file. Your
`overlay-config.json` is personal and git-ignored; only the template is tracked. Restart the
overlay (and refresh the OBS source) after editing.

**Custom icon:** point `icon` at your image, or drop it in `assets\` and use
`"assets/yourfile.png"`. In OBS the server serves it at `/icon`; the NMS10 logo is at `/nms10`.

---

## Any game

Find a game's AppID in its Steam store URL — `store.steampowered.com/app/<AppID>/` — and pass it
with `-AppId`. The `-Threshold` default is No Man's Sky's record; set your own for other games.

## Disclaimer

This is an unofficial, fan-made tool. It is **not affiliated with, endorsed by, or sponsored
by** Hello Games (No Man's Sky) or Valve Corporation (Steam). "No Man's Sky", "Steam", and all
related names are trademarks of their respective owners and are used here only descriptively.
The tool uses Steam's public Web API. The bundled `nms10-logo.png` is a community-made asset
(not an official Hello Games asset), included with permission from the NMS10 organizers.

## License

[MIT](LICENSE) © 2026 GoodGuysFree (Amit Margalit)
