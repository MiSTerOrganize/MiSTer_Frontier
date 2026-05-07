# MiSTer Frontier

MiSTer Frontier is a project that brings software-based gaming platforms —
fantasy consoles, game engines, and retro graphics systems — to MiSTer
FPGA as hybrid FPGA+ARM cores with native video and audio output.

These are platforms that never existed as dedicated hardware. They live
as software — emulators, virtual machines, and engines that run thousands
of games created by passionate communities. MiSTer Frontier gives them a
home on real FPGA hardware with the same native output quality that
MiSTer is known for.

Every core uses a hybrid architecture: the ARM CPU runs the emulator or
engine while the FPGA handles video and audio output directly — no Linux
framebuffer, no ALSA, no software scaler. The FPGA drives video and
audio straight to hardware, just like a real chip would. Full CRT
support with analog output, zero-lag, and the crisp retro experience
MiSTer users expect. Frontier cores run alongside every other MiSTer
core — installing this database doesn't change anything about your
existing setup.

## Installing on your MiSTer

1. Add this entry to `downloader.ini` on your MiSTer's SD card:

   ```ini
   [MiSTerOrganize/MiSTer_Frontier]
   db_url = https://raw.githubusercontent.com/MiSTerOrganize/MiSTer_Frontier/db/db.json.zip
   ```

2. Run `update_all` from MiSTer's Scripts menu. All Frontier files appear
   automatically — the FPGA cores under `_Other/`, the emulator programs
   under `games/`, and per-core guides under `docs/`.

3. Run `Scripts/Install_MiSTer_Frontier.sh` once from MiSTer's Scripts
   menu. This sets up the background helper that auto-launches each
   core's emulator when you load it. You only need to run this once.
   Running it a second time is harmless.

4. Load any Frontier core from MiSTer's main menu. The matching emulator
   starts automatically — nothing else to do.

When new Frontier cores are released, just run `update_all` again. New
cores show up and work the same way, no reinstall needed.

## How it works

When you load a Frontier core from MiSTer's menu, the FPGA loads the
core file — same as any other MiSTer core. At the same time, a small
background helper notices which core just loaded and starts the matching
emulator program on the ARM CPU. The emulator sends video and audio
directly to the FPGA, which outputs them to your TV or monitor just
like a real chip would.

You don't see any of this — from your side, you just load a core and
it runs.

## Choosing what to install (filters)

You don't have to install everything. Add a `filter = ...` line to the
`[MiSTerOrganize/MiSTer_Frontier]` section of your `downloader.ini` to
choose specific cores. Three tags are available:

| Tag | What it includes |
|---|---|
| `pico-8` | PICO-8 fantasy console (RBF + emulator + BIOS + handler + docs) |
| `openbor-4086` | OpenBOR engine Build 4086 (legacy PAK collections) |
| `openbor-7533` | OpenBOR engine 4.0 Build 7533 (modern PAK collections) |

**Examples:**

```ini
[MiSTerOrganize/MiSTer_Frontier]
db_url = https://raw.githubusercontent.com/MiSTerOrganize/MiSTer_Frontier/db/db.json.zip
filter = pico-8                            # PICO-8 only
# filter = openbor-4086                    # OpenBOR 4086 only
# filter = openbor-7533                    # OpenBOR 7533 only
# filter = openbor-4086 openbor-7533       # both OpenBOR engines, no PICO-8
# filter = pico-8 openbor-7533             # PICO-8 + 7533, skip the legacy 4086
# (omit the filter line)                   # everything (default)
```

**Negative tags** (prefix with `!`) exclude content. They're useful when
you want most things but not one specific core:

```ini
filter = !openbor-4086                     # everything except the 4086 build
```

Note that negative filters work by exclusion, so they remove any file
tagged with the negated tag — including shared OpenBOR infrastructure
(handler + README) that's tagged with both `openbor-4086` and
`openbor-7533`. If you want a working partial install (e.g., 7533 only,
no 4086), prefer a positive filter (`filter = openbor-7533`) over a
negative one. Use negative filters only for clean exclusions where you
don't need the rest of that core family.

The bootstrap files (Master_Daemon, Install script) install with every
filter selection automatically — you can't accidentally exclude them.

**Inspecting the database:** the live manifest (every file, hash, size,
tags) is browsable via theypsilon's DB Inspector tool:
[DB Inspector for MiSTer_Frontier](https://theypsilon.github.io/DB-Inspector_MiSTer/?database-url=https%3A%2F%2Fraw.githubusercontent.com%2FMiSTerOrganize%2FMiSTer_Frontier%2Fdb%2Fdb.json.zip).
Useful for verifying what a given filter would actually install.

## Per-core documentation

Each core has its own guide with controls, supported games, and credits.
After running `update_all`, browse `/media/fat/docs/` on your MiSTer.
The guides live in their respective per-core repos (see "Source code"
below) and are mirrored to your MiSTer by `update_all`.

## Source code

MiSTer Frontier is structured as a combiner repo that pulls files from
per-core repositories:

| Repo | Contents |
|---|---|
| [MiSTer_PICO-8](https://github.com/MiSTerOrganize/MiSTer_PICO-8) | PICO-8 source, FPGA, ARM emulator, RBF, BIOS, docs |
| [MiSTer_OpenBOR_4086](https://github.com/MiSTerOrganize/MiSTer_OpenBOR_4086) | OpenBOR Build 4086 source, FPGA, ARM build, RBF, docs |
| [MiSTer_OpenBOR_7533](https://github.com/MiSTerOrganize/MiSTer_OpenBOR_7533) | OpenBOR Build 7533 source, FPGA, ARM build, RBF, docs |
| MiSTer_Frontier (this repo) | Combiner — `external_files.csv`, Master_Daemon, Install script, DB build workflow |

Source isn't downloaded to your MiSTer; it's on GitHub for reading,
auditing, and contribution. Open issues / PRs against the relevant
per-core repo. Each per-core repo is self-contained — you can clone any
one of them and build the core independently.

## License

GPL-3.0 — see [`LICENSE`](LICENSE).

## Support

<p align="center">
  <a href="https://www.patreon.com/join/MiSTer_Organize">
    <img src="https://github.com/MiSTerOrganize/MiSTer_Frontier/raw/main/assets/patreon_banner.png" alt="Support MiSTer Organize on Patreon" width="500">
  </a>
</p>
