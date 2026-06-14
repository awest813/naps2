#!/usr/bin/env bash
# Probe a Canon imageFORMULA R10 (or related Canon document scanner) on Linux and
# work out which Linux scanning route, if any, applies - without modifying any
# system files or recompiling anything.
#
# Usage:
#   ./r10-probe.sh           # detect device, report interfaces, test canon_dr attach
#   ./r10-probe.sh --scan    # additionally attempt a real test scan (load paper first)
#
# See README.md in this directory for background and next steps.

set -u

# Canon uses two USB vendor ids: 0x1083 (Canon Electronics, the imageFORMULA/DR
# division - this is where the R40/R30/P-215 family lives) and 0x04a9 (Canon Inc.,
# used by CanoScan/PIXMA). We look under both so the device is found either way.
CANON_VIDS="1083 04a9"
DO_SCAN=0
[ "${1:-}" = "--scan" ] && DO_SCAN=1

say() { printf '\n==> %s\n' "$*"; }

# --- Step 1: find the device ---------------------------------------------------
say "Looking for Canon USB scanners (vendor 0x1083 Canon Electronics / 0x04a9 Canon Inc.)"
if ! command -v lsusb >/dev/null; then
    echo "lsusb not found; install usbutils (sudo apt install usbutils)"; exit 1
fi
DEVICE_LINE=""
for vid in $CANON_VIDS; do
    line=$(lsusb -d "$vid:" 2>/dev/null | grep -iE "scan|imageformula| R[0-9]|CANON R|DR-|P-2[01]" | head -1)
    [ -z "$line" ] && line=$(lsusb -d "$vid:" 2>/dev/null | head -1)
    if [ -n "$line" ]; then DEVICE_LINE="$line"; break; fi
done
if [ -z "$DEVICE_LINE" ]; then
    echo "No Canon device found. Full lsusb output:"
    lsusb
    echo
    echo "If the scanner is plugged in and powered (slide the feed cover open to"
    echo "power it on), but is not listed above, the cable/port may be the issue."
    echo "If it IS listed above under some other vendor id, re-run the canon_dr test"
    echo "manually with that vid/pid (see README.md)."
    exit 1
fi
echo "Found: $DEVICE_LINE"
VID=$(echo "$DEVICE_LINE" | sed -n 's/.*ID \([0-9a-f]\{4\}\):[0-9a-f]\{4\}.*/\1/p')
PID=$(echo "$DEVICE_LINE" | sed -n 's/.*ID [0-9a-f]\{4\}:\([0-9a-f]\{4\}\).*/\1/p')
BUS=$(echo "$DEVICE_LINE" | awk '{print $2}')
DEV=$(echo "$DEVICE_LINE" | awk '{print $4}' | tr -d ':')
echo "USB id: 0x$VID:0x$PID  (please report this - it's the key fact the patch needs)"

# --- Step 2: inspect interfaces ------------------------------------------------
say "USB interfaces (what does the device actually expose?)"
LSUSB_V=$(lsusb -v -s "$BUS:$DEV" 2>/dev/null)
if ! echo "$LSUSB_V" | grep -q bInterfaceClass; then
    LSUSB_V=$(sudo lsusb -v -s "$BUS:$DEV" 2>/dev/null)
fi
echo "$LSUSB_V" | grep -E "bInterfaceClass|bInterfaceSubClass|bInterfaceProtocol|iProduct " | sed 's/^ *//'

HAS_IPPUSB=0; HAS_MASSSTORAGE=0; HAS_VENDOR=0; HAS_SCANNER_IMGCLASS=0
echo "$LSUSB_V" | grep -qE "bInterfaceClass +7 " && \
   echo "$LSUSB_V" | grep -qE "bInterfaceProtocol +4 " && HAS_IPPUSB=1
echo "$LSUSB_V" | grep -qE "bInterfaceClass +8 " && HAS_MASSSTORAGE=1
echo "$LSUSB_V" | grep -qE "bInterfaceClass +255 " && HAS_VENDOR=1
echo "$LSUSB_V" | grep -qE "bInterfaceClass +6 " && HAS_SCANNER_IMGCLASS=1

if [ "$HAS_IPPUSB" = 1 ]; then
    say "ROUTE: IPP-over-USB (class 7 / protocol 4) detected"
    echo "This is the easiest path. Install ipp-usb:"
    echo "    sudo apt install ipp-usb && sudo systemctl enable --now ipp-usb"
    echo "Then NAPS2's ESCL driver finds the scanner automatically (no SANE work)."
fi
if [ "$HAS_VENDOR" = 1 ]; then
    echo
    echo "Vendor-specific interface (class 255) present - consistent with the"
    echo "canon_dr SCSI-over-USB scanning interface used by the P-215/R40 family."
