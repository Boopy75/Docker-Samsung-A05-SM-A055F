#!/usr/bin/env bash
# 03-fixups.sh  (PC, Linux/WSL2)
# Three fixes the Samsung tree needs before it will build:
#   1. build_kernel.sh calls `python` (Ubuntu only has python3)
#   2. kernel-6.6 is a symlink that escapes the Bazel workspace -> make it a real in-workspace dir
#   3. drop ABI/KMI symbol-list enforcement (irrelevant for a custom kernel; otherwise the build
#      fails on a dangling abi_symbollist.raw symlink)
set -euo pipefail

A05="$HOME/a05"
[ -d "$A05/kernel" ] || { echo "run 01/02 first" >&2; exit 1; }

# 1. python shim (needs sudo)
sudo ln -sf /usr/bin/python3 /usr/bin/python

# 2. de-escape the kernel-6.6 symlink
if [ -L "$A05/kernel-6.6" ] || { [ -L "$A05/kernel/kernel-6.6" ] && [ ! -d "$A05/kernel/kernel-6.6/" ]; }; then
  rm -f "$A05/kernel/kernel-6.6"
  mv "$A05/kernel-6.6" "$A05/kernel/kernel-6.6"
  ln -s kernel/kernel-6.6 "$A05/kernel-6.6"
fi

# 3. disable ABI/KMI symbol list for the device kernel_build
sed -i 's/kmi_symbol_list = symbol_list,/kmi_symbol_list = None,/' \
  "$A05/kernel/build/bazel_mgk_rules/mgk.bzl"

echo "fixups applied."
