#!/usr/bin/env bash
# Build a patched sane-backends (canon_dr + imageFORMULA R10 support) into an
# isolated prefix ($HOME/sane-r10) without touching the system SANE install.
#
# Usage:
#   ./build-patched-backend.sh
#
# Afterwards, test with:
#   ~/sane-r10/bin/r10-scanimage -L
#
# See README.md in this directory for the full procedure.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PATCH="$SCRIPT_DIR/canon_dr-r10.patch"
SRC_DIR="${SANE_R10_SRC:-$HOME/sane-backends-r10}"
PREFIX="${SANE_R10_PREFIX:-$HOME/sane-r10}"
CANON_ELECTRONICS_VID="1083"

say() { printf '\n==> %s\n' "$*"; }

say "Checking build dependencies"
MISSING=""
for tool in git autoconf automake libtoolize autopoint gettext pkg-config gcc make; do
    command -v "$tool" >/dev/null || MISSING="$MISSING $tool"
done
pkg-config --exists libusb-1.0 2>/dev/null || MISSING="$MISSING libusb-1.0-0-dev"
if [ -n "$MISSING" ]; then
    echo "Missing:$MISSING"
    echo "Install with: sudo apt install git autoconf automake libtool autoconf-archive autopoint gettext pkg-config libusb-1.0-0-dev"
    exit 1
fi

say "Getting sane-backends source in $SRC_DIR"
if [ ! -d "$SRC_DIR/.git" ]; then
    git clone --depth 1 https://gitlab.com/sane-project/backends.git "$SRC_DIR"
fi
cd "$SRC_DIR"

say "Applying R10 patch"
if git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
    echo "Patch applied."
elif git apply --check --reverse "$PATCH" 2>/dev/null; then
    echo "Patch already applied."
else
    echo "Patch does not apply cleanly to $SRC_DIR (upstream may have changed)."
    echo "Resolve manually, or delete $SRC_DIR and re-run."
    exit 1
fi

say "Building (canon_dr backend only) into $PREFIX - log: $SRC_DIR/build.log"
{
    [ -x configure ] || ./autogen.sh
    BACKENDS="canon_dr" ./configure --prefix="$PREFIX"
    make -j"$(nproc)"
    make install
} >"$SRC_DIR/build.log" 2>&1 || {
    tail -25 "$SRC_DIR/build.log"
    echo "Build failed - see $SRC_DIR/build.log"
    exit 1
}
echo "Installed."

# Restrict the isolated install to the canon_dr backend (the default dll.conf
# lists every backend, most of which aren't built here)
echo "canon_dr" > "$PREFIX/etc/sane.d/dll.conf"

CONF="$PREFIX/etc/sane.d/canon_dr.conf"
say "Configuring $CONF"
PID=$(lsusb -d "$CANON_ELECTRONICS_VID:" 2>/dev/null | head -1 | sed -n 's/.*ID [0-9a-f]\{4\}:\([0-9a-f]\{4\}\).*/\1/p' || true)
if [ -n "${PID:-}" ] && ! grep -q "^usb 0x$CANON_ELECTRONICS_VID 0x$PID" "$CONF"; then
    {
        echo ""
        echo "# imageFORMULA R10 (added by build-patched-backend.sh)"
        echo "option duplex-offset 320"
        echo "usb 0x$CANON_ELECTRONICS_VID 0x$PID"
    } >> "$CONF"
    echo "Added usb 0x$CANON_ELECTRONICS_VID 0x$PID to canon_dr.conf"
elif [ -z "${PID:-}" ]; then
    echo "No Canon Electronics (0x$CANON_ELECTRONICS_VID) device currently connected."
    echo "Plug in the scanner and add its id to $CONF:"
    echo "    option duplex-offset 320"
    echo "    usb 0x$CANON_ELECTRONICS_VID 0x<product-id-from-lsusb>"
fi

say "Creating wrapper $PREFIX/bin/r10-scanimage"
cat > "$PREFIX/bin/r10-scanimage" <<EOF
#!/bin/sh
SANE_CONFIG_DIR="$PREFIX/etc/sane.d" LD_LIBRARY_PATH="$PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" exec "$PREFIX/bin/scanimage" "\$@"
EOF
chmod +x "$PREFIX/bin/r10-scanimage"

say "Done. Test with:"
echo "  $PREFIX/bin/r10-scanimage -L"
echo "  $PREFIX/bin/r10-scanimage --format=png -o /tmp/r10-test.png   # paper loaded"
echo "Debug log: SANE_DEBUG_CANON_DR=35 $PREFIX/bin/r10-scanimage -L"
