@echo off
REM Double-click to start the always-on-top DESKTOP overlay (for Discord whole-screen share).
REM Leave this window open while streaming; close it (or Ctrl+C) to remove the overlay.
title NMS Live Players - Desktop Overlay
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0nms-desktop-overlay.ps1"
