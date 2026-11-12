#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
set -euo pipefail

RUST_FEED="$PWD/feeds/packages/lang/rust"
RUST_MAKEFILE="$RUST_FEED/Makefile"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPORT_DIR="${GITHUB_WORKSPACE:-$PWD}/build-reports"
mkdir -p "$REPORT_DIR"

# Ask the feed for its target triple so CI and OpenWrt use the same mapping.
RUST_TARGET=$(make --no-print-directory -s -f - TOPDIR="$PWD" ci-rust-target <<'MAKE'
include $(TOPDIR)/rules.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-values.mk
.PHONY: ci-rust-target
ci-rust-target:
	@printf '%s\n' '$(RUSTC_TARGET_ARCH)'
MAKE
)

# ========== 关键修复部分 ==========
# 当 REAL_GNU_TARGET_NAME 获取失败时（常见于 qualcommax/ipq60xx），进行兜底
if [[ -z "$RUST_TARGET" || "$RUST_TARGET" == -* || "$RUST_TARGET" == *"unknown-linux-musl" && "$RUST_TARGET" != *-*unknown* ]]; then
  echo "WARNING: Invalid RUST_TARGET='$RUST_TARGET', applying fallback..." | tee -a "$REPORT_DIR/rust-toolchain.txt"
  
  case "${WRT_TARGET:-}" in
    qualcommax)
      # IPQ60xx / IPQ807x 都是 aarch64
      RUST_TARGET="aarch64-unknown-linux-musl"
      ;;
    rockchip|sunxi|mediatek|layerscape)
      RUST_TARGET="aarch64-unknown-linux-musl"
      ;;
    x86)
      RUST_TARGET="x86_64-unknown-linux-musl"
      ;;
    *)
      # 最后尝试从环境变量或 .config 推断
      if grep -q 'CONFIG_ARCH="aarch64"' .config 2>/dev/null; then
        RUST_TARGET="aarch64-unknown-linux-musl"
      elif grep -q 'CONFIG_ARCH="arm"' .config 2>/dev/null; then
        RUST_TARGET="arm-unknown-linux-musleabi"
      else
        echo "ERROR: Cannot determine RUST_TARGET (got '$RUST_TARGET')" >&2
        exit 1
      fi
      ;;
  esac
  echo "Fallback RUST_TARGET set to: $RUST_TARGET" | tee -a "$REPORT_DIR/rust-toolchain.txt"
fi
# ==================================

RUSTUP_BIN=$(command -v rustup || true)
if [ -z "$RUSTUP_BIN" ]; then
	for candidate in "$HOME/.cargo/bin/rustup" /usr/bin/rustup; do
		if [ -x "$candidate" ]; then RUSTUP_BIN=$candidate; break; fi
	done
fi
if [ -z "$RUSTUP_BIN" ]; then
	echo "rustup is missing from the GitHub runner" >&2
	exit 1
fi
PATH="$(dirname "$RUSTUP_BIN"):$PATH"
export PATH

RUST_TOOLCHAIN=$(rustup show active-toolchain | awk '{print $1}')
printf 'Rust toolchain: %s\nRust target: %s\n' "$RUST_TOOLCHAIN" "$RUST_TARGET" | tee "$REPORT_DIR/rust-toolchain.txt"

# 强制加上 -- 防止 target 以 - 开头时被当成选项
rustup target add --toolchain "$RUST_TOOLCHAIN" -- "$RUST_TARGET"

RUST_ROOT=$(rustup run "$RUST_TOOLCHAIN" rustc --print sysroot)
test -d "$RUST_ROOT/lib/rustlib/$RUST_TARGET/lib"
for tool in cargo rustc rustdoc; do
	test -x "$RUST_ROOT/bin/$tool"
done

# Replace the source bootstrap before OpenWrt expands its host build rules.
{
	printf 'CI_RUST_ROOT:=%s\n' "$RUST_ROOT"
	cat "$SCRIPT_DIR/rust-prebuilt.mk"
} > "$RUST_FEED/ci-prebuilt.mk"

# shellcheck disable=SC2016
sed -i '/^include \.\/ci-prebuilt.mk$/d; /^$(eval $(call HostBuild))$/i include ./ci-prebuilt.mk' "$RUST_MAKEFILE"
grep -Fxq 'include ./ci-prebuilt.mk' "$RUST_MAKEFILE"

"$RUST_ROOT/bin/rustc" --version | tee -a "$REPORT_DIR/rust-toolchain.txt"
echo "Using runner Rust $RUST_TOOLCHAIN for $RUST_TARGET" | tee -a "$REPORT_DIR/rust-toolchain.txt"
sha256sum "$RUST_MAKEFILE" >> "$REPORT_DIR/rust-toolchain.txt"
