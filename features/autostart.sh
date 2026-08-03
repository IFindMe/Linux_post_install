#!/usr/bin/env bash

LOG="${HOME:-/root}/.autostart.log"

echo "[$(date)] autostart running" >> "$LOG" 2>/dev/null || true

# Check network connectivity
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "[$(date)] Network: online" >> "$LOG" 2>/dev/null || true
else
    echo "[$(date)] Network: offline" >> "$LOG" 2>/dev/null || true
fi

echo "[$(date)] autostart complete" >> "$LOG" 2>/dev/null || true
