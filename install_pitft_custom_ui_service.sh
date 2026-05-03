#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

SERVICE_NAME="pitft-custom-ui"
APP_DIR="/opt/pitft-custom-ui"
APP_DEST="${APP_DIR}/app.py"
APP_SOURCE="${TEMPLATE_DIR}/pitft_custom_ui_app.py"
RUNNER_TEMPLATE="${TEMPLATE_DIR}/pitft_custom_ui_launcher.sh"
SERVICE_TEMPLATE="${TEMPLATE_DIR}/pitft_custom_ui.service"
RUNNER_PATH="/usr/local/bin/pitft-custom-ui-launcher"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

ENABLE_SERVICE=1
START_NOW=0
INSTALL_DEPS=1
FORCE_FBDEV=""
PYTHON_BIN="/usr/bin/python3"
DO_UNINSTALL=0
DO_REINSTALL=0
REMOVE_APP_ON_UNINSTALL=1

usage() {
    cat <<EOF
Usage: sudo ./${SCRIPT_NAME} [options]

Options:
  --app-source PATH          Path to custom UI Python script to deploy
                             Default: ${APP_SOURCE}
  --service-name NAME        systemd service name (default: ${SERVICE_NAME})
  --app-dir DIR              Install directory for app script (default: ${APP_DIR})
  --python-bin PATH          Python binary for ExecStart (default: ${PYTHON_BIN})
  --force-fbdev /dev/fbN     Override auto-detection with explicit FB device
  --no-enable                Install service without enabling it
  --start-now                Start service after install/reinstall
  --no-deps                  Skip apt dependency installation
  --reinstall                Force clean re-install (remove + install)
  --uninstall                Stop/disable/remove installed service and launcher
  --keep-app                 Keep deployed app script during uninstall
  -h, --help                 Show this help

Notes:
  - Re-running this script updates/re-installs in-place.
  - Service and launcher are installed from template files in templates/.
  - Service runs as root to reliably access VT and framebuffer access.
EOF
}

log() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Run as root (use sudo)."
    fi
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
    if [[ "${#spi_candidates[@]}" -gt 1 ]]; then
        warn "Multiple SPI framebuffer candidates found: ${spi_candidates[*]}"
        return 1
    fi

    if [[ "${#named_candidates[@]}" -eq 1 ]]; then
        echo "${named_candidates[0]}"
        return 0
    fi
    if [[ "${#named_candidates[@]}" -gt 1 ]]; then
        warn "Multiple named framebuffer candidates found: ${named_candidates[*]}"
        return 1
    fi

    return 1
}

detect_fbdev() {
    local fbdev

    if [[ -n "$FORCE_FBDEV" ]]; then
        validate_fbdev_path "$FORCE_FBDEV" || die "--force-fbdev is invalid or does not exist: $FORCE_FBDEV"
        echo "$FORCE_FBDEV"
        return 0
    fi

    if fbdev="$(parse_fbnum_from_con2fbmap)"; then
        echo "$fbdev"
        return 0
    fi
    if fbdev="$(sysfs_detect_fbdev)"; then
        echo "$fbdev"
        return 0
    fi

    return 1
}

install_dependencies() {
    if [[ "$INSTALL_DEPS" -eq 0 ]]; then
        log "Skipping dependency installation (--no-deps)."
        return 0
    fi

    log "Installing dependencies via apt (python3, pygame, pillow)."
    apt-get update
    apt-get install -y --no-install-recommends python3 python3-pygame python3-pil
}

ensure_templates_exist() {
    [[ -f "$RUNNER_TEMPLATE" ]] || die "Missing launcher template: $RUNNER_TEMPLATE"
    [[ -f "$SERVICE_TEMPLATE" ]] || die "Missing service template: $SERVICE_TEMPLATE"
    [[ -f "$APP_SOURCE" ]] || die "Missing app source: $APP_SOURCE"
}

install_app_script() {
    [[ -f "$APP_SOURCE" ]] || die "App source file not found: $APP_SOURCE"
    mkdir -p "$APP_DIR"
    install -m 0755 "$APP_SOURCE" "$APP_DEST"
    log "Installed app script to $APP_DEST"
}

