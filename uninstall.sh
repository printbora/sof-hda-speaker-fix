#!/usr/bin/env bash
# Uninstaller for sof-gain-fix. Usage: sudo ./uninstall.sh
set -u
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo ./uninstall.sh"; exit 1; }
systemctl disable sof-gain-fix.service >/dev/null 2>&1
rm -f /etc/systemd/system/sof-gain-fix.service \
      /etc/udev/rules.d/99-sof-gain-fix.rules \
      /usr/lib/systemd/system-sleep/sof-gain-fix \
      /usr/local/sbin/sof-gain-fix \
      /etc/default/sof-gain-fix
systemctl daemon-reload
udevadm control --reload 2>/dev/null || true
echo "sof-gain-fix removed."
echo "The current gain values were left as they are (and remain in /var/lib/alsa/asound.state)."
echo "Lowering them back to -90 dB would silence the speakers again; if you really want that, use alsamixer."
