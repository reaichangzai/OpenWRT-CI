#!/usr/bin/env bash
# Work around recursive Kconfig dependencies in optional packages from moving feeds.
# These packages are not selected by this firmware config; uninstalling their feed
# links prevents their broken Kconfig entries from poisoning the global defconfig.
set -euo pipefail

packages=(
  dnsdist dnsdist-full
  luci-app-upnp miniupnpd
  fwknop fwknopd libfko luci-app-fwknopd
  luci-app-weechat
  mpd-full squeezelite-custom
  snort3 openappid knot-resolver
)

for package in "${packages[@]}"; do
  # feeds uninstall returns nonzero when a package is absent or not installed.
  ./scripts/feeds uninstall "$package" >/dev/null 2>&1 || true
done

# Custom package feeds may copy directories directly into package/ instead of
# exposing them through feeds. Remove only the affected optional package dirs.
for package in luci-app-upnp miniupnpd; do
  find ./package -mindepth 2 -maxdepth 3 -type d -name "$package" -prune -exec rm -rf -- {} +
done

echo "Removed optional packages with known recursive Kconfig dependencies."
