#!/usr/bin/env bash
# sof-hda-speaker-fix uninstaller.
#   sudo ./uninstall.sh           remove the gain-fix tool, udev rule, service and sleep hook
#   sudo ./uninstall.sh --purge   also remove the firmware files this package added
#                                 (WARNING: without them the sound card will not work)
set -u
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo ./uninstall.sh"; exit 1; }
STATE="/var/lib/sof-hda-speaker-fix"
systemctl disable sof-gain-fix.service >/dev/null 2>&1
rm -f /etc/systemd/system/sof-gain-fix.service \
      /etc/udev/rules.d/99-sof-gain-fix.rules \
      /usr/lib/systemd/system-sleep/sof-gain-fix \
      /usr/local/sbin/sof-gain-fix \
      /etc/default/sof-gain-fix
systemctl daemon-reload
udevadm control --reload 2>/dev/null || true
echo "sof-gain-fix removed. The current gain values were left as they are."

if [ "${1:-}" = "--purge" ] && [ -f "$STATE/installed-firmware" ]; then
    while read -r f; do [ -n "$f" ] && rm -f "$f" && echo "removed $f"; done < "$STATE/installed-firmware"
    rm -rf "$STATE"
    command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u >/dev/null 2>&1
    echo "Firmware added by this package was removed. Reboot; the sound card will be missing until"
    echo "your distribution provides the firmware."
elif [ -f "$STATE/installed-firmware" ]; then
    echo "Firmware added by this package was kept (sound needs it). Remove it with: sudo ./uninstall.sh --purge"
fi
