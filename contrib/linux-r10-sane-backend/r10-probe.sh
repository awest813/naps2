#!/usr/bin/env bash
# Probe a Canon imageFORMULA R10 (or other Canon Electronics USB scanner) on Linux
# and test whether the SANE canon_dr backend can talk to it - without modifying
# any system files or recompiling anything.
#
# Usage:
#   ./r10-probe.sh           # detect device, report interfaces, test canon_dr attach
#   ./r10-probe.sh --scan    # additionally attempt a real test scan (load paper first)
#
# See README.md in this directory for background and next steps.

set -u

CANON_ELECTRONICS_VID="1083"
DO_SCAN=0
[ "${1:-}" = "--scan" ] && DO_SCAN=1

say() { printf '\n==> %s\n' "$*"; }

# --- Step 1: find the device ---------------------------------------------------
say "Looking for Canon Electronics (VID 0x$CANON_ELECTRONICS_VID) USB devices"
if ! command -v lsusb >/dev/null; then
    echo "lsusb not found; install usbutils (sudo apt install usbutils)"; exit 1
fi
DEVICE_LINE=$(lsusb -d "$CANON_ELECTRONICS_VID:" 2>/dev/null | head -1)
if [ -z "$DEVICE_LINE" ]; then
    echo "No Canon Electronics device found. Full lsusb output:"
    lsusb
    echo
    echo "If the scanner is plugged in and powered (slide the feed cover open),"
    echo "it may enumerate under a different vendor id - look for it above and"
    echo "re-run the canon_dr test manually with that vid/pid."
    exit 1
fi
echo "Found: $DEVICE_LINE"
PID=$(echo "$DEVICE_LINE" | sed -n 's/.*ID [0-9a-f]\{4\}:\([0-9a-f]\{4\}\).*/\1/p')
BUS=$(echo "$DEVICE_LINE" | awk '{print $2}')
DEV=$(echo "$DEVICE_LINE" | awk '{print $4}' | tr -d ':')
echo "Product ID: 0x$PID  (please report this - it's needed for the upstream patch)"

# --- Step 2: inspect interfaces ------------------------------------------------
say "USB interfaces (what protocols does the device expose?)"
LSUSB_V=$(lsusb -v -s "$BUS:$DEV" 2>/dev/null || sudo lsusb -v -s "$BUS:$DEV" 2>/dev/null)
echo "$LSUSB_V" | grep -E "bInterfaceClass|bInterfaceSubClass|bInterfaceProtocol" | sed 's/^ *//'

if echo "$LSUSB_V" | grep -qE "bInterfaceClass *7" && \
   echo "$LSUSB_V" | grep -qE "bInterfaceProtocol *4"; then
    echo
    echo "*** Device exposes IPP-over-USB (class 7 protocol 4)!"
    echo "*** Install ipp-usb (sudo apt install ipp-usb) and NAPS2 will find it"
    echo "*** through its ESCL driver - no SANE backend work needed."
fi
if echo "$LSUSB_V" | grep -qE "bInterfaceClass *255"; then
    echo
    echo "Device exposes a vendor-specific interface (class 255) - this is the"
    echo "interface the canon_dr backend uses on the P-208/P-215/R40 family."
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
    echo "usb 0x$CANON_ELECTRONICS_VID 0x$PID"
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
    echo "(Permission errors? Re-run with sudo, or add a udev rule - see README.md.)"
fi
