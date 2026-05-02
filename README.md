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

## Per-core documentation

Each core has its own guide with controls, supported games, and credits.
After running `update_all`, browse `/media/fat/docs/` on your MiSTer, or
the [`docs/`](docs/) folder in this repository.

## Source code

The full source for every Frontier core lives in [`source/`](source/) —
the FPGA design (Verilog/SystemVerilog), the ARM emulator code, build
scripts, and patches. This is the canonical home for every core. Source
isn't downloaded to your MiSTer; it's here on GitHub for reading,
auditing, and contribution.

## License

GPL-3.0 — see [`LICENSE`](LICENSE).

## Support

<p align="center">
  <a href="https://www.patreon.com/join/MiSTer_Organize">
    <img src="https://github.com/MiSTerOrganize/MiSTer_Frontier/raw/main/assets/patreon_banner.png" alt="Support MiSTer Organize on Patreon" width="500">
  </a>
</p>
