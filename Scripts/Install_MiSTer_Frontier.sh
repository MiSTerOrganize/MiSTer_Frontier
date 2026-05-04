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

echo "=== MiSTer Frontier — One-time setup ==="
echo

# Sanity check
if [ ! -f "$MASTER" ]; then
    echo "ERROR: $MASTER not found."
    echo
    echo "Run 'update_all' first to download MiSTer Frontier files,"
    echo "then run this script again."
    exit 1
fi

# 1) Make Master_Daemon executable
chmod +x "$MASTER"
echo "  ✓ $MASTER is executable"

# 2) Strip obsolete per-core daemon registrations
if [ -f "$STARTUP" ]; then
    sed -i '/pico8_daemon\.sh/d'         "$STARTUP"
    sed -i '/openbor_4086_daemon\.sh/d'  "$STARTUP"
    sed -i '/openbor_7533_daemon\.sh/d'  "$STARTUP"
    sed -i '/music_player_daemon\.sh/d'  "$STARTUP"
    sed -i '/PICO-8 auto-launch daemon/d' "$STARTUP"
    sed -i '/OpenBOR auto-launch daemon/d' "$STARTUP"
    echo "  ✓ Cleared obsolete per-core daemon registrations"
fi

# 3) Register Master_Daemon (idempotent)
if [ -f "$STARTUP" ] && ! grep -qF "Master_Daemon.sh" "$STARTUP"; then
    echo ""                                                    >> "$STARTUP"
    echo "# MiSTer Frontier — hybrid core master daemon"       >> "$STARTUP"
    echo "bash $MASTER &"                                       >> "$STARTUP"
    echo "  ✓ Registered Master_Daemon in $STARTUP"
else
    echo "  ✓ Master_Daemon already registered in $STARTUP"
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
    echo "  ✓ Migrated OpenBOR_4086/7533 layouts → unified games/OpenBOR/"
fi

# 5) Kill any prior Master_Daemon instance, then start fresh
ps | grep "Master_Daemon.sh" | grep -v grep | awk '{print $1}' | xargs -r kill 2>/dev/null
sleep 1

nohup bash "$MASTER" </dev/null >/dev/null 2>&1 &
sleep 1

if ps | grep "Master_Daemon.sh" | grep -v grep > /dev/null; then
    echo "  ✓ Master_Daemon started"
else
    echo "  ⚠ Master_Daemon failed to start — check $MASTER for errors"
fi

echo
echo "Setup complete. MiSTer Frontier hybrid cores will now auto-launch"
echo "when you load them from MiSTer's cores menu. No reboot needed."
echo
echo "Running 'update_all' from now on will keep everything current —"
echo "you only need this script once."
echo
