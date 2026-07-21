@echo off
REM Double-click to start the No Man's Sky live-player overlay server.
REM Leave this window open while recording; close it (or Ctrl+C) to stop.
title NMS Live Players Overlay
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nms-overlay-server.ps1"
echo.
echo Overlay server stopped. Press any key to close.
pause >nul
