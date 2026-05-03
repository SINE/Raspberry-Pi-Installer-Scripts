#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="__SERVICE_NAME__"
APP_SCRIPT="__APP_SCRIPT__"
PYTHON_BIN="__PYTHON_BIN__"
FORCE_FBDEV="__FORCE_FBDEV__"

log() {
    echo "[$SERVICE_NAME] $*"
}

die() {
    echo "[$SERVICE_NAME][ERROR] $*" >&2
    exit 1
}

validate_fbdev_path() {
    local fbdev="$1"
    [[ "$fbdev" =~ ^/dev/fb[0-9]+$ ]] || return 1
    [[ -c "$fbdev" ]] || return 1
    return 0
}

is_probable_tft_fbdev() {
    local fbdev="$1"
    local fb_name fb_path name vsize

    validate_fbdev_path "$fbdev" || return 1
    fb_name="$(basename "$fbdev")"
    fb_path="/sys/class/graphics/${fb_name}"
    [[ -d "$fb_path" ]] || return 1

    if compgen -G "$fb_path/device/drm/*-SPI-*" >/dev/null; then
        return 0
    fi

    name="$(cat "$fb_path/name" 2>/dev/null || true)"
    vsize="$(cat "$fb_path/virtual_size" 2>/dev/null || true)"

    if echo "$name" | grep -Eqi 'st7789|minipitft|panel-mipi-dbi-spi|ili9341|hx8357|fbtft'; then
        return 0
    fi

    if [[ "$vsize" == "240,240" ]]; then
        return 0
    fi

    return 1
}

parse_fbnum_from_con2fbmap() {
    local out fbnum
    if ! command -v con2fbmap >/dev/null 2>&1; then
        return 1
    fi

    out="$(con2fbmap 1 2>/dev/null || true)"
    fbnum="$(echo "$out" | sed -nE 's/.*framebuffer[[:space:]]+([0-9]+).*/\1/p' | head -n1)"
    if [[ -n "$fbnum" && -e "/dev/fb${fbnum}" ]] && is_probable_tft_fbdev "/dev/fb${fbnum}"; then
        echo "/dev/fb${fbnum}"
        return 0
    fi

    fbnum="$(echo "$out" | sed -nE 's/.*\bfb([0-9]+)\b.*/\1/p' | head -n1)"
    if [[ -n "$fbnum" && -e "/dev/fb${fbnum}" ]] && is_probable_tft_fbdev "/dev/fb${fbnum}"; then
        echo "/dev/fb${fbnum}"
        return 0
    fi

    return 1
}

sysfs_detect_fbdev() {
    local fb fbdev name vsize
    local -a spi_candidates=()
    local -a named_candidates=()

    shopt -s nullglob
    for fb in /sys/class/graphics/fb*; do
        fbdev="/dev/$(basename "$fb")"
        [[ -e "$fbdev" ]] || continue

        if compgen -G "$fb/device/drm/*-SPI-*" >/dev/null; then
            spi_candidates+=("$fbdev")
            continue
        fi

        name="$(cat "$fb/name" 2>/dev/null || true)"
        vsize="$(cat "$fb/virtual_size" 2>/dev/null || true)"
        if echo "$name" | grep -Eqi 'st7789|minipitft|panel-mipi-dbi-spi|ili9341|hx8357|fbtft'; then
            if [[ "$vsize" == "240,240" ]]; then
                echo "$fbdev"
                return 0
            fi
            named_candidates+=("$fbdev")
        fi
    done
    shopt -u nullglob

    if [[ "${#spi_candidates[@]}" -eq 1 ]]; then
        echo "${spi_candidates[0]}"
        return 0
    fi

    if [[ "${#named_candidates[@]}" -eq 1 ]]; then
        echo "${named_candidates[0]}"
        return 0
    fi

    return 1
}

if [[ ! -f "$APP_SCRIPT" ]]; then
    die "App script not found: $APP_SCRIPT"
fi

fbdev=""
if [[ -n "$FORCE_FBDEV" ]]; then
    validate_fbdev_path "$FORCE_FBDEV" || die "Configured FORCE_FBDEV is invalid: $FORCE_FBDEV"
    fbdev="$FORCE_FBDEV"
elif fbdev="$(parse_fbnum_from_con2fbmap)"; then
    :
elif fbdev="$(sysfs_detect_fbdev)"; then
    :
else
    die "Unable to safely determine framebuffer device. Set --force-fbdev during install if needed."
fi

log "Using framebuffer: $fbdev"
export SDL_FBDEV="$fbdev"
export SDL_AUDIODRIVER="dummy"

exec "$PYTHON_BIN" "$APP_SCRIPT"
