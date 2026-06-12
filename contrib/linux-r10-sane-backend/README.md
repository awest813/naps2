# Canon imageFORMULA R10 on Linux: SANE backend effort

This directory contains the work-in-progress effort to get the Canon imageFORMULA R10
working on Linux (and therefore in NAPS2, which uses SANE on Linux).

## Why this is promising

Canon provides no Linux driver or SDK for the R10 (it is officially driven only by the
onboard CaptureOnTouch Lite app on Windows/macOS). However, the R10 is made by Canon
Electronics, and SANE's `canon_dr` backend already supports its close relatives:

- **P-208 / P-215 / P-208II / P-215II** — the R10's direct predecessors, which use the
  exact same design (onboard CaptureOnTouch Lite on a USB mass-storage partition plus a
  vendor-specific USB scanning interface). Fully supported.
- **R40** — the R10's same-generation bigger sibling, supported in `canon_dr` since v66
  with status "confirmed" (USB id `0x1083 0x1679`).

The `canon_dr` backend chooses model-specific behavior from the product string the
device reports via INQUIRY, and attaches to any USB id listed in `canon_dr.conf` — so
the R10 hypothesis can be tested on a stock distro without compiling anything.

## Contents

- `r10-probe.sh` — run this first on the machine with the R10 plugged in. It:
  1. finds the device and reports its USB product id (needed for the upstream patch),
  2. dumps its USB interfaces (and tells you if the much-simpler `ipp-usb` route is
     available, i.e. an interface with class 7 / subclass 1 / protocol 4),
  3. tests whether the stock `canon_dr` backend attaches to it, using a temporary
     SANE config — no system files are modified.
- `canon_dr-r10.patch` — patch against [sane-project/backends](https://gitlab.com/sane-project/backends)
  master adding an R10 model block to `canon_dr` (cloned from the confirmed R40 block,
  same hardware generation). Compiles cleanly; the image-geometry settings (interlacing,
  duplex offset) are a starting hypothesis to refine against real scans.

## Test procedure

### Step 1: probe (no compiling)

```bash
./r10-probe.sh           # detect + attach test
./r10-probe.sh --scan    # also try a real scan (load a sheet first)
```

Possible outcomes:

| Probe result | Meaning | Next step |
|---|---|---|
| IPP-over-USB interface found | `ipp-usb` can bridge it | `sudo apt install ipp-usb`; NAPS2's ESCL driver finds it automatically |
| `canon_dr` attaches, scan looks right | Protocol matches, defaults are fine | Make the config permanent (below); report success upstream |
| `canon_dr` attaches, scan garbled/striped | Protocol matches, model quirks needed | Build the patched backend (below) |
| `canon_dr` doesn't attach | Different protocol | Capture a debug log + USB trace; real reverse-engineering needed |

If you get a USB permission error, either re-run with `sudo` or add a udev rule:

```bash
echo 'ATTRS{idVendor}=="1083", MODE="0666"' | sudo tee /etc/udev/rules.d/65-canon-r10.rules
sudo udevadm control --reload && sudo udevadm trigger
```

### Step 2: make the config permanent

If the probe attaches, add the device to the system config (replace `XXXX` with the
product id the probe printed):

```bash
printf '\n# imageFORMULA R10\noption duplex-offset 320\nusb 0x1083 0xXXXX\n' | \
    sudo tee -a /etc/sane.d/canon_dr.conf
```

`scanimage -L` — and NAPS2 — will then see the scanner.

### Step 3: build the patched backend (if images need the R10 model quirks)

```bash
sudo apt install git autoconf automake libtool autoconf-archive autopoint gettext pkg-config libusb-1.0-0-dev
git clone --depth 1 https://gitlab.com/sane-project/backends.git
cd backends
git apply /path/to/canon_dr-r10.patch
./autogen.sh && BACKENDS="canon_dr" ./configure --prefix="$HOME/sane-r10" && make && make install
# Test with the freshly built backend (system otherwise untouched):
SANE_CONFIG_DIR="$HOME/sane-r10/etc/sane.d" LD_LIBRARY_PATH="$HOME/sane-r10/lib" \
    "$HOME/sane-r10/bin/scanimage" -L
```

Remember to uncomment/fill in the R10 usb line in `$HOME/sane-r10/etc/sane.d/canon_dr.conf`.

If scans are still wrong, the knobs to iterate on are in the R10 block of
`backend/canon_dr.c` (`gray_interlace`, `color_interlace`, `duplex_interlace`) and the
`duplex-offset` config value; `SANE_DEBUG_CANON_DR=35` logs every command exchanged.
The P-215 block is the alternative template if the R40 settings don't fit.

### Step 4: report upstream

Whatever the outcome, please file it at
https://gitlab.com/sane-project/backends/-/issues with:

- the USB product id (`lsusb`) and full descriptor (`sudo lsusb -v -d 1083:`),
- the `SANE_DEBUG_CANON_DR=35 scanimage -L` log,
- if scanning worked: sample scans and which settings were used.

That lets the R10 be added to `canon_dr.conf.in` and `doc/descriptions/canon_dr.desc`
properly so every Linux user gets it out of the box.

## NAPS2 integration

None needed: once `scanimage -L` shows the scanner, NAPS2's SANE driver lists and scans
from it automatically. (And if the device instead turns out to support IPP-over-USB,
NAPS2's ESCL driver now discovers ipp-usb devices on localhost directly.)
