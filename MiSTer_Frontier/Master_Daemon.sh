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

# Rotate at launch, exactly like every per-core handler does. This log had NO
# rotation and NO prune anywhere in the script -- the one shipped script the
# project's own auto-prune rule did not reach -- so it grew monotonically for
# the life of the SD card. One .prev generation is enough here: the daemon logs
# a handful of lines per core switch, not per frame.
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.prev" 2>/dev/null

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# ── Self-register in user-startup.sh if missing ──────────────────────
# Belt-and-suspenders for the case where the install script wasn't run.
if [ -f "$STARTUP" ] && ! grep -qF "Master_Daemon.sh" "$STARTUP"; then
    echo "" >> "$STARTUP"
    echo "# MiSTer Frontier - hybrid core master daemon" >> "$STARTUP"
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
# 🛑 The binary name is NOT always the folder name. The folder is "OpenBOR"
# while the binaries are OpenBOR_4086 and OpenBOR_7533, so the old
# "$core/$core" form resolved to games/OpenBOR/OpenBOR -- a path that does not
# exist -- and this sweep silently did nothing for either OpenBOR core for as
# long as it has existed. PICO-8 worked only because its names coincide.
#
# That matters on an NFS-hosted /games, where Unix permissions are enforced and
# update_all (which runs repeatedly) strips the execute bit, while
# Install_MiSTer_Frontier.sh (which sets it) runs once. Install already uses
# this exact "$core_name"|"$core_name"_* shape; the daemon did not.
for core in $(discover_cores); do
    handler="$GAMES_ROOT/$core/_handler.sh"
    [ -f "$handler" ] && chmod +x "$handler" 2>/dev/null
    for bin in "$GAMES_ROOT/$core/$core" "$GAMES_ROOT/$core/$core"_*; do
        [ -f "$bin" ] && chmod +x "$bin" 2>/dev/null
    done
done
log "Startup chmod sweep: $(discover_cores | tr '\n' ' ')"

# ── Startup zombie sweep ─────────────────────────────────────────────
# Kill any leftover hybrid-core binary from a previous master instance
# (deploy script kill, crash, manual SSH restart).
#
# Same folder-name-vs-binary-name bug as the chmod sweep above: `pidof OpenBOR`
# matches nothing, because the running binaries are OpenBOR_4086 and
# OpenBOR_7533. This swept only PICO-8. Enumerate the real binaries instead.
#
# pidof matches the executable BASENAME exactly, so it can never match MiSTer
# Main (basename "MiSTer") -- unlike a grep over cmdline, which would, because
# Main's argv carries the .rbf path. The /proc/$pid/cwd filter is a second
# guard: it pins the kill to a process actually launched from this GAMEDIR.
for core in $(discover_cores); do
    GAMEDIR="$GAMES_ROOT/$core"
    for bin in "$GAMEDIR/$core" "$GAMEDIR/$core"_*; do
        [ -f "$bin" ] || continue
        bname=$(basename "$bin")
        for pid in $(pidof "$bname" 2>/dev/null); do
            cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
            if [ "$cwd" = "$GAMEDIR" ]; then
                kill -9 "$pid" 2>/dev/null
                log "Startup: killed rogue $bname PID $pid"
            fi
        done
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

