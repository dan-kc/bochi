#!/bin/bash
# Debug version - print environment after modifications

# Filter PATH to remove Nix compiler toolchain but keep other Nix tools
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v 'clang-wrapper' | grep -v 'clang-21' | grep -v 'cctools-binutils' | grep -v 'xcbuild' | tr '\n' ':' | sed 's/:$//')

# Unset ALL Nix compiler/SDK variables
unset NIX_CFLAGS_COMPILE
unset NIX_LDFLAGS
unset NIX_CC
unset NIX_CC_WRAPPER_TARGET_HOST_arm64_apple_darwin
unset NIX_BINTOOLS
unset NIX_BINTOOLS_WRAPPER_TARGET_HOST_arm64_apple_darwin
unset NIX_ENFORCE_NO_NATIVE
unset NIX_HARDENING_ENABLE
unset NIX_IGNORE_LD_THROUGH_GCC

# Critical: Reset SDK to use real Xcode
unset SDKROOT
unset DEVELOPER_DIR

export PATH="$CLEAN_PATH"
export LANG="en_US.UTF-8"

echo "=== DEBUG: Checking environment ==="
echo "SDKROOT=${SDKROOT:-unset}"
echo "DEVELOPER_DIR=${DEVELOPER_DIR:-unset}"
echo "NIX_BINTOOLS=${NIX_BINTOOLS:-unset}"
echo "which ld: $(which ld)"
echo "which clang: $(which clang)"
echo "xcrun --find ld: $(xcrun --find ld 2>&1)"
