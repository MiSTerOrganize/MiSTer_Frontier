#!/bin/bash
#
# MiSTer Frontier — One-time install
#
# Run this from MiSTer's Scripts menu after the first 'update_all' that
# pulls in MiSTer Frontier files. Performs the only steps update_all
# can't do on its own:
#
#   1. chmod +x on the master daemon
#   2. Strip any obsolete per-core daemon registrations from earlier
#      MiSTer Frontier installs (pico8_daemon.sh, openbor_*_daemon.sh,
#      music_player_daemon.sh)
#   3. Register Master_Daemon in /media/fat/linux/user-startup.sh so it
#      auto-starts at every boot
#   4. Start Master_Daemon now so the user doesn't have to reboot
#
# Idempotent — re-running it is a no-op.

MASTER="/media/fat/MiSTer_Frontier/Master_Daemon.sh"
STARTUP="/media/fat/linux/user-startup.sh"
STARTUP_UNDERSCORE="/media/fat/linux/_user-startup.sh"

echo "=== MiSTer Frontier -- One-time setup ==="
echo

# Sanity check
if [ ! -f "$MASTER" ]; then
    echo "ERROR: $MASTER not found."
    echo
    echo "Run 'update_all' first to download MiSTer Frontier files,"
    echo "then run this script again."
    exit 1
fi

# 1) Set executable bit on Master_Daemon, hybrid-core ARM binaries, and
# per-core _handler.sh launchers. raw.githubusercontent.com serves files
# with mode 0644; on FAT/exFAT (most MiSTers) the missing exec bit is
# silently tolerated — the kernel ignores mode bits on those filesystems.
# BUT if /media/fat/games/ is hosted on an NFS share (where Unix
# permissions ARE enforced), the ARM binaries can't be executed and the
# hybrid cores black-screen on launch. Discovery-driven so future hybrid
# cores added to /media/fat/games/<CoreName>/ get handled automatically.
# Reported by community user 2026-05-23 (NFS-hosted /games/).
chmod 0755 "$MASTER"
echo "  OK chmod 0755 $MASTER"