# Clear any stale .s0 files for every hybrid core at startup. Master_Daemon
# normally clears .s0 on core transition (leaving a hybrid core), but cannot
# clear on POWER OFF — so a previous session's .s0 survives reboot and the
# next launch of that core auto-mounts the stale path instead of waiting
# for OSD pick. Cleanup here ensures fresh-boot behavior matches in-session
# behavior: every hybrid-core entry waits for OSD pick (or MGL write, which
# happens after this point so isn't affected).
for HANDLER_DIR in "$GAMES_ROOT"/*/_handler.sh; do
    [ -f "$HANDLER_DIR" ] || continue
    CORE_NAME=$(basename "$(dirname "$HANDLER_DIR")")
    if [ -f "$CONFIG_ROOT/$CORE_NAME.s0" ]; then
        log "Cleared stale boot-time .s0 for hybrid core '$CORE_NAME'"
        rm -f "$CONFIG_ROOT/$CORE_NAME.s0"
    fi
done

LAST_RBF=""

# Respawn backoff. A handler that exits immediately -- missing $GAMEDIR so its
# `cd ... || exit 1` fires, a binary that is absent or lost its execute bit,
# ETXTBSY mid-deploy -- was respawned every loop, forever, with no cap and no
# delay. That is a tight fork loop writing two log lines a second (and, before
# the rotation above, into a log that never shrank).
#
# Five immediate exits in a row and it stops, loudly, once. Anything that runs
# longer than RESPAWN_MIN_RUN clears the streak, so a legitimate Reset Pak or
# cart-quit -- which is a deliberate exit after a real session -- never counts
# toward it. Switching cores clears it too.
RESPAWN_FAILS=0
RESPAWN_HALTED=0
SPAWN_TIME=0
RESPAWN_MAX=5
RESPAWN_MIN_RUN=5

while true; do
    CUR=$(cat /tmp/CORENAME 2>/dev/null)
    # Also track the loaded RBF path (MiSTer Main's argv[1]) — sister-core
    # forks (e.g. OpenBOR_4086 + OpenBOR_7533) share the same CONF_STR
    # setname so CORENAME doesn't change when switching between them.
    # Without RBF tracking, swapping 4086 ↔ 7533 leaves the previous
    # binary running with the previous PAK auto-mounted via .s0.
    MISTER_PID=$(pidof MiSTer 2>/dev/null | awk '{print $1}')
    CUR_RBF=""
    if [ -n "$MISTER_PID" ] && [ -r "/proc/$MISTER_PID/cmdline" ]; then
        # cmdline is NUL-separated; argv[1] is the loaded RBF path
        CUR_RBF=$(tr '\0' '\n' < "/proc/$MISTER_PID/cmdline" 2>/dev/null | sed -n 2p)
    fi

    # Core changed OR (same core but RBF changed — sister-core swap)?
    if [ "$CUR" != "$LAST" ] || { [ -n "$CUR_RBF" ] && [ -n "$LAST_RBF" ] && [ "$CUR_RBF" != "$LAST_RBF" ]; }; then
        # Kill the previous core's child cleanly
        if [ -n "$CHILD" ]; then
            if [ "$CUR" != "$LAST" ]; then
                log "Core changed: '$LAST' -> '$CUR', killing CHILD PID $CHILD"
            else
                log "Sister-core RBF swap within '$CUR': '$LAST_RBF' -> '$CUR_RBF', killing CHILD PID $CHILD"
            fi
            kill_child
        fi

        # Delete .s0 so re-entry/swap goes through OSD picker instead of
        # auto-mounting the previous PAK/cart. Use LAST for cross-core
        # transitions, CUR for sister-core RBF swap (same setname).
        STALE_CORE="${LAST:-$CUR}"
        if [ -n "$STALE_CORE" ] && [ -f "$CONFIG_ROOT/$STALE_CORE.s0" ]; then
            log "Cleared stale .s0 for '$STALE_CORE' (PAK/cart picker on re-entry)"
            rm -f "$CONFIG_ROOT/$STALE_CORE.s0"
        fi

        # Spawn the handler for the new core, if it's a hybrid core
        HANDLER="$GAMES_ROOT/$CUR/_handler.sh"
        # A core change is a fresh start: clear any halted respawn streak, so a
        # core that was failing is retried once the user comes back to it.
        RESPAWN_FAILS=0
        RESPAWN_HALTED=0
        if [ -n "$CUR" ] && [ -x "$HANDLER" ]; then
            log "Spawning handler for '$CUR' (RBF=$CUR_RBF)"
            "$HANDLER" &
            CHILD=$!
            SPAWN_TIME=$(date +%s)
        fi
        LAST="$CUR"
        LAST_RBF="$CUR_RBF"
    fi

    # Detect child exit (engine called exit(0), Reset Pak, crash, etc.)
    # If user is still on the same core, respawn the handler — that's
    # how Reset Pak / cart-quit-and-relaunch is supposed to work.
    if [ -n "$CHILD" ] && ! kill -0 "$CHILD" 2>/dev/null; then
        wait "$CHILD" 2>/dev/null
        EXIT_CODE=$?
        log "'$LAST' handler exited code $EXIT_CODE"
        CHILD=""

        # Did it actually run, or did it fall over on startup? A real session
        # (Reset Pak, cart quit) lasts far longer than RESPAWN_MIN_RUN, so this
        # only counts handlers that are failing to start at all.
        NOW=$(date +%s)
        if [ "$SPAWN_TIME" -gt 0 ] && [ $(( NOW - SPAWN_TIME )) -lt "$RESPAWN_MIN_RUN" ]; then
            RESPAWN_FAILS=$(( RESPAWN_FAILS + 1 ))
        else
            RESPAWN_FAILS=0
        fi

        if [ "$CUR" = "$LAST" ] && [ -x "$GAMES_ROOT/$LAST/_handler.sh" ]; then
            if [ "$RESPAWN_FAILS" -ge "$RESPAWN_MAX" ]; then
                # Once, not every second: the whole point is to stop the noise.
                if [ "$RESPAWN_HALTED" != "1" ]; then
                    log "'$LAST' handler exited within ${RESPAWN_MIN_RUN}s, ${RESPAWN_FAILS}x in a row -- NOT respawning."
                    log "Check the binary exists and is executable, and that $GAMES_ROOT/$LAST is present."
                    log "Switching cores clears this."
                    RESPAWN_HALTED=1
                fi
            else
                log "Respawning handler for '$LAST'"
                "$GAMES_ROOT/$LAST/_handler.sh" &
                CHILD=$!
                SPAWN_TIME=$(date +%s)
            fi
        fi
    fi

    sleep 1
done
