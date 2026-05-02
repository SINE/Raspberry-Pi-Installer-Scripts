#!/bin/bash
set -e

# Unload
sudo dtoverlay -r drm-minipitft114
sudo modprobe -r fb_st7789v
sudo modprobe -r fbtft

# Compile
sudo make

# Capture hash of freshly built module before installation
LOCAL_HASH=$(sha256sum fb_st7789v.ko | awk '{print $1}')

# Install into kernel module tree
sudo make install

# Verify the installed module matches what was built
INSTALLED_KO=$(find /lib/modules/"$(uname -r)" -name 'fb_st7789v.ko' | head -1)
if [ -z "$INSTALLED_KO" ]; then
    echo "ERROR: Cannot locate installed fb_st7789v.ko" >&2
    exit 1
fi
INSTALLED_HASH=$(sha256sum "$INSTALLED_KO" | awk '{print $1}')
if [ "$LOCAL_HASH" != "$INSTALLED_HASH" ]; then
    echo "ERROR: Module integrity check failed" >&2
    echo "  Built:     $LOCAL_HASH" >&2
    echo "  Installed: $INSTALLED_HASH  ($INSTALLED_KO)" >&2
    exit 1
fi
echo "Integrity OK: $INSTALLED_KO"

# Load again
sudo modprobe fbtft
sudo modprobe fb_st7789v
sudo dtoverlay drm-minipitft114