install_runner_script() {
    install -m 0755 "$RUNNER_TEMPLATE" "$RUNNER_PATH"
    sed -i "s|__SERVICE_NAME__|${SERVICE_NAME}|g" "$RUNNER_PATH"
    sed -i "s|__APP_SCRIPT__|${APP_DEST}|g" "$RUNNER_PATH"
    sed -i "s|__PYTHON_BIN__|${PYTHON_BIN}|g" "$RUNNER_PATH"
    sed -i "s|__FORCE_FBDEV__|${FORCE_FBDEV}|g" "$RUNNER_PATH"
}

install_service_unit() {
    install -m 0644 "$SERVICE_TEMPLATE" "$SERVICE_PATH"
    sed -i "s|__SERVICE_NAME__|${SERVICE_NAME}|g" "$SERVICE_PATH"
    sed -i "s|__APP_DIR__|${APP_DIR}|g" "$SERVICE_PATH"
    sed -i "s|__RUNNER_PATH__|${RUNNER_PATH}|g" "$SERVICE_PATH"
}

stop_existing_service_if_present() {
    if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
        log "Stopping existing service instance (${SERVICE_NAME}.service) if running."
        systemctl stop "${SERVICE_NAME}.service" || true
    fi
}

install_or_update() {
    local detected_fbdev

    ensure_templates_exist
    install_dependencies

    if ! detected_fbdev="$(detect_fbdev)"; then
        die "Could not detect TFT framebuffer safely. Re-run with --force-fbdev /dev/fbN"
    fi
    log "Framebuffer detection successful: ${detected_fbdev}"

    stop_existing_service_if_present
    install_app_script
    install_runner_script
    install_service_unit

    systemctl daemon-reload

    if [[ "$ENABLE_SERVICE" -eq 1 ]]; then
        systemctl enable "${SERVICE_NAME}.service"
        log "Enabled ${SERVICE_NAME}.service"
    else
        log "Installed but not enabled (--no-enable)."
    fi

    if [[ "$START_NOW" -eq 1 ]]; then
        systemctl restart "${SERVICE_NAME}.service"
        log "Started ${SERVICE_NAME}.service"
    else
        log "Install/update complete. Start with: systemctl start ${SERVICE_NAME}.service"
    fi
}

uninstall() {
    log "Uninstalling ${SERVICE_NAME}.service and launcher"
    systemctl stop "${SERVICE_NAME}.service" || true
    systemctl disable "${SERVICE_NAME}.service" || true
    rm -f "$SERVICE_PATH"
    rm -f "$RUNNER_PATH"

    if [[ "$REMOVE_APP_ON_UNINSTALL" -eq 1 ]]; then
        rm -f "$APP_DEST"
        rmdir "$APP_DIR" 2>/dev/null || true
        log "Removed deployed app script: ${APP_DEST}"
    else
        log "Keeping deployed app script: ${APP_DEST}"
    fi

    systemctl daemon-reload
    log "Uninstall complete"
}

reinstall() {
    log "Performing clean re-install"
    uninstall
    install_or_update
}

main() {
    require_root

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app-source)
                [[ $# -ge 2 ]] || die "--app-source requires a value"
                APP_SOURCE="$2"
                shift 2
                ;;
            --service-name)
                [[ $# -ge 2 ]] || die "--service-name requires a value"
                SERVICE_NAME="$2"
                shift 2
                ;;
            --app-dir)
                [[ $# -ge 2 ]] || die "--app-dir requires a value"
                APP_DIR="$2"
                shift 2
                ;;
            --python-bin)
                [[ $# -ge 2 ]] || die "--python-bin requires a value"
                PYTHON_BIN="$2"
                shift 2
                ;;
            --force-fbdev)
                [[ $# -ge 2 ]] || die "--force-fbdev requires a value"
                FORCE_FBDEV="$2"
                shift 2
                ;;
            --no-enable)
                ENABLE_SERVICE=0
                shift
                ;;
            --start-now)
                START_NOW=1
                shift
                ;;
            --no-deps)
                INSTALL_DEPS=0
                shift
                ;;
            --reinstall)
                DO_REINSTALL=1
                shift
                ;;
            --uninstall)
                DO_UNINSTALL=1
                shift
                ;;
            --keep-app)
                REMOVE_APP_ON_UNINSTALL=0
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    APP_DEST="${APP_DIR}/app.py"
    RUNNER_PATH="/usr/local/bin/${SERVICE_NAME}-launcher"
    SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

    if [[ "$DO_UNINSTALL" -eq 1 ]]; then
        uninstall
        exit 0
    fi
    if [[ "$DO_REINSTALL" -eq 1 ]]; then
        reinstall
        exit 0
    fi

    install_or_update
}

main "$@"
