#!/usr/bin/env bash
set -euo pipefail

# Central installer for st7789v_bonnet_240x240 console mode.
# Handles dependencies, Python venv prep, install/reinstall/uninstall wizard,
# and optional custom UI service deployment.

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PITFT_SCRIPT="${SCRIPT_DIR}/adafruit-pitft.py"
UI_SERVICE_INSTALLER="${SCRIPT_DIR}/install_pitft_custom_ui_service.sh"

DISPLAY_TYPE="st7789v_bonnet_240x240"
ROTATION="0"
INSTALL_TYPE="console"

TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$TARGET_HOME" ]]; then
    echo "[ERROR] Unable to determine home directory for user $TARGET_USER" >&2
    exit 1
fi

VENV_DIR="${TARGET_HOME}/env"
VENV_PYTHON="${VENV_DIR}/bin/python3"
VENV_PIP="${VENV_DIR}/bin/pip3"

BOOT_DIR="/boot/firmware"
if [[ ! -d "$BOOT_DIR" ]]; then
    BOOT_DIR="/boot"
fi

usage() {
    cat <<EOF
Usage: sudo ./${SCRIPT_NAME} [options]

Options:
  --yes               Non-interactive mode (defaults: reinstall when detected, no UI service install)
  --skip-ui-prompt    Do not ask about optional UI service install
  -h, --help          Show this help

Behavior:
  - If PiTFT installation is not detected: performs install.
  - If detected: interactive wizard asks reinstall or uninstall.
  - Optionally offers UI service install/reinstall (default: no).
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
    if [[ "$EUID" -ne 0 ]]; then
        die "Run as root (use sudo)."
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local answer

    while true; do
        if [[ "$default" == "y" ]]; then
            read -r -p "$prompt [Y/n]: " answer || true
            answer="${answer:-y}"
        else
            read -r -p "$prompt [y/N]: " answer || true
            answer="${answer:-n}"
        fi

        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

install_base_dependencies() {
    log "Installing base dependencies"
    apt-get update
    apt-get install -y git python3-venv python3-pip
}

prepare_venv() {
    log "Preparing Python virtual environment at ${VENV_DIR}"

    if [[ -e "$VENV_DIR" && ! -d "$VENV_DIR" ]]; then
        warn "${VENV_DIR} exists but is not a directory, removing it"
        rm -f "$VENV_DIR"
    fi

    if [[ -d "$VENV_DIR" && ! -f "${VENV_DIR}/pyvenv.cfg" ]]; then
        warn "Existing ${VENV_DIR} is not a valid venv, removing residue"
        rm -rf "$VENV_DIR"
    fi

    if [[ ! -d "$VENV_DIR" ]]; then
        sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR" --system-site-packages
    fi

    if [[ ! -x "$VENV_PYTHON" || ! -x "$VENV_PIP" ]]; then
        warn "Venv appears broken, recreating ${VENV_DIR}"
        rm -rf "$VENV_DIR"
        sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR" --system-site-packages
    fi

    log "Installing Python dependencies in venv"
    sudo -u "$TARGET_USER" "$VENV_PIP" install --upgrade adafruit-python-shell click
}

pitft_install_detected() {
    if [[ -f "${BOOT_DIR}/config.txt" ]] && grep -q "adafruit-pitft-helper" "${BOOT_DIR}/config.txt"; then
        return 0
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^con2fbmap\.service'; then
        return 0
    fi

    if [[ -f "/etc/systemd/system/con2fbmap.service" ]] || [[ -f "/usr/local/bin/con2fbmap-helper.sh" ]]; then
        return 0
    fi

    return 1
}

run_pitft_install() {
    [[ -f "$PITFT_SCRIPT" ]] || die "Missing script: $PITFT_SCRIPT"
    log "Running PiTFT console install (${DISPLAY_TYPE}, rotation ${ROTATION})"
    "$VENV_PYTHON" "$PITFT_SCRIPT" \
        --display="$DISPLAY_TYPE" \
        --rotation="$ROTATION" \
        --install-type="$INSTALL_TYPE" \
        --reboot=no
}

run_pitft_uninstall() {
    [[ -f "$PITFT_SCRIPT" ]] || die "Missing script: $PITFT_SCRIPT"
    log "Running PiTFT uninstall"
    "$VENV_PYTHON" "$PITFT_SCRIPT" --install-type=uninstall --reboot=no
}

maybe_handle_ui_service() {
    local skip_prompt="$1"

    [[ -x "$UI_SERVICE_INSTALLER" ]] || {
        warn "UI service installer not found or not executable: $UI_SERVICE_INSTALLER"
        return 0
    }

    if [[ "$skip_prompt" -eq 1 ]]; then
        return 0
    fi

    local ui_exists=0
    if systemctl list-unit-files 2>/dev/null | grep -q '^pitft-custom-ui\.service'; then
        ui_exists=1
    fi

    if [[ "$ui_exists" -eq 1 ]]; then
        if prompt_yes_no "UI service is already installed. Re-install it now?" "n"; then
            log "Re-installing UI service"
            "$UI_SERVICE_INSTALLER" --reinstall --start-now
        fi
    else
        if prompt_yes_no "Install optional custom UI service now?" "n"; then
            log "Installing UI service"
            "$UI_SERVICE_INSTALLER" --start-now
        fi
    fi
}

main() {
    local assume_yes=0
    local skip_ui_prompt=0

    require_root

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes)
                assume_yes=1
                shift
                ;;
            --skip-ui-prompt)
                skip_ui_prompt=1
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

    install_base_dependencies
    prepare_venv

    if pitft_install_detected; then
        log "Existing PiTFT installation detected"

        local choice=""
        if [[ "$assume_yes" -eq 1 ]]; then
            choice="reinstall"
        else
            echo "Choose action:"
            echo "  1) Re-install PiTFT console setup"
            echo "  2) Uninstall PiTFT setup"
            echo "  3) Exit"
            read -r -p "Selection [1-3]: " answer
            case "$answer" in
                1) choice="reinstall" ;;
                2) choice="uninstall" ;;
                3) choice="exit" ;;
                *) die "Invalid selection" ;;
            esac
        fi

        case "$choice" in
            reinstall)
                run_pitft_uninstall
                run_pitft_install
                maybe_handle_ui_service "$skip_ui_prompt"
                ;;
            uninstall)
                run_pitft_uninstall
                if [[ "$assume_yes" -eq 0 ]] && prompt_yes_no "Also uninstall optional UI service if present?" "n"; then
                    if [[ -x "$UI_SERVICE_INSTALLER" ]]; then
                        "$UI_SERVICE_INSTALLER" --uninstall --keep-app
                    fi
                fi
                ;;
            exit)
                log "No changes made"
                ;;
            *) die "Unexpected choice: $choice" ;;
        esac
    else
        log "No existing PiTFT installation detected, running install"
        run_pitft_install
        maybe_handle_ui_service "$skip_ui_prompt"
    fi

    log "Done. Reboot is recommended to apply all display changes."
}

main "$@"
