#!/bin/bash
#
# MiSTer Frontier — Uninstall
#
# Removes all MiSTer Frontier components from this MiSTer. Run from the
# Scripts menu OR via SSH:
#   bash /media/fat/Scripts/Uninstall_MiSTer_Frontier.sh
#
# DISCOVERY-DRIVEN — enumerates hybrid cores by scanning
# /media/fat/games/*/_handler.sh (same convention Master_Daemon uses).
# New hybrid cores added to the manifest in the future (Beetle VB,
# Tilengine, Game King, etc.) get cleaned up automatically without
# needing to update this script.
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

# ─── Discovery: find every hybrid core installed under this Frontier ───
# A hybrid core is identified by /media/fat/games/<CoreName>/_handler.sh
# (the same convention Master_Daemon uses for auto-discovery). Each
# discovered CoreName becomes a target for per-core cleanup. Beetle VB
# or any future hybrid core added to the public manifest will be picked
# up automatically by this enumeration — no script update needed.
DISCOVERED_CORES=""
for handler in /media/fat/games/*/_handler.sh; do
    [ -f "$handler" ] || continue
    core_dir=$(dirname "$handler")
    core_name=$(basename "$core_dir")
    DISCOVERED_CORES="$DISCOVERED_CORES $core_name"
done
DISCOVERED_CORES=$(echo "$DISCOVERED_CORES" | xargs)  # trim

# Sanity: anything installed?
if [ -z "$DISCOVERED_CORES" ] && [ ! -f "$MASTER" ]; then
    echo "MiSTer Frontier doesn't appear to be installed (no Master_Daemon,"
    echo "no hybrid-core _handler.sh files found under /media/fat/games/)."
    echo
    echo "Nothing to do. Exiting."
    exit 0
fi

echo "Discovered hybrid cores: ${DISCOVERED_CORES:-(none)}"
echo

# ─── Ask about purge mode (interactive only) ───
PURGE_USER_CONTENT="no"
if [ -t 0 ]; then
    echo "Two uninstall modes:"
    echo
    echo "  [S] Safe (recommended) — removes cores + system files only."
    echo "      KEEPS your saves, savestates, configs, high scores, PAKs, carts."
    echo "      Reinstall later → everything still works."
    echo
    echo "  [P] Purge — also removes user content (saves, savestates, configs,"
    echo "      Paks/, Carts/, and equivalent per-core user dirs)."
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

# ─── 1) Kill all hybrid-core ARM binaries + Master_Daemon ───
# Discovery: ARM binary names match _Other/<BinaryName>_<date>.rbf and/or
# the executable files in each core's games dir. The pattern across all
# current hybrid cores: at least one file inside games/<CoreName>/ has
# the same prefix as the RBF (e.g. PICO-8 binary, OpenBOR_4086 binary).
# We kill by name + by working-directory (/proc/$pid/cwd in core_dir).
echo "1/8  Killing Master_Daemon + hybrid-core binaries..."
pkill -TERM -f "Master_Daemon.sh" 2>/dev/null

# Per-core: kill any process whose cwd is inside this core's games dir,
# OR whose binary name matches an executable in that dir.
for core_name in $DISCOVERED_CORES; do
    core_dir="/media/fat/games/$core_name"
    # Collect candidate binary names from this core's games dir
    # (executable files that aren't .sh scripts)
    for f in "$core_dir"/*; do
        [ -f "$f" ] || continue
        [ -x "$f" ] || continue
        case "$f" in *.sh) continue;; esac
        bin=$(basename "$f")
        killall -TERM "$bin" 2>/dev/null
    done
    # Also kill by cwd as a backstop (catches any binary we missed)
    for pid in $(pidof -x 2>/dev/null); do
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
        [ "$cwd" = "$core_dir" ] && kill -TERM "$pid" 2>/dev/null
    done
done
sleep 1

# Force-kill anything still running
pkill -KILL -f "Master_Daemon.sh" 2>/dev/null
for core_name in $DISCOVERED_CORES; do
    core_dir="/media/fat/games/$core_name"
    for f in "$core_dir"/*; do
        [ -f "$f" ] && [ -x "$f" ] || continue
        case "$f" in *.sh) continue;; esac
        killall -KILL "$(basename "$f")" 2>/dev/null
    done
done
sleep 1
echo "     ✓ Killed Master_Daemon + per-core ARM binaries for: $DISCOVERED_CORES"

# ─── 2) Strip Master_Daemon entry from both user-startup variants ───
echo "2/8  Cleaning user-startup files (both .sh and _.sh variants)..."
for f in "$STARTUP" "$STARTUP_UNDERSCORE"; do
    [ -f "$f" ] || continue
    sed -i '/# MiSTer Frontier — hybrid core master daemon/d' "$f"
    sed -i '/MiSTer_Frontier\/Master_Daemon\.sh/d'            "$f"
    # Also strip pre-Master_Daemon-era per-core daemon registrations
    sed -i '/pico8_daemon\.sh/d'              "$f"
    sed -i '/openbor_4086_daemon\.sh/d'       "$f"
    sed -i '/openbor_7533_daemon\.sh/d'       "$f"
    sed -i '/music_player_daemon\.sh/d'       "$f"
    sed -i '/PICO-8 auto-launch daemon/d'     "$f"
    sed -i '/OpenBOR auto-launch daemon/d'    "$f"
    echo "     ✓ Cleaned $f"
done

# ─── 3) Remove MiSTer Frontier bootstrap (Master_Daemon + Install) ───
# These are MiSTer Frontier-specific, not per-core. Hardcoded paths
# because they're the Frontier-owned files. Uninstall self-deletes
# at the end.
echo "3/8  Removing MiSTer Frontier bootstrap (Master_Daemon + Install)..."
rm -rf /media/fat/MiSTer_Frontier                    2>/dev/null
rm -f  /media/fat/Scripts/Install_MiSTer_Frontier.sh 2>/dev/null
echo "     ✓ Removed /media/fat/MiSTer_Frontier/ and Install_MiSTer_Frontier.sh"

# ─── 4) Per-core file removal (discovery-driven) ───
echo "4/8  Removing per-core files for each discovered core..."
for core_name in $DISCOVERED_CORES; do
    core_dir="/media/fat/games/$core_name"

    # Remove the games/<CoreName>/ dir contents — every file directly in
    # it is ours (handlers, ARM binaries, BIOS). User content lives in
    # subdirs (games/<CoreName>/Carts/, /Paks/, etc.) which we preserve
    # in safe mode and handle separately in purge mode.
    find "$core_dir" -maxdepth 1 -type f -delete 2>/dev/null

    # Remove docs/<CoreName>/ (single core name only — OpenBOR sister
    # cores share one docs/OpenBOR/ that gets removed exactly once via
    # the sister-core dedup below)
    rm -rf "/media/fat/docs/$core_name" 2>/dev/null

    # Remove RBFs in _Other/ matching CoreName_*.rbf
    rm -f "/media/fat/_Other/$core_name"_*.rbf 2>/dev/null
    # Also handle sister-core RBF pattern: <CoreFamily>_<Build>_<Date>.rbf
    # (OpenBOR ships as OpenBOR_4086_*.rbf and OpenBOR_7533_*.rbf — both
    # under games/OpenBOR/ but with build-suffixed RBF names. Match those
    # by scanning game-dir executables and treating their stems as RBF
    # prefixes.)
    for f in "$core_dir"/*; do
        [ -f "$f" ] || continue
        [ -x "$f" ] || continue
        case "$f" in *.sh) continue;; esac
        bin=$(basename "$f")
        rm -f "/media/fat/_Other/$bin"_*.rbf 2>/dev/null
    done

    # Remove the now-empty games/<CoreName>/ dir IF it has no user
    # content (Carts/, Paks/, etc.) — rmdir fails harmlessly if dir
    # is non-empty
    rmdir "$core_dir" 2>/dev/null

    # Per-core .s0 cart-path file (lives in /media/fat/config/)
    # SetName may differ from CoreName for sister-cored engines (e.g.,
    # OpenBOR's setname is "OpenBOR" while CoreName is "OpenBOR"; sister
    # cores share .s0). The simple-case .s0 is named <CoreName>.s0.
    rm -f "/media/fat/config/$core_name.s0" 2>/dev/null

    # Per-core /tmp markers (lowercase corename convention)
    rm -f "/tmp/$(echo "$core_name" | tr A-Z a-z)_reset_marker"   2>/dev/null
    rm -f "/tmp/$(echo "$core_name" | tr A-Z a-z)_hotswap_marker" 2>/dev/null

    echo "     ✓ Cleaned core: $core_name"
done

# ─── 5) Also clean sister-cored engines' shared dirs ───
# OpenBOR is the canonical example: setname "OpenBOR" with sister builds
# OpenBOR_4086 + OpenBOR_7533 sharing games/OpenBOR/. After step 4 each
# build's RBFs + binary were removed but games/OpenBOR/ + docs/OpenBOR/
# may still exist if there are sub-dirs we preserved (Paks/, etc.).
# Handle the shared-setname .s0 here too.
rm -f /media/fat/config/OpenBOR.s0 2>/dev/null
# (Future sister-cored engines: add their shared setname's .s0 here.)
echo "5/8  Cleaned sister-cored shared cart-path files (OpenBOR.s0)"

# ─── 6) Cart-path config files — defensive cleanup ───
# In case the discovery-driven cleanup missed any .s0 from a previously-
# installed-but-now-removed core, sweep the config dir for any .s0
# files whose corresponding games/<X>/ no longer exists.
echo "6/8  Sweeping for orphan .s0 cart-path files..."
for s0 in /media/fat/config/*.s0; do
    [ -f "$s0" ] || continue
    name=$(basename "$s0" .s0)
    # If neither games/<name>/_handler.sh nor games/<name>/<name> exists,
    # this .s0 is an orphan from a removed core
    if [ ! -f "/media/fat/games/$name/_handler.sh" ] && [ ! -f "/media/fat/games/$name/$name" ]; then
        # But ONLY remove if we have specific evidence the core was a
        # Frontier core (don't touch arbitrary OSD-mounted .s0 from
        # other people's cores). Safest: skip orphan removal in safe
        # mode; only remove in purge.
        if [ "$PURGE_USER_CONTENT" = "yes" ]; then
            rm -f "$s0"
            echo "     ✓ Removed orphan $s0 (purge mode)"
        fi
    fi
done

# ─── 7) Purge mode — also remove per-core user content ───
if [ "$PURGE_USER_CONTENT" = "yes" ]; then
    echo "7/8  PURGING per-core user content (saves, savestates, logs, configs, content libs)..."
    for core_name in $DISCOVERED_CORES; do
        # Per-build save/savestate/log dirs: name OR name_<suffix>
        # (sister-cored engines split per-build: saves/OpenBOR_4086/ +
        # saves/OpenBOR_7533/, not saves/OpenBOR/)
        rm -rf /media/fat/saves/"$core_name"      2>/dev/null
        rm -rf /media/fat/saves/"$core_name"_*    2>/dev/null
        rm -rf /media/fat/savestates/"$core_name" 2>/dev/null
        rm -rf /media/fat/savestates/"$core_name"_* 2>/dev/null
        rm -rf /media/fat/logs/"$core_name"       2>/dev/null
        rm -rf /media/fat/logs/"$core_name"_*     2>/dev/null

        # MiSTer OSD config (one per build)
        rm -f  /media/fat/config/"$core_name".cfg     2>/dev/null
        rm -f  /media/fat/config/"$core_name"_*.cfg   2>/dev/null

        # User content libraries inside games/<CoreName>/ (subdirs we
        # preserved in step 4 — Carts/, Paks/, etc.)
        rm -rf "/media/fat/games/$core_name"          2>/dev/null
        echo "     ✓ Purged $core_name"
    done

    # Engine-specific configs (NOT per-build; sister cores share these)
    # PICO-8: zepto8 emulator config
    rm -f /media/fat/config/zepto8.cfg 2>/dev/null
    # OpenBOR: global fallback + per-PAK .cfg, .hi
    rm -f /media/fat/config/default.cfg 2>/dev/null
    # Per-PAK .hi/.cfg files lack a CoreName prefix; pattern-match by
    # known engine. For OpenBOR these are <pak>.cfg and <pak>.hi.
    # We can't safely auto-detect these without ambiguity, so we only
    # remove the engine fallback files. User can hand-remove per-PAK
    # files in /media/fat/config/ if they want.

    echo "     ✓ Also removed engine-shared configs (zepto8.cfg, default.cfg)"
else
    echo "7/8  Skipping user content (safe mode)"
    echo "     User content preserved per discovered core:"
    for core_name in $DISCOVERED_CORES; do
        [ -d "/media/fat/saves/$core_name" ]       && echo "       /media/fat/saves/$core_name/"
        for d in /media/fat/saves/"$core_name"_*; do
            [ -d "$d" ] && echo "       $d/"
        done
        [ -d "/media/fat/savestates/$core_name" ]  && echo "       /media/fat/savestates/$core_name/"
        for d in /media/fat/savestates/"$core_name"_*; do
            [ -d "$d" ] && echo "       $d/"
        done
        [ -d "/media/fat/games/$core_name" ] && \
            find "/media/fat/games/$core_name" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's/^/       /'
    done
fi

# ─── 8) Self-delete this uninstall script ───
echo "8/8  Self-deleting Uninstall_MiSTer_Frontier.sh..."
rm -f /media/fat/Scripts/Uninstall_MiSTer_Frontier.sh 2>/dev/null

# ─── Final verification + next-steps ───
echo
echo "=== Uninstall complete ==="
echo
echo "Verification:"
if [ ! -d "/media/fat/MiSTer_Frontier" ]; then
    echo "  ✓ /media/fat/MiSTer_Frontier/ removed"
else
    echo "  ⚠ /media/fat/MiSTer_Frontier/ still exists — manual cleanup needed"
fi
if ! ps | grep -E "Master_Daemon\.sh" | grep -v grep > /dev/null; then
    echo "  ✓ No Master_Daemon process running"
fi
remaining_cores=""
for handler in /media/fat/games/*/_handler.sh; do
    [ -f "$handler" ] && remaining_cores="$remaining_cores $(basename $(dirname "$handler"))"
done
if [ -z "$remaining_cores" ]; then
    echo "  ✓ No hybrid-core handlers remain"
else
    echo "  ⚠ Some hybrid-core handlers still present:$remaining_cores"
    echo "    (likely user-installed non-Frontier cores; not touched)"
fi
echo

# Manual step: downloader.ini
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
