#!/usr/bin/env bash
# Installer for sof-gain-fix. Usage: sudo ./install.sh [--force]
set -eu
cd "$(dirname "$(readlink -f "$0")")"
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo ./install.sh"; exit 1; }
command -v amixer >/dev/null 2>&1 || { echo "amixer not found - install it first: sudo apt install alsa-utils"; exit 1; }

echo "== Checking this machine"
CHECK=$(bash ./sof-gain-fix apply --dry-run)
echo "$CHECK"
if ! grep -qE "^  (ok|would set) " <<< "$CHECK"; then
    echo
    echo "No SOF card with the known DSP gain controls was found, so this fix does not apply here."
    echo "Make sure the SOF driver is in use (see README, 'Requirements'). Use --force to install anyway."
    [ "$FORCE" = 1 ] || exit 1
fi

echo "== Installing"
install -D -m 0755 sof-gain-fix                   /usr/local/sbin/sof-gain-fix
install -D -m 0644 files/99-sof-gain-fix.rules    /etc/udev/rules.d/99-sof-gain-fix.rules
install -D -m 0644 files/sof-gain-fix.service     /etc/systemd/system/sof-gain-fix.service
install -D -m 0755 files/sof-gain-fix.sleep       /usr/lib/systemd/system-sleep/sof-gain-fix
[ -e /etc/default/sof-gain-fix ] || install -D -m 0644 files/sof-gain-fix.default /etc/default/sof-gain-fix
udevadm control --reload 2>/dev/null || true
systemctl daemon-reload
systemctl enable sof-gain-fix.service >/dev/null 2>&1
echo "  /usr/local/sbin/sof-gain-fix, udev rule, systemd service and sleep hook installed"

echo "== Applying now"
/usr/local/sbin/sof-gain-fix apply

cat <<'MSG'

Done. Unplug headphones and test the speakers:
    speaker-test -c 2 -t wav -l 1
Check the state at any time with:  sof-gain-fix status
Remove with:                       sudo ./uninstall.sh
MSG