for handler in /media/fat/games/*/_handler.sh; do
    [ -f "$handler" ] || continue
    core_dir=$(dirname "$handler")
    core_name=$(basename "$core_dir")
    # Handler script
    chmod 0755 "$handler" 2>/dev/null
    echo "  OK chmod 0755 $handler"
    # ARM binaries: every executable file directly in games/<CoreName>/
    # that isn't a .sh script. Picks up PICO-8 + OpenBOR_4086 +
    # OpenBOR_7533 today and any future hybrid-core binary automatically.
    for f in "$core_dir"/*; do
        [ -f "$f" ] || continue
        case "$f" in
            *.sh|*.p8|*.png|*.cfg|*.txt|*.md) continue ;;
        esac
        # Heuristic: file is a candidate ARM binary if it has no extension
        # OR matches the core name pattern. Either way, chmod 0755 — no
        # harm on FAT/exFAT; required on NFS.
        bin=$(basename "$f")
        case "$bin" in
            "$core_name"|"$core_name"_*)
                chmod 0755 "$f" 2>/dev/null
                echo "  OK chmod 0755 $f"
                ;;
        esac
    done
done

# 2a) Resolve which startup file MiSTer Main actually reads at boot.
# MiSTer's convention: linux/user-startup.sh (no underscore) is executed.
# linux/_user-startup.sh (with underscore) is a deactivated/template state.
# If the user has ONLY the underscore variant, our install previously
# became a silent no-op — meaning Master_Daemon wouldn't auto-start on
# reboot. Fix: detect the case, prefer the active file, create it if
# neither exists. Reported by community user 2026-05-22.
if [ -f "$STARTUP" ]; then
    ACTIVE_STARTUP="$STARTUP"
    echo "  OK Using existing $STARTUP"
elif [ -f "$STARTUP_UNDERSCORE" ]; then
    # User has only the underscore variant — promote it by writing to
    # the no-underscore name (which is what MiSTer Main actually reads).
    # Preserve their existing content by copying first.
    cp -f "$STARTUP_UNDERSCORE" "$STARTUP"
    chmod +x "$STARTUP"
    ACTIVE_STARTUP="$STARTUP"
    echo "  OK Promoted $STARTUP_UNDERSCORE -> $STARTUP (MiSTer Main reads"
    echo "    the no-underscore version at boot; the underscore variant"
    echo "    is a deactivated template that wouldn't run)"
else
    # Neither variant exists — create the active one fresh.
    cat > "$STARTUP" <<'EOF'
#!/bin/sh
# MiSTer user startup script — runs at every boot.
EOF
    chmod +x "$STARTUP"
    ACTIVE_STARTUP="$STARTUP"
    echo "  OK Created $STARTUP (didn't exist before)"
fi

# 2b) Strip obsolete per-core daemon registrations from the active file
sed -i '/pico8_daemon\.sh/d'              "$ACTIVE_STARTUP"
sed -i '/openbor_4086_daemon\.sh/d'       "$ACTIVE_STARTUP"
sed -i '/openbor_7533_daemon\.sh/d'       "$ACTIVE_STARTUP"
sed -i '/music_player_daemon\.sh/d'       "$ACTIVE_STARTUP"
sed -i '/PICO-8 auto-launch daemon/d'     "$ACTIVE_STARTUP"
sed -i '/OpenBOR auto-launch daemon/d'    "$ACTIVE_STARTUP"
echo "  OK Cleared obsolete per-core daemon registrations"

# 3) Register Master_Daemon (idempotent)
if ! grep -qF "Master_Daemon.sh" "$ACTIVE_STARTUP"; then
    echo ""                                                    >> "$ACTIVE_STARTUP"
    echo "# MiSTer Frontier -- hybrid core master daemon"       >> "$ACTIVE_STARTUP"
    echo "bash $MASTER &"                                       >> "$ACTIVE_STARTUP"
    echo "  OK Registered Master_Daemon in $ACTIVE_STARTUP"
else
    echo "  OK Master_Daemon already registered in $ACTIVE_STARTUP"
fi

# 4) Kill any pre-existing per-core daemons (now obsolete)
killall pico8_daemon.sh        2>/dev/null
killall openbor_4086_daemon.sh 2>/dev/null
killall openbor_7533_daemon.sh 2>/dev/null
killall music_player_daemon.sh 2>/dev/null

# 4b) Migrate from pre-unification OpenBOR layout (May 2026):
# Both OpenBOR builds now share games/OpenBOR/ folder. Move user PAKs
# from the legacy per-build folders, then remove the old folder skeleton.
if [ -d /media/fat/games/OpenBOR_4086 ] || [ -d /media/fat/games/OpenBOR_7533 ]; then
    mkdir -p /media/fat/games/OpenBOR/Paks
    for old in /media/fat/games/OpenBOR_4086 /media/fat/games/OpenBOR_7533; do
        [ -d "$old/Paks" ] || continue
        # Move PAK files (deduplicated by name — won't clobber existing target)
        find "$old/Paks" -maxdepth 1 -type f -name '*.pak' -print0 \
            | while IFS= read -r -d '' f; do
                base=$(basename "$f")
                if [ ! -e "/media/fat/games/OpenBOR/Paks/$base" ]; then
                    mv -f "$f" "/media/fat/games/OpenBOR/Paks/" 2>/dev/null
                fi
            done
        # Move any sub-folders of Paks/ (custom organization)
        find "$old/Paks" -maxdepth 1 -mindepth 1 -type d -exec mv -f {} /media/fat/games/OpenBOR/Paks/ \; 2>/dev/null
    done
    # Remove obsolete binaries + handlers (handled by update_all manifest now)
    rm -f /media/fat/games/OpenBOR_4086/OpenBOR /media/fat/games/OpenBOR_4086/_handler.sh 2>/dev/null
    rm -f /media/fat/games/OpenBOR_7533/OpenBOR /media/fat/games/OpenBOR_7533/_handler.sh 2>/dev/null
    rm -rf /media/fat/games/OpenBOR_4086/Logs /media/fat/games/OpenBOR_7533/Logs 2>/dev/null
    rmdir /media/fat/games/OpenBOR_4086/Paks /media/fat/games/OpenBOR_7533/Paks 2>/dev/null
    rmdir /media/fat/games/OpenBOR_4086 /media/fat/games/OpenBOR_7533 2>/dev/null
    echo "  OK Migrated OpenBOR_4086/7533 layouts -> unified games/OpenBOR/"
fi

# 4b) Migrate from v2.2-and-earlier log layouts:
#   - games/OpenBOR/Logs/        — engine wrote here via "./Logs/..." relative paths before v2.3
#   - logs/OpenBOR/              — handler used unified LOGDIR=/media/fat/logs/OpenBOR briefly
# v2.3 fix: engine + handler both write per-build to logs/OpenBOR_4086/ or logs/OpenBOR_7533/.
# Clean up the stale dirs so audits + tail-F workflows aren't confused by ghost content.
rm -rf /media/fat/games/OpenBOR/Logs 2>/dev/null
rm -rf /media/fat/logs/OpenBOR 2>/dev/null

# 4c) Migrate from pre-unification OpenBOR docs layout: per-build README
# folders are replaced by a single docs/OpenBOR/README.md.
if [ -d /media/fat/docs/OpenBOR_4086 ] || [ -d /media/fat/docs/OpenBOR_7533 ]; then
    rm -rf /media/fat/docs/OpenBOR_4086 /media/fat/docs/OpenBOR_7533 2>/dev/null
    echo "  OK Removed legacy per-build docs/OpenBOR_*/ folders (single docs/OpenBOR/ now)"
fi

# 5) Kill any prior Master_Daemon instance, then start fresh
ps | grep "Master_Daemon.sh" | grep -v grep | awk '{print $1}' | xargs -r kill 2>/dev/null
sleep 1

nohup bash "$MASTER" </dev/null >/dev/null 2>&1 &
sleep 1

if ps | grep "Master_Daemon.sh" | grep -v grep > /dev/null; then
    echo "  OK Master_Daemon started"
else
    echo "  ! Master_Daemon failed to start -- check $MASTER for errors"
fi

echo
echo "Setup complete. MiSTer Frontier hybrid cores will now auto-launch"
echo "when you load them from MiSTer's cores menu. No reboot needed."
echo
echo "Running 'update_all' from now on will keep everything current --"
echo "you only need this script once."
echo
