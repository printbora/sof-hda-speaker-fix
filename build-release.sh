#!/usr/bin/env bash
# Builds dist/sof-hda-speaker-fix-<version>.zip for a GitHub release.
set -eu
cd "$(dirname "$(readlink -f "$0")")"
V=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' sof-gain-fix)
N="sof-hda-speaker-fix-$V"
rm -rf "dist/$N" "dist/$N.zip"; mkdir -p "dist/$N/files"
cp README.md LICENSE install.sh uninstall.sh sof-gain-fix "dist/$N/"
cp files/* "dist/$N/files/"
cp -a firmware "dist/$N/"
(cd dist && zip -qr "$N.zip" "$N" && sha256sum "$N.zip" > "$N.zip.sha256")
rm -rf "dist/$N"
echo "dist/$N.zip"; cat "dist/$N.zip.sha256"
