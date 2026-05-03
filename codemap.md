# Code Map: Raspberry-Pi-Installer-Scripts

This document is an orientation guide for humans and AI agents working in this repository.

Scope note:
- This map covers all current files and folders except .git, .github, and __pycache__.
- The current working focus is the st7789v_bonnet_240x240 path in console mode, plus the custom UI service flow.

## 1) System Setup Flow (Start Here)

Primary recommended entrypoint:
- install_st7789v_bonnet_console_full.sh

What it automates:
1. Installs base host dependencies (git, python3-venv, python3-pip).
2. Creates/repairs per-user venv at ~/env (residue-safe handling).
3. Installs Python requirements for adafruit-pitft.py into that venv.
4. Detects whether PiTFT is already installed.
5. If installed, opens wizard to choose reinstall or uninstall.
6. Runs adafruit-pitft.py for st7789v_bonnet_240x240 console mode.
7. Prompts whether to install/reinstall optional custom UI service (default no).

Install/reinstall behavior:
- New install path: direct install.
- Reinstall path: uninstall first, then install.
- Uninstall path: removes PiTFT setup and can optionally remove UI service.

Legacy/manual entrypoint (still valid):
- adafruit-pitft.py

Primary entrypoint for custom UI service deployment:
- install_pitft_custom_ui_service.sh

High-level flow:
1. Validate root execution and parse install/uninstall/reinstall flags.
2. Resolve template sources from templates/.
3. Install runtime dependencies (python3, pygame, pillow) unless --no-deps.
4. Detect a safe TFT framebuffer device:
   - Explicit override from --force-fbdev
   - con2fbmap mapping parse
   - sysfs heuristics under /sys/class/graphics
5. Install app script to /opt/pitft-custom-ui/app.py.
6. Install launcher script to /usr/local/bin/<service>-launcher.
7. Install systemd unit to /etc/systemd/system/<service>.service.
8. daemon-reload, enable, and optionally start service.

Uninstall flow:
1. Stop and disable service.
2. Remove installed unit and launcher.
3. Remove deployed app unless --keep-app was provided.

Reinstall flow:
1. Uninstall sequence.
2. Fresh install sequence.

## 2) Runtime Flow (When Service Starts)

Installed systemd unit:
- templates/pitft_custom_ui.service (template source)
- /etc/systemd/system/pitft-custom-ui.service (installed instance)

Runtime chain:
1. systemd starts launcher.
2. Launcher detects FBDEV conservatively (same strategy as installer).
3. Launcher exports SDL_FBDEV and SDL_AUDIODRIVER=dummy.
4. Launcher execs Python UI app.
5. UI app initializes pygame and tries SDL video backends in fallback order:
   - environment-selected backend first
   - auto backend selection
   - kmsdrm
   - fbcon
   - directfb
6. App renders:
   - image/animated image area
   - ticker bar with scrolling text
7. On service stop, unit runs ExecStopPost to restart con2fbmap service to restore console mapping.

## 3) Display Template Files (Core for Custom UI)

templates/pitft_custom_ui.service
- Template systemd unit for custom UI service.
- Placeholder tokens are replaced by installer.
- Restarts on failure.
- Calls con2fbmap restart on stop to bring console mapping back.

templates/pitft_custom_ui_launcher.sh
- Runtime bootstrap shell script.
- Verifies and detects framebuffer device.
- Exports runtime env for SDL.
- Starts the Python UI script.

templates/pitft_custom_ui_app.py
- Default example UI implementation.
- Uses pygame for display loop and text rendering.
- Uses Pillow to decode image frames (including animated formats) into pygame surfaces.
- Supports environment-driven content:
  - PITFT_IMAGE for image file path
  - PITFT_TICKER for ticker text

templates/con2fbmap.service
- Console mapping helper service used by console-mode installer path.

templates/con2fbmap-helper.sh
- Script that finds correct framebuffer for configured display type and maps console using con2fbmap.

templates/config_text_base.txt
- Base config fragment used by adafruit-pitft.py when writing boot config overlay sections.

## 4) Existing PiTFT Installer Stack (Adafruit Script Path)

install_st7789v_bonnet_console_full.sh
- Central orchestration script for the full workflow users previously ran manually.
- Intended first script to run for this repository's target setup.
- Adds install-state wizard and optional custom UI service deployment prompt.

