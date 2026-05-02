#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cleanup_pitft_st7789v_bonnet_console.sh
#
# Removes every file in this repository that is completely redundant when
# running:
#   adafruit-pitft.py --display=st7789v_bonnet_240x240 \
#                     --rotation=0 \
#                     --install-type=console
#
# FILES KEPT (required for the above invocation):
#   adafruit-pitft.py
#   overlays/tftbonnet13-overlay.dts        (overlay_src for this display)
#   mipi/adafruit_st7789_drm.txt            (MIPI firmware, command_bin path)
#   st7789_module/{Makefile,fb_st7789v.c,   (fallback kernel-module build when
#                  fbtft.h,reload.sh}        mipi-dbi-spi.dtbo is absent)
#   templates/config_text_base.txt          (loaded by update_configtxt())
#   templates/con2fbmap-helper.sh           (installed by install_console())
#   templates/con2fbmap.service             (installed by install_console())
#
# RATIONALE FOR EACH DELETION GROUP:
#
# [OVERLAY_OTHER] Device-tree source files for displays other than
#   st7789v_bonnet_240x240.  The script only compiles the file listed in
#   overlay_src for the chosen display; all others are unreachable.
#   (pitft22/28c/28r/35r overlays have no overlay_src in the config at all.)
#   touch-ft6236.dts and touch-stmpe.dts are referenced only in
#   old_scripts/adafruit-pitft-mipi.py, never in adafruit-pitft.py.
#
# [MIPI_OTHER] MIPI firmware command files for ILI9341 and HX8357 displays.
#   compile_mipi_fw() copies mipi/<command_bin>.txt where command_bin is
#   "adafruit_st7789_drm" for this display; the other two files are unused.
#
# [TPL_UDEV] udev rule templates that are only written via update_udev().
#   update_udev() is called only when the chosen display config contains a
#   "touchscreen" key.  st7789v_bonnet_240x240 has no touchscreen, so
#   update_udev() is never called and all five udev templates are dead code.
#
# [TPL_FBCP] fbcp.service is only written by install_fbcp_service(), which
#   is called exclusively from install_mirror().  install_type=console never
#   reaches install_mirror(); the template is unreachable.
#
# [OTHER_SCRIPTS] All other top-level installer scripts are independent
#   programmes for different hardware and are not imported or executed by
#   adafruit-pitft.py.  raspi-spi-reassign.py is intentionally kept.
#
# [CONVERTED] Shell-script ports of various Python installers; none is
#   sourced or invoked by adafruit-pitft.py.
#
# [OLD_SCRIPTS] Legacy adafruit-pitft-mipi.py predates the current script
#   and is not referenced anywhere.
#
# [I2S_MODULE] The i2s_mic_module kernel driver is for the I2S microphone
#   product, entirely unrelated to the PiTFT display flow.
#
# [OCCI] Historical Perl configuration helper, not referenced by any current
#   script.
#
# [PACKAGES_ARCHIVE] packages/lgpio.zip is used only by libgpiod.py, which
#   is itself unrelated to adafruit-pitft.py.  The entire archive is
#   redundant; it is deleted directly (no partial extraction needed).
#
# [README] Repository documentation; not loaded or executed by the script.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "=== PiTFT st7789v_bonnet_240x240 console-install cleanup ==="
echo "Working directory: $REPO_ROOT"
echo ""

# ---------------------------------------------------------------------------
# [OVERLAY_OTHER] DTS overlays for every display except tftbonnet13
# ---------------------------------------------------------------------------
echo "[OVERLAY_OTHER] Removing unused device-tree overlay sources..."
rm -f overlays/pitft22-overlay.dts
rm -f overlays/pitft24v2-tsc2007-overlay.dts
rm -f overlays/pitft28-capacitive-overlay.dts
rm -f overlays/pitft28-resistive-overlay.dts
rm -f overlays/pitft35-resistive-overlay.dts
rm -f overlays/minipitft13-overlay.dts
rm -f overlays/minipitft114-overlay.dts
rm -f overlays/st7789v_240x320-overlay.dts
rm -f overlays/touch-ft6236.dts
rm -f overlays/touch-stmpe.dts

# ---------------------------------------------------------------------------
# [MIPI_OTHER] MIPI firmware sources for ILI9341 and HX8357 displays
# ---------------------------------------------------------------------------
echo "[MIPI_OTHER] Removing unused MIPI firmware sources..."
rm -f mipi/adafruit_ili9341_drm.txt
rm -f mipi/adafruit_hx8357_drm.txt

