#!/bin/bash
#
# MiSTer Frontier — Uninstall
#
# Removes all MiSTer Frontier components from this MiSTer. Run from the
# Scripts menu OR via SSH:
#   bash /media/fat/Scripts/Uninstall_MiSTer_Frontier.sh
#
# Default (safe) mode: removes cores + system files but PRESERVES your
# user content (saves, savestates, configs, high scores, PAKs, carts).
# Re-installing later restores everything to a working state.
#
# Purge mode: also removes user content. Asked interactively; non-
# interactive callers default to safe mode.
#
# IMPORTANT: this script does NOT unsubscribe you from the Frontier
# database in update_all. If you don't also edit downloader.ini to
# remove the [mister-frontier] section, your next `update_all` run
# will re-download all the Frontier files. Instructions printed at end.

set -u  # exit on uninitialized vars; do NOT use set -e (we tolerate
        # missing files — most rm/sed targets are optional cleanup)

STARTUP="/media/fat/linux/user-startup.sh"
STARTUP_UNDERSCORE="/media/fat/linux/_user-startup.sh"
MASTER="/media/fat/MiSTer_Frontier/Master_Daemon.sh"

echo "=== MiSTer Frontier — Uninstall ==="
echo

# Detect what's currently installed so we can report accurately
INSTALLED_PARTS=0
[ -f "$MASTER" ]                         && INSTALLED_PARTS=$((INSTALLED_PARTS+1))
[ -f "/media/fat/games/PICO-8/PICO-8" ]  && INSTALLED_PARTS=$((INSTALLED_PARTS+1))
[ -f "/media/fat/games/OpenBOR/OpenBOR_4086" ] && INSTALLED_PARTS=$((INSTALLED_PARTS+1))
[ -f "/media/fat/games/OpenBOR/OpenBOR_7533" ] && INSTALLED_PARTS=$((INSTALLED_PARTS+1))
ls /media/fat/_Other/PICO-8_*.rbf       >/dev/null 2>&1 && INSTALLED_PARTS=$((INSTALLED_PARTS+1))
ls /media/fat/_Other/OpenBOR_*_*.rbf    >/dev/null 2>&1 && INSTALLED_PARTS=$((INSTALLED_PARTS+1))

if [ "$INSTALLED_PARTS" -eq 0 ]; then
    echo "MiSTer Frontier doesn't appear to be installed (no Master_Daemon,"
    echo "no ARM binaries, no RBFs found in expected locations)."
    echo
    echo "Nothing to do. Exiting."
    exit 0
fi

# Ask about purge mode (interactive only — non-interactive defaults to safe)
PURGE_USER_CONTENT="no"
if [ -t 0 ]; then  # stdin is a terminal
    echo "Two uninstall modes:"
    echo
    echo "  [S] Safe (recommended) — removes cores + system files only."
    echo "      KEEPS your saves, savestates, configs, high scores, PAKs, carts."
    echo "      Reinstall later → everything still works."
    echo
    echo "  [P] Purge — also removes user content (saves, savestates, configs,"
    echo "      PAKs at games/OpenBOR/Paks/, carts at games/PICO-8/Carts/)."
    echo "      Use this only if you want zero trace of the cores."
    echo
    echo "  [Q] Quit without changes."
    echo
    read -n 1 -r -p "Choice [S/P/Q]: " choice
    echo
    echo
    case "$choice" in
        [Ss]) PURGE_USER_CONTENT="no" ;;
        [Pp])
            PURGE_USER_CONTENT="yes"
            echo "Purge mode selected. Confirm again:"
            read -n 1 -r -p "This will delete saves + PAKs + carts. Type Y to confirm: " confirm
            echo
            if [ "$confirm" != "Y" ] && [ "$confirm" != "y" ]; then
                echo "Cancelled."
                exit 0
            fi
            ;;
        [Qq]|*)
            echo "Cancelled."
            exit 0
            ;;
    esac
else
    echo "(Non-interactive mode — defaulting to SAFE uninstall, preserving user content)"
fi

echo

# 1) Kill the running Master_Daemon + any hybrid-core child binaries.
# SIGTERM first, sleep, then SIGKILL — same pattern as Master_Daemon's
# own child-kill, ensures clean exit without leaving zombies writing to
# DDR3.
echo "1/8  Killing Master_Daemon + child processes..."
pkill -TERM -f "Master_Daemon.sh"              2>/dev/null
killall -TERM PICO-8 OpenBOR_4086 OpenBOR_7533 2>/dev/null
sleep 1
pkill -KILL -f "Master_Daemon.sh"              2>/dev/null
killall -KILL PICO-8 OpenBOR_4086 OpenBOR_7533 2>/dev/null
sleep 1
if ps | grep -E "Master_Daemon\.sh|OpenBOR_(4086|7533)|/PICO-8" | grep -v grep > /dev/null; then
    echo "     ⚠ Some processes still running — they'll exit on next reboot"