fi
if [ "$HAS_MASSSTORAGE" = 1 ] && [ "$HAS_VENDOR" = 0 ] && [ "$HAS_IPPUSB" = 0 ]; then
    say "WARNING: device presents ONLY a USB Mass Storage interface (class 8)"
    echo "This is 'Auto Start' / CaptureOnTouch-Lite mode: the scanner is showing"
    echo "only its onboard installer partition, NOT a scanning interface. The whole"
    echo "P-215/P-208/R-series family does this, and canon_dr CANNOT scan in this"
    echo "mode. You must switch the device into scanner mode first:"
    echo "  - Look for an 'Auto Start' switch on the scanner and set it to OFF, or"
    echo "  - On Windows/Mac, open CaptureOnTouch and turn off 'Auto Start' /"
    echo "    'CaptureOnTouch Lite' (the setting is stored in the device, so it"
    echo "    persists when you move it back to Linux),"
    echo "  - then replug and re-run this script. The USB product id will change"
    echo "    when the mode changes (e.g. P-208 reports 0x164c in scanner mode vs"
    echo "    0x164e in auto-start mode) - report BOTH ids if you can."
fi
if [ "$HAS_SCANNER_IMGCLASS" = 1 ]; then
    echo
    echo "Still-image capture interface (class 6 / PTP) present - the device may"
    echo "speak PTP/MTP rather than the canon_dr protocol."
fi

# --- Step 3: test the canon_dr protocol with the stock distro SANE --------------
say "Testing canon_dr attach via a temporary SANE config (no system changes)"
if ! command -v scanimage >/dev/null; then
    echo "scanimage not found; install sane-utils (sudo apt install sane-utils)"; exit 1
fi
SYS_CONF_DIR=""
for d in /etc/sane.d /usr/local/etc/sane.d; do
    [ -f "$d/canon_dr.conf" ] && SYS_CONF_DIR=$d && break
done
if [ -z "$SYS_CONF_DIR" ]; then
    echo "canon_dr.conf not found; install libsane (sudo apt install libsane1 sane-utils)"; exit 1
fi
TMP_CONF=$(mktemp -d)
trap 'rm -rf "$TMP_CONF"' EXIT
cp "$SYS_CONF_DIR/canon_dr.conf" "$TMP_CONF/"
# Restrict SANE to the canon_dr backend and add this device's usb id
echo "canon_dr" > "$TMP_CONF/dll.conf"
mkdir -p "$TMP_CONF/dll.d"
{
    echo ""
    echo "# Canon imageFORMULA R10 (experimental, added by r10-probe.sh)"
    echo "option duplex-offset 320"
    echo "usb 0x$VID 0x$PID"
} >> "$TMP_CONF/canon_dr.conf"

echo "Running: scanimage -L (canon_dr only, with this device's usb id added)"
RESULT=$(SANE_CONFIG_DIR="$TMP_CONF" SANE_DEBUG_CANON_DR="${SANE_DEBUG_CANON_DR:-5}" scanimage -L 2>"$TMP_CONF/debug.log")
echo "$RESULT"
echo
if echo "$RESULT" | grep -q "canon_dr"; then
    echo "*** SUCCESS: the canon_dr backend attached to the device!"
    echo "*** The scanner speaks the Canon DR protocol. Next steps in README.md:"
    echo "*** make the config change permanent and (for correct image output)"
    echo "*** build the patched backend with the R10 model quirks."
    if [ "$DO_SCAN" = 1 ]; then
        DEVNAME=$(SANE_CONFIG_DIR="$TMP_CONF" scanimage -f '%d' 2>/dev/null | head -1)
        say "Attempting test scan from $DEVNAME (paper loaded?)"
        SANE_CONFIG_DIR="$TMP_CONF" scanimage -d "$DEVNAME" --format=png -o /tmp/r10-test.png \
            && echo "Wrote /tmp/r10-test.png - check whether the image looks correct."
    fi
else
    echo "canon_dr did not attach. Last lines of the backend debug log:"
    tail -25 "$TMP_CONF/debug.log"
    echo
    cp "$TMP_CONF/debug.log" ./r10-canon_dr-debug.log
    echo "Full log saved to ./r10-canon_dr-debug.log - please report it."
    echo "For maximum detail, re-run as: SANE_DEBUG_CANON_DR=35 $0"
    if [ "$HAS_MASSSTORAGE" = 1 ] && [ "$HAS_VENDOR" = 0 ]; then
        echo
        echo "NOTE: this device is in mass-storage / Auto Start mode (see the warning"
        echo "above). canon_dr is EXPECTED to fail until you switch it to scanner mode."
    fi
    if [ "$VID" = "04a9" ]; then
        echo
        echo "NOTE: this device is on the 0x04a9 (Canon Inc.) vendor id. If it uses a"
        echo "Genesys Logic chip (sane-find-scanner may report 'chip=GL...'), the"
        echo "'genesys' backend is the candidate instead of canon_dr. Try:"
        echo "    sane-find-scanner -q ; SANE_DEBUG_GENESYS=5 scanimage -L"
    fi
    echo "(Permission errors? Re-run with sudo, or add a udev rule - see README.md.)"
fi
