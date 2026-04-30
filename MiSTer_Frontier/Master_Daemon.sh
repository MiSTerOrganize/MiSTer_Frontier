#!/bin/bash
#
# MiSTer Frontier — Master Daemon
#
# Watches /tmp/CORENAME and dispatches to per-core _handler.sh scripts
# whenever the user loads a MiSTer Frontier hybrid core.
#
# A hybrid core is identified by the presence of an executable
# /media/fat/games/{CoreName}/_handler.sh. Drop a handler in any game
# folder and this daemon picks it up automatically — no edits needed
# here when adding a new core.
#
# Runs continuously in the background, started at every boot via
# /media/fat/linux/user-startup.sh. Self-installs into user-startup.sh
# on first run if it isn't there already (so it survives even if the
# install script wasn't executed).
#
# Universal hybrid-core daemon pattern (applied here once for every
# core, instead of duplicated across per-core daemons):
#   - chmod +x on every hybrid binary + handler at startup, since
#     update_all does not preserve the executable bit
#   - SIGTERM -> sleep 1 -> SIGKILL on core switch (engines like
#     OpenBOR's borExit() can hang under SDL2 dummy + keepalive)
#   - Startup zombie sweep filtered by /proc/$pid/cwd, so we only
#     kill OUR processes — never an unrelated binary that happens to
#     share a name
#   - Per-core .s0 cleanup on core switch (re-entry goes through OSD
#     picker, doesn't auto-mount previous PAK/cart)
#

SELF="/media/fat/MiSTer_Frontier/Master_Daemon.sh"
STARTUP="/media/fat/linux/user-startup.sh"
LOGDIR="/media/fat/logs/MiSTer_Frontier"
GAMES_ROOT="/media/fat/games"
CONFIG_ROOT="/media/fat/config"

mkdir -p "$LOGDIR"
LOG="$LOGDIR/Master_Daemon.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# ── Self-register in user-startup.sh if missing ──────────────────────
# Belt-and-suspenders for the case where the install script wasn't run.
if [ -f "$STARTUP" ] && ! grep -qF "Master_Daemon.sh" "$STARTUP"; then
    echo "" >> "$STARTUP"
    echo "# MiSTer Frontier — hybrid core master daemon" >> "$STARTUP"
    echo "bash $SELF &" >> "$STARTUP"
    log "Self-registered in $STARTUP"
fi

# ── Discover hybrid cores ────────────────────────────────────────────
# Any games/{Name}/ folder with an executable _handler.sh is a hybrid
# core. Auto-discovery means new cores need no edits to this script.
discover_cores() {
    for dir in "$GAMES_ROOT"/*/; do
        [ -f "$dir/_handler.sh" ] || continue
        basename "$dir"
    done
}

# ── Startup chmod sweep ──────────────────────────────────────────────
# update_all places files at default umask (no execute bit). Master
# fixes that for every hybrid binary + handler at boot.
for core in $(discover_cores); do
    bin="$GAMES_ROOT/$core/$core"
    handler="$GAMES_ROOT/$core/_handler.sh"
    [ -f "$bin" ]     && chmod +x "$bin"     2>/dev/null
    [ -f "$handler" ] && chmod +x "$handler" 2>/dev/null
done
log "Startup chmod sweep: $(discover_cores | tr '\n' ' ')"

# ── Startup zombie sweep ─────────────────────────────────────────────
# Kill any leftover hybrid-core binary from a previous master instance
# (deploy script kill, crash, manual SSH restart). Filter by
# /proc/$pid/cwd matching the core's GAMEDIR so we never kill an
# unrelated process that happens to share a binary name (the OpenBOR
# variants both name their binary "OpenBOR").
for core in $(discover_cores); do
    GAMEDIR="$GAMES_ROOT/$core"
    for pid in $(pidof "$core" 2>/dev/null); do
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
        if [ "$cwd" = "$GAMEDIR" ]; then
            kill -9 "$pid" 2>/dev/null
            log "Startup: killed rogue $core PID $pid"
        fi
    done
done

# ── Helper: aggressive child kill ────────────────────────────────────
# SIGTERM grace window then SIGKILL. Plain SIGTERM can leave a zombie
# writing to DDR3 if the engine ignores it (OpenBOR borExit hangs
# under SDL2 dummy + keepalive). 1-second window is plenty for clean
# engines, forced kill catches the rest.
kill_child() {
    [ -z "$CHILD" ] && return
    kill "$CHILD" 2>/dev/null
    sleep 1
    kill -9 "$CHILD" 2>/dev/null
    wait "$CHILD" 2>/dev/null
    CHILD=""
}

cleanup() {
    log "Master_Daemon shutting down (signal received)"
    kill_child
    exit 0
}
trap cleanup TERM INT

# ── Dispatch loop ────────────────────────────────────────────────────
LAST=""
CHILD=""
log "Master_Daemon started (PID $$)"

while true; do
    CUR=$(cat /tmp/CORENAME 2>/dev/null)

    # Core changed?
    if [ "$CUR" != "$LAST" ]; then
        # Kill the previous core's child cleanly
        if [ -n "$CHILD" ]; then
            log "Core changed: '$LAST' -> '$CUR', killing CHILD PID $CHILD"
            kill_child
        fi

        # When leaving a hybrid core, delete its .s0 so re-entry goes
        # through MiSTer's OSD picker instead of auto-mounting the
        # previous PAK/cart. .cfg files (OSD video settings) are kept.
        if [ -n "$LAST" ] && [ -f "$CONFIG_ROOT/$LAST.s0" ]; then
            rm -f "$CONFIG_ROOT/$LAST.s0"
        fi

        # Spawn the handler for the new core, if it's a hybrid core
        HANDLER="$GAMES_ROOT/$CUR/_handler.sh"
        if [ -n "$CUR" ] && [ -x "$HANDLER" ]; then
            log "Spawning handler for '$CUR'"
            "$HANDLER" &
            CHILD=$!
        fi
        LAST="$CUR"
    fi

    # Detect child exit (engine called exit(0), Reset Pak, crash, etc.)
    # If user is still on the same core, respawn the handler — that's
    # how Reset Pak / cart-quit-and-relaunch is supposed to work.
    if [ -n "$CHILD" ] && ! kill -0 "$CHILD" 2>/dev/null; then
        wait "$CHILD" 2>/dev/null
        EXIT_CODE=$?
        log "'$LAST' handler exited code $EXIT_CODE"
        CHILD=""
        if [ "$CUR" = "$LAST" ] && [ -x "$GAMES_ROOT/$LAST/_handler.sh" ]; then
            log "Respawning handler for '$LAST'"
            "$GAMES_ROOT/$LAST/_handler.sh" &
            CHILD=$!
        fi
    fi

    sleep 1
done