else
    echo "     ✓ all MiSTer Frontier processes stopped"
fi

# 2) Remove our entry from BOTH startup files (whichever variant exists)
echo "2/8  Removing Master_Daemon entry from user-startup files..."
for f in "$STARTUP" "$STARTUP_UNDERSCORE"; do
    [ -f "$f" ] || continue
    # Use a sed range to remove the comment line + the bash command line
    # together. Match either the comment or the daemon path.
    sed -i '/# MiSTer Frontier — hybrid core master daemon/d' "$f"
    sed -i '/MiSTer_Frontier\/Master_Daemon\.sh/d'            "$f"
    # Also strip any pre-Master_Daemon-era per-core daemon registrations
    sed -i '/pico8_daemon\.sh/d'              "$f"
    sed -i '/openbor_4086_daemon\.sh/d'       "$f"
    sed -i '/openbor_7533_daemon\.sh/d'       "$f"
    sed -i '/music_player_daemon\.sh/d'       "$f"
    sed -i '/PICO-8 auto-launch daemon/d'     "$f"
    sed -i '/OpenBOR auto-launch daemon/d'    "$f"
    echo "     ✓ Cleaned $f"
done

# 3) Remove Master_Daemon + Install script + this script
echo "3/8  Removing system files (Master_Daemon, Install script)..."
rm -rf /media/fat/MiSTer_Frontier         2>/dev/null
rm -f  /media/fat/Scripts/Install_MiSTer_Frontier.sh 2>/dev/null
echo "     ✓ Removed /media/fat/MiSTer_Frontier/"
echo "     ✓ Removed Install_MiSTer_Frontier.sh"

# 4) Remove the three RBFs
echo "4/8  Removing FPGA cores (RBFs)..."
rm -f /media/fat/_Other/PICO-8_*.rbf       2>/dev/null
rm -f /media/fat/_Other/OpenBOR_4086_*.rbf 2>/dev/null
rm -f /media/fat/_Other/OpenBOR_7533_*.rbf 2>/dev/null
echo "     ✓ Removed PICO-8 + OpenBOR_4086 + OpenBOR_7533 RBFs from _Other/"

# 5) Remove ARM binaries + handlers (leaves your Paks/Carts subdirs intact in safe mode)
echo "5/8  Removing ARM binaries + handlers..."
rm -f /media/fat/games/PICO-8/PICO-8       2>/dev/null
rm -f /media/fat/games/PICO-8/bios.p8      2>/dev/null
rm -f /media/fat/games/PICO-8/_handler.sh  2>/dev/null
rm -f /media/fat/games/OpenBOR/OpenBOR_4086 2>/dev/null
rm -f /media/fat/games/OpenBOR/OpenBOR_7533 2>/dev/null
rm -f /media/fat/games/OpenBOR/_handler.sh  2>/dev/null
echo "     ✓ Removed PICO-8 + OpenBOR binaries + BIOS + handlers"

# 6) Remove docs
echo "6/8  Removing docs..."
rm -rf /media/fat/docs/PICO-8  2>/dev/null
rm -rf /media/fat/docs/OpenBOR 2>/dev/null
echo "     ✓ Removed /media/fat/docs/PICO-8/ and /media/fat/docs/OpenBOR/"

# 7) Remove cart-path config files (transient; written by MiSTer Main + our binaries)
echo "7/8  Removing transient cart-path files..."
rm -f /media/fat/config/PICO-8.s0  2>/dev/null
rm -f /media/fat/config/OpenBOR.s0 2>/dev/null
rm -f /tmp/openbor_reset_marker    2>/dev/null
rm -f /tmp/openbor_hotswap_marker  2>/dev/null
rm -f /tmp/pico8_reset_marker      2>/dev/null
rm -f /tmp/pico8_hotswap_marker    2>/dev/null
echo "     ✓ Removed .s0 cart-path files + /tmp markers"