adafruit-pitft.py
- Main hardware installer and configurator.
- Handles display selection, rotation, overlay compilation, MIPI firmware generation, and install mode selection.
- For console mode, installs and enables con2fbmap helper/service.
- For mirror mode, can use rpi-fbcp path.

cleanup_pitft_st7789v_bonnet_console.sh
- Repository cleanup utility focused on st7789v_bonnet_240x240 + console installation scenario.
- Removes files considered unnecessary for that specific scenario.

raspi-spi-reassign.py
- SPI reassign helper script retained in repository (separate from custom UI service flow).

## 5) Display/Kernel Plumbing Assets

overlays/tftbonnet13-overlay.dts
- Device Tree Source for TFT bonnet display overlay used in st7789v_bonnet_240x240 path.

mipi/adafruit_st7789_drm.txt
- MIPI command description used for firmware generation in supported install paths.

mipi/mipi-dbi-cmd
- Tool invoked to compile panel command text into firmware binary.

st7789_module/Makefile
st7789_module/fb_st7789v.c
st7789_module/fbtft.h
st7789_module/reload.sh
- Fallback kernel module build assets for ST7789V path where required by system state.

## 6) Mirror Mode Helper

rpi-fbcp/CMakeLists.txt
rpi-fbcp/main.c
rpi-fbcp/main.c.orig
rpi-fbcp/README.md
- rpi-fbcp source used when mirror mode is selected by adafruit-pitft.py.
- Not required for the custom UI service path in console-first mode.

## 7) Dependency and Security Context

requirements.txt
- Declares Python dependencies for security scanning and tooling checks.
- Includes Pillow>=12.2.0 policy.

AGENTS.md
- Verified project-specific engineering notes for AI/coding agents.
- Includes Pillow migration/breaking-change research and rationale for current version floor.

.gitignore
- Standard ignore rules for local/derived files.

## 8) Where To Look For Common Tasks

Task: Service does not start
- Check launcher and app logs first:
  - journalctl -u pitft-custom-ui.service -b -n 200
- Inspect templates:
  - templates/pitft_custom_ui_launcher.sh
  - templates/pitft_custom_ui_app.py
  - templates/pitft_custom_ui.service

Task: Wrong framebuffer selected
- Review detection logic in:
  - install_pitft_custom_ui_service.sh
  - templates/pitft_custom_ui_launcher.sh
- Override with installer flag:
  - --force-fbdev /dev/fbN

Task: Update UI visuals
- Edit only:
  - templates/pitft_custom_ui_app.py
- Reinstall to redeploy:
  - sudo ./install_pitft_custom_ui_service.sh --reinstall --start-now

Task: Reconfigure system display overlays
- Inspect:
  - install_st7789v_bonnet_console_full.sh
  - adafruit-pitft.py
  - overlays/tftbonnet13-overlay.dts
  - mipi/adafruit_st7789_drm.txt

Task: Keep console mode reliable
- Inspect:
  - templates/con2fbmap.service
  - templates/con2fbmap-helper.sh

## 9) Practical Notes For New Programmers And AI Agents

- Prefer changing template files over editing deployed files in /opt or /etc directly.
- The installer is idempotent by design. Re-running it is the intended update mechanism.
- Keep framebuffer detection conservative. If uncertain, fail with clear guidance rather than guessing.
- For UI development, treat templates/pitft_custom_ui_app.py as the source of truth and redeploy via installer.
- For dependency policy changes, read AGENTS.md and requirements.txt together.

## 10) External References (Syntax, APIs, Methods)

Pygame:
- https://www.pygame.org/docs/
- https://www.pygame.org/docs/ref/display.html
- https://www.pygame.org/docs/ref/font.html

SDL2 video backend selection:
- https://wiki.libsdl.org/SDL2/FAQUsingSDL
- https://wiki.libsdl.org/SDL2/SDL_HINT_VIDEODRIVER

Pillow image handling:
- https://pillow.readthedocs.io/
- https://pillow.readthedocs.io/en/stable/reference/Image.html
- https://pillow.readthedocs.io/en/stable/reference/ImageSequence.html

systemd unit/service behavior:
- https://www.freedesktop.org/software/systemd/man/systemd.service.html
- https://www.freedesktop.org/software/systemd/man/systemctl.html

Linux framebuffer and DRM/KMS background:
- https://www.kernel.org/doc/html/latest/gpu/drm-kms.html
- https://www.kernel.org/doc/html/latest/fb/framebuffer.html
