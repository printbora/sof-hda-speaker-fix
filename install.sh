#!/usr/bin/env bash
# sof-hda-speaker-fix installer.
#
#   sudo ./install.sh            check everything, fix what is missing (asks before a kernel update)
#   sudo ./install.sh --yes      same, without questions (accepts the kernel update)
#   sudo ./install.sh --check    report only, change nothing (root not required)
#   sudo ./install.sh --force    install even if no supported audio hardware is detected
#
# Steps: 1 hardware  2 packages  3 SOF firmware + topology  4 modprobe overrides
#        5 kernel support  6 DSP gain fix (udev + systemd + sleep hook)
set -u
cd "$(dirname "$(readlink -f "$0")")"
export LC_ALL=C

YES=0; CHECK=0; FORCE=0
for a in "$@"; do
    case "$a" in
        -y|--yes) YES=1 ;; --check) CHECK=1 ;; --force) FORCE=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a (see --help)"; exit 2 ;;
    esac
done

FW_ROOT="${FW_ROOT:-/lib/firmware}"          # overridable for testing
STATE="/var/lib/sof-hda-speaker-fix"
ARLS_PCI="8086:7f50"
REBOOT=0; PROBLEMS=0

say()  { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m[ok]\033[0m %s\n' "$*"; }
info() { printf '  [..] %s\n' "$*"; }
warn() { printf '  \033[33m[!!]\033[0m %s\n' "$*"; PROBLEMS=$((PROBLEMS+1)); }
ask()  { # default yes; --yes answers yes; no terminal = no
    [ "$YES" = 1 ] && return 0
    [ -t 0 ] || { info "(no terminal - skipped; re-run with --yes to accept)"; return 1; }
    local r; read -r -p "  >> $1 [Y/n] " r; [[ -z "$r" || "$r" =~ ^[yY] ]]
}

if [ "$CHECK" = 0 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo ./install.sh   (or ./install.sh --check to only look)"; exit 1
fi
[ "$CHECK" = 1 ] && echo "Check mode: nothing will be changed."

# ------------------------------------------------------------------ 1 hardware
say "1/6 Audio hardware"
HW_ARLS=0; HW_SOF=0
if lspci -nn 2>/dev/null | grep -qi "\[$ARLS_PCI\]"; then
    HW_ARLS=1; ok "Intel Arrow Lake-S/HX audio DSP found ($ARLS_PCI)"
fi
ADDR=$(lspci -D -nn 2>/dev/null | grep -i -E 'audio|multimedia' | grep -i '8086:' | grep -v -i hdmi | awk '{print $1}' | head -1)
if [ -n "$ADDR" ]; then
    DRV=$(basename "$(readlink -f "/sys/bus/pci/devices/$ADDR/driver" 2>/dev/null)" 2>/dev/null)
    info "Intel audio controller $ADDR, driver in use: ${DRV:-none}"
    [[ "$DRV" == sof-audio-pci* ]] && HW_SOF=1
fi
for f in /proc/asound/card*/codec#*; do
    [ -r "$f" ] && grep -q '^Codec: Realtek' "$f" && info "codec: $(sed -n 's/^Codec: //p' "$f") ($(grep -m1 -o 'Subsystem Id: 0x[0-9a-f]*' "$f"))"
done
if [ "$HW_ARLS" = 0 ] && [ "$HW_SOF" = 0 ] && [ "$FORCE" = 0 ]; then
    echo; echo "No supported Intel SOF audio hardware found. Nothing to do (use --force to install anyway)."
    exit 1
fi

# ------------------------------------------------------------------ 2 packages
say "2/6 Packages"
MISSING=()
command -v amixer  >/dev/null 2>&1 || MISSING+=(alsa-utils)
[ -d /usr/share/alsa/ucm2 ]        || MISSING+=(alsa-ucm-conf)
if [ ${#MISSING[@]} -eq 0 ]; then ok "alsa-utils and alsa-ucm-conf present"
elif [ "$CHECK" = 1 ]; then warn "missing: ${MISSING[*]}"
elif command -v apt-get >/dev/null 2>&1; then
    info "installing: ${MISSING[*]}"
    apt-get install -y "${MISSING[@]}" >/dev/null && ok "installed ${MISSING[*]}" || warn "could not install ${MISSING[*]} (no internet?)"
else warn "please install: ${MISSING[*]}"; fi

# ------------------------------------------------------------------ 3 firmware
say "3/6 SOF firmware and topology"
if ! (cd firmware && sha256sum --quiet -c SHA256SUMS) >/dev/null 2>&1; then
    echo "  bundled firmware is corrupted (SHA256SUMS mismatch) - download the release again."; exit 1
fi
FW_NEW=0
while read -r _ rel; do
    case "$rel" in intel/sof-ipc4/arl-s/*) [ "$HW_ARLS" = 1 ] || [ "$FORCE" = 1 ] || continue ;; esac
    dst="$FW_ROOT/$rel"
    if [ -e "$dst" ] || [ -e "$dst.zst" ] || [ -e "$dst.xz" ]; then
        ok "present: $rel"
    elif [ "$CHECK" = 1 ]; then
        warn "MISSING: $rel (the installer will add it)"
    else
        install -D -m 0644 "firmware/$rel" "$dst" && { ok "installed: $rel"; FW_NEW=1; mkdir -p "$STATE"; echo "$dst" >> "$STATE/installed-firmware"; }
    fi
done < firmware/SHA256SUMS
if [ "$FW_NEW" = 1 ]; then
    command -v update-initramfs >/dev/null 2>&1 && [ "$FW_ROOT" = /lib/firmware ] && update-initramfs -u >/dev/null 2>&1
    REBOOT=1
fi
if journalctl -k -b --no-pager 2>/dev/null | grep -qi 'sof.*Booted firmware version'; then
    ok "DSP firmware booted: $(journalctl -k -b --no-pager 2>/dev/null | grep -i -m1 -o 'Booted firmware version: .*')"
fi

# ------------------------------------------------------------------ 4 overrides
say "4/6 Driver overrides"
BAD=$(grep -rlE '^\s*options\s+snd[-_]intel[-_]dspcfg\s+.*dsp_driver=1' /etc/modprobe.d/ 2>/dev/null)
if [ -z "$BAD" ]; then ok "SOF is not disabled by any modprobe option"
else
    for f in $BAD; do
        warn "$f forces the legacy HDA driver (dsp_driver=1): internal microphone cannot work"
        if [ "$CHECK" = 0 ] && ask "Comment out that line (backup kept as $f.bak)?"; then
            cp -a "$f" "$f.bak" && sed -i -E 's/^(\s*options\s+snd[-_]intel[-_]dspcfg\s+.*dsp_driver=1.*)$/# disabled by sof-hda-speaker-fix: \1/' "$f" \
                && { ok "disabled in $f"; PROBLEMS=$((PROBLEMS-1)); REBOOT=1; command -v update-initramfs >/dev/null && update-initramfs -u >/dev/null 2>&1; }
        fi
    done
fi

# ------------------------------------------------------------------ 5 kernel
say "5/6 Kernel"
kernel_ok() { modinfo -k "$1" snd_sof_pci_intel_mtl 2>/dev/null | grep -qi 'v00008086d00007F50'; }
if [ "$HW_ARLS" = 0 ]; then info "not an Arrow Lake-S/HX system - kernel check skipped"
elif kernel_ok "$(uname -r)"; then ok "running kernel $(uname -r) supports this audio DSP"
else
    GOOD=""; for k in $(ls -1 /lib/modules | sort -V -r); do kernel_ok "$k" && { GOOD=$k; break; }; done
    if [ -n "$GOOD" ]; then
        warn "running kernel $(uname -r) does not support this DSP, but installed kernel $GOOD does -> reboot into it"
        REBOOT=1
    elif [ "$CHECK" = 1 ]; then warn "kernel $(uname -r) does not support this DSP; the installer will offer a kernel update"
    else
        . /etc/os-release 2>/dev/null
        PKG=""; [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = "22.04" ] && PKG="linux-generic-hwe-22.04"
        warn "kernel $(uname -r) does not support the Arrow Lake-S/HX audio DSP"
        if [ -n "$PKG" ] && ask "Install/update $PKG (latest Ubuntu 6.8 HWE kernel, needs internet)?"; then
            apt-get update -qq && apt-get install -y "$PKG" && { ok "$PKG installed"; PROBLEMS=$((PROBLEMS-1)); REBOOT=1; } || warn "kernel update failed"
        elif [ -z "$PKG" ]; then info "update to a kernel with SOF Arrow Lake-S support (Ubuntu: newest HWE/OEM kernel)"; fi
    fi
fi

# ------------------------------------------------------------------ 6 gain fix
say "6/6 DSP gain fix (speakers at -90 dB)"
if [ "$CHECK" = 1 ]; then
    bash ./sof-gain-fix apply --dry-run | sed 's/^/  /'
else
    install -D -m 0755 sof-gain-fix                   /usr/local/sbin/sof-gain-fix
    install -D -m 0644 files/99-sof-gain-fix.rules    /etc/udev/rules.d/99-sof-gain-fix.rules
    install -D -m 0644 files/sof-gain-fix.service     /etc/systemd/system/sof-gain-fix.service
    install -D -m 0755 files/sof-gain-fix.sleep       /usr/lib/systemd/system-sleep/sof-gain-fix
    [ -e /etc/default/sof-gain-fix ] || install -D -m 0644 files/sof-gain-fix.default /etc/default/sof-gain-fix
    udevadm control --reload 2>/dev/null || true
    systemctl daemon-reload; systemctl enable sof-gain-fix.service >/dev/null 2>&1
    ok "tool, udev rule, systemd service and sleep hook installed"
    /usr/local/sbin/sof-gain-fix apply | sed 's/^/  /'
fi

# ------------------------------------------------------------------ summary
say "Summary"
if [ "$CHECK" = 1 ]; then
    [ "$PROBLEMS" -eq 0 ] && echo "  Nothing missing." || echo "  $PROBLEMS item(s) need attention - run: sudo ./install.sh"
elif [ "$REBOOT" = 1 ]; then
    printf '  \033[1;33mREBOOT REQUIRED.\033[0m After the reboot everything is applied automatically.\n'
    echo "  Afterwards you can verify with: sudo ./install.sh --check"
else
    echo "  Done. Unplug headphones and test:  speaker-test -c 2 -t wav -l 1"
    echo "  State at any time:                 sof-gain-fix status"
fi
[ "$PROBLEMS" -gt 0 ] && echo "  Open issues: $PROBLEMS (see [!!] lines above)."
echo "  Uninstall:                         sudo ./uninstall.sh"
exit 0
