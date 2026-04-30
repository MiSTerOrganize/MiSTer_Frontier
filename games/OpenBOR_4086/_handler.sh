#!/bin/bash
#
# OpenBOR_4086 handler — invoked by Master_Daemon when the
# OpenBOR_4086 core loads.
#
# Master_Daemon owns the lifecycle. This handler sets up the SDL
# environment, archives the previous OpenBOR engine log (for crash
# diagnostics across restart loops), and execs the binary.

GAMEDIR="/media/fat/games/OpenBOR_4086"
LOGDIR="/media/fat/logs/OpenBOR_4086"

cd "$GAMEDIR" || exit 1

mkdir -p "$LOGDIR" Logs

# Rotate ARM-binary log
mv -f "$LOGDIR/OpenBOR.log" "$LOGDIR/OpenBOR.prev.log" 2>/dev/null

# Preserve OpenBOR's internal engine log across restarts. The engine
# opens Logs/OpenBorLog.txt in 'wt' (truncate) mode on every launch,
# so without archiving, a crash loop wipes the diagnostic info from
# the actual failure. Keep one prev + a timestamped copy of any
# non-empty current log.
if [ -s Logs/OpenBorLog.txt ]; then
    cp -f Logs/OpenBorLog.txt "Logs/OpenBorLog.$(date +%H%M%S).txt" 2>/dev/null
fi
mv -f Logs/OpenBorLog.txt Logs/OpenBorLog.prev.txt 2>/dev/null

# Free kernel page cache — FC0 streams 50-150 MB PAKs through SPI on
# load, exhausting RAM if the cache isn't dropped. OpenBOR segfaults
# on repeated PAK loads without this.
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

# OpenBOR build 4086 = SDL 1.2.15 with custom dummy video driver
export SDL_VIDEODRIVER=dummy

# FPGA settle on first launch
sleep 1

exec ./OpenBOR > "$LOGDIR/OpenBOR.log" 2>&1
