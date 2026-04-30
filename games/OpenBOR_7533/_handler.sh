#!/bin/bash
#
# OpenBOR_7533 handler — invoked by Master_Daemon when the
# OpenBOR_7533 core loads.
#
# Master_Daemon owns the lifecycle. This handler sets up the SDL2
# environment (dummy video + audio + software renderer), archives
# the previous OpenBOR engine log, and execs the binary.

GAMEDIR="/media/fat/games/OpenBOR_7533"
LOGDIR="/media/fat/logs/OpenBOR_7533"

cd "$GAMEDIR" || exit 1

mkdir -p "$LOGDIR" Logs

# Rotate ARM-binary log
mv -f "$LOGDIR/OpenBOR.log" "$LOGDIR/OpenBOR.prev.log" 2>/dev/null

# Preserve OpenBOR's internal engine log across restart loops
# (truncated on every launch in 'wt' mode by the engine itself).
# Keeps one prev + timestamped copy of any non-empty current log.
if [ -s Logs/OpenBorLog.txt ]; then
    cp -f Logs/OpenBorLog.txt "Logs/OpenBorLog.$(date +%H%M%S).txt" 2>/dev/null
fi
mv -f Logs/OpenBorLog.txt   Logs/OpenBorLog.prev.txt   2>/dev/null
mv -f Logs/ScriptLog.txt    Logs/ScriptLog.prev.txt    2>/dev/null

# Free kernel page cache — FC0 PAK streaming exhausts RAM otherwise.
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

# OpenBOR build 7533 = SDL 2.0.8 with patched dummy framebuffer.
# Dummy video driver registers no render driver, so SDL_CreateRenderer
# fails silently — force software renderer explicitly.
export SDL_VIDEODRIVER=dummy
export SDL_AUDIODRIVER=dummy
export SDL_RENDER_DRIVER=software

# FPGA settle on first launch
sleep 1

exec ./OpenBOR > "$LOGDIR/OpenBOR.log" 2>&1
