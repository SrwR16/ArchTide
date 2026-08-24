#!/bin/bash
# Flow platform — distro detection + package manager abstraction

detect_distro() {
    if [[ -f /etc/arch-release ]]; then echo "arch"
    elif [[ -f /etc/fedora-release ]]; then echo "fedora"
    elif [[ -f /etc/gentoo-release ]]; then echo "gentoo"
    elif command -v nixos-version &>/dev/null; then echo "nixos"
    elif [[ -f /etc/debian_version ]]; then echo "debian"
    else echo "unknown"
    fi
}

pkgmgr_detect() {
    case "$(detect_distro)" in
        arch)   echo "pacman" ;;
        fedora) echo "dnf" ;;
        gentoo) echo "emerge" ;;
        debian) echo "apt" ;;
        *)      echo "none" ;;
    esac
}

# Stream package output live while still logging
_pkg_run() {
    local rc=0
    if [[ -n "${FLOW_LOG_FILE:-}" && -w "$(dirname "$FLOW_LOG_FILE")" ]]; then
        "$@" 2>&1 | tee -a "$FLOW_LOG_FILE"; rc=${PIPESTATUS[0]}
    else
        "$@"; rc=$?
    fi
    return $rc
}

pkg_install() {
    local mgr; mgr=$(pkgmgr_detect)
    local -a repo=() aur=()
    for p in "$@"; do
        if [[ "$mgr" == pacman ]] && ! pacman -Si "$p" &>/dev/null; then aur+=("$p"); else repo+=("$p"); fi
    done
    if ((${#repo[@]})); then
        case "$mgr" in
            pacman) _pkg_run sudo pacman -S --needed --noconfirm "${repo[@]}" ;;
            dnf)    _pkg_run sudo dnf install -y "${repo[@]}" ;;
            apt)    _pkg_run sudo apt-get install -y "${repo[@]}" ;;
            emerge) _pkg_run sudo emerge -av "${repo[@]}" ;;
        esac
    fi
    if ((${#aur[@]})) && [[ "$mgr" == pacman ]]; then
        local helper=""
        for h in yay paru; do command -v "$h" &>/dev/null && { helper="$h"; break; }; done
        if [[ -n "$helper" ]]; then
            _pkg_run "$helper" -S --needed --noconfirm "${aur[@]}"
        else
            echo "✗ AUR packages need yay/paru: ${aur[*]}"
            return 1
        fi
    fi
}

pkg_installed() { command -v "$1" &>/dev/null; }