# 8) Purge mode — also remove user content
if [ "$PURGE_USER_CONTENT" = "yes" ]; then
    echo "8/8  PURGING user content (saves, savestates, configs, PAKs, carts)..."
    rm -rf /media/fat/saves/PICO-8       2>/dev/null
    rm -rf /media/fat/saves/OpenBOR_4086 2>/dev/null
    rm -rf /media/fat/saves/OpenBOR_7533 2>/dev/null
    rm -rf /media/fat/savestates/PICO-8       2>/dev/null
    rm -rf /media/fat/savestates/OpenBOR_4086 2>/dev/null
    rm -rf /media/fat/savestates/OpenBOR_7533 2>/dev/null
    rm -rf /media/fat/logs/PICO-8       2>/dev/null
    rm -rf /media/fat/logs/OpenBOR_4086 2>/dev/null
    rm -rf /media/fat/logs/OpenBOR_7533 2>/dev/null
    rm -f  /media/fat/config/PICO-8.cfg       2>/dev/null
    rm -f  /media/fat/config/OpenBOR_4086.cfg 2>/dev/null
    rm -f  /media/fat/config/OpenBOR_7533.cfg 2>/dev/null
    rm -f  /media/fat/config/zepto8.cfg       2>/dev/null
    rm -f  /media/fat/config/default.cfg      2>/dev/null  # OpenBOR global fallback
    rm -rf /media/fat/games/PICO-8/Carts      2>/dev/null
    rm -rf /media/fat/games/OpenBOR/Paks      2>/dev/null
    rm -f  /media/fat/games/PICO-8/*.p8d.txt  2>/dev/null  # PICO-8 cart save data
    rm -f  /media/fat/config/*.hi             2>/dev/null  # OpenBOR per-PAK high scores
    # Empty games dirs?
    rmdir /media/fat/games/PICO-8  2>/dev/null
    rmdir /media/fat/games/OpenBOR 2>/dev/null
    echo "     ✓ Purged saves, savestates, logs, OSD configs, BIOS configs, PAKs, carts, high scores"
else
    echo "8/8  Skipping user content (safe mode)"
    echo "     User content preserved in:"
    [ -d /media/fat/saves/PICO-8 ]       && echo "       /media/fat/saves/PICO-8/"
    [ -d /media/fat/saves/OpenBOR_4086 ] && echo "       /media/fat/saves/OpenBOR_4086/"
    [ -d /media/fat/saves/OpenBOR_7533 ] && echo "       /media/fat/saves/OpenBOR_7533/"
    [ -d /media/fat/savestates/PICO-8 ]       && echo "       /media/fat/savestates/PICO-8/"
    [ -d /media/fat/savestates/OpenBOR_4086 ] && echo "       /media/fat/savestates/OpenBOR_4086/"
    [ -d /media/fat/savestates/OpenBOR_7533 ] && echo "       /media/fat/savestates/OpenBOR_7533/"
    [ -d /media/fat/games/PICO-8/Carts ]  && echo "       /media/fat/games/PICO-8/Carts/"
    [ -d /media/fat/games/OpenBOR/Paks ]  && echo "       /media/fat/games/OpenBOR/Paks/"
fi

# Self-delete this uninstall script
rm -f /media/fat/Scripts/Uninstall_MiSTer_Frontier.sh 2>/dev/null

# Final verification + next-steps
echo
echo "=== Uninstall complete ==="
echo
echo "Verification:"
if [ ! -d "/media/fat/MiSTer_Frontier" ]; then
    echo "  ✓ /media/fat/MiSTer_Frontier/ removed"
else
    echo "  ⚠ /media/fat/MiSTer_Frontier/ still exists — manual cleanup needed"
fi
if ! ps | grep -E "Master_Daemon\.sh|OpenBOR_(4086|7533)|/PICO-8" | grep -v grep > /dev/null; then
    echo "  ✓ No MiSTer Frontier processes running"
fi
if ! ls /media/fat/_Other/PICO-8_*.rbf /media/fat/_Other/OpenBOR_*_*.rbf >/dev/null 2>&1; then
    echo "  ✓ All RBFs removed from _Other/"
fi
echo

# Tell the user about the downloader.ini step they need to take manually
echo "⚠ IMPORTANT — one manual step left:"
echo
echo "   update_all will RE-DOWNLOAD these files on your next run unless"
echo "   you also unsubscribe from the MiSTer Frontier database. Edit:"
echo
echo "     /media/fat/downloader.ini"
echo
echo "   and remove (or comment out with #) the section that looks like:"
echo
echo "     [mister-frontier]"
echo "     db_url = https://raw.githubusercontent.com/MiSTerOrganize/MiSTer_Frontier/db/db.json.zip"
echo
echo "   After that, update_all will skip MiSTer Frontier entirely."
echo
echo "Reboot is NOT required — the daemon is killed and won't auto-start"
echo "again (we removed the user-startup.sh entry). But a reboot is fine"
echo "if you want a fully fresh state."
echo
