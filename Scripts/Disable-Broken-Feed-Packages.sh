#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

readonly BROKEN_PACKAGES=(
  dnsdist dnsdist-full
  fwknop fwknopd libfko
  luci-app-fwknopd luci-app-upnp luci-app-weechat
  luci-app-homeproxy miniupnpd
  mpd-full squeezelite-custom snort3 openappid knot-resolver
)

for pkg in "${BROKEN_PACKAGES[@]}"; do
  ./scripts/feeds uninstall "$pkg" >/dev/null 2>&1 || true
  find ./package -mindepth 2 -maxdepth 4 -type d -name "$pkg" -exec rm -rf -- {} + 2>/dev/null || true
  find ./feeds -mindepth 2 -maxdepth 5 -type d -name "$pkg" -exec rm -rf -- {} + 2>/dev/null || true
done

echo "Removed known recursive Kconfig packages from feeds and package tree."