# ---------------------------------------------------------------------------
# [TPL_UDEV] udev rule templates (update_udev() is never called; no touchscreen)
# ---------------------------------------------------------------------------
echo "[TPL_UDEV] Removing unused udev rule templates..."
rm -f templates/95-ftcaptouch.rules
rm -f templates/95-stmpe.rules
rm -f templates/95-touchmouse.rules
rm -f templates/99-tsc2007-touchscreen.rules
rm -f templates/99-spi-tft-drm.rules

# ---------------------------------------------------------------------------
# [TPL_FBCP] fbcp service template (install_mirror() is never reached)
# ---------------------------------------------------------------------------
echo "[TPL_FBCP] Removing unused fbcp service template..."
rm -f templates/fbcp.service

# ---------------------------------------------------------------------------
# [OTHER_SCRIPTS] Independent top-level installer scripts for other hardware
# ---------------------------------------------------------------------------
echo "[OTHER_SCRIPTS] Removing unrelated top-level installer scripts..."
rm -f adafruit_fanservice.py
rm -f ar1100.py
rm -f arcade-bonnet.sh
rm -f i2c.sh
rm -f i2samp.py
rm -f i2smic.py
rm -f install_wm8960.sh
rm -f joy-bonnet.py
rm -f libgpiod.py
rm -f pi-eyes.sh
rm -f pi-touch-cam.py
rm -f pitft-fbcp.py
rm -f raspi-blinka.py
rm -f read-only-fs.sh
rm -f retrogame.py
rm -f retrogame.sh
rm -f rgb-matrix.sh
rm -f rpi_pin_kernel_firmware.py
rm -f rtc.py
rm -f rtc.sh
rm -f spectro.sh
rm -f voice_bonnet.sh

# ---------------------------------------------------------------------------
# [CONVERTED] Shell-script ports of the Python installers
# ---------------------------------------------------------------------------
echo "[CONVERTED] Removing converted shell scripts..."
rm -f converted_shell_scripts/adafruit-pitft.sh
rm -f converted_shell_scripts/adafruit_fanservice.sh
rm -f converted_shell_scripts/i2samp.sh
rm -f converted_shell_scripts/i2smic.sh
rm -f converted_shell_scripts/joy-bonnet.sh
rm -f converted_shell_scripts/libgpiod.sh
rm -f converted_shell_scripts/pi-touch-cam.sh
rm -f converted_shell_scripts/pitft-fbcp.sh
rm -f converted_shell_scripts/rpi-pin-kernel-firmware.sh

# ---------------------------------------------------------------------------
# [OLD_SCRIPTS] Legacy scripts
# ---------------------------------------------------------------------------
echo "[OLD_SCRIPTS] Removing legacy scripts..."
rm -f old_scripts/adafruit-pitft-mipi.py

# ---------------------------------------------------------------------------
# [I2S_MODULE] I2S microphone kernel module (unrelated hardware)
# ---------------------------------------------------------------------------
echo "[I2S_MODULE] Removing i2s_mic_module..."
rm -f i2s_mic_module/dkms.conf
rm -f i2s_mic_module/Makefile
rm -f i2s_mic_module/README.md
rm -f i2s_mic_module/snd-i2smic-rpi.c
rm -f i2s_mic_module/snd-i2smic-rpi.h

# ---------------------------------------------------------------------------
# [OCCI] Historical Perl configuration helper
# ---------------------------------------------------------------------------
echo "[OCCI] Removing occi..."
rm -f occi

# ---------------------------------------------------------------------------
# [PACKAGES_ARCHIVE] packages/lgpio.zip
# The entire archive is redundant (only used by libgpiod.py).
# zip -d cannot delete the last entry from an archive, and since the whole
# archive is unused, we delete the file directly.
# ---------------------------------------------------------------------------
echo "[PACKAGES_ARCHIVE] Removing packages/lgpio.zip..."
rm -f packages/lgpio.zip

# ---------------------------------------------------------------------------
# [README] Repository-level documentation
# ---------------------------------------------------------------------------
echo "[README] Removing README.md..."
rm -f README.md

echo ""
echo "Cleanup complete."
echo ""
echo "Remaining files (required for the invocation):"
find . \
  -not -path './.git/*' \
  -not -path './.github/*' \
  -not -name '.gitignore' \
  -not -name "$(basename "$0")" \
  -type f \
  | sort
