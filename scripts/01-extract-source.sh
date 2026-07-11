#!/usr/bin/env bash
# 01-extract-source.sh  (PC, Linux/WSL2)
# Extract Kernel.tar.gz out of the Samsung Opensource zip into ~/a05.
# MUST run on a Linux/ext4 filesystem so the tree's symlinks survive.
#
# Usage:  ./01-extract-source.sh [path/to/SM-A055F_15_Opensource.zip]
set -euo pipefail

ZIP="${1:-SM-A055F_15_Opensource.zip}"
[ -f "$ZIP" ] || { echo "not found: $ZIP" >&2; exit 1; }

mkdir -p "$HOME/a05" && cd "$HOME/a05"
python3 - "$ZIP" <<'PY' | tar xz
import zipfile, sys
z = zipfile.ZipFile(sys.argv[1])
with z.open("Kernel.tar.gz") as f:
    while (chunk := f.read(1 << 20)):
        sys.stdout.buffer.write(chunk)
PY

echo "extracted ->"
echo "  ~/a05/kernel      (Bazel/Kleaf workspace)"
echo "  ~/a05/kernel-6.6  (GKI common tree)"
echo "  ~/a05/vendor      (mediatek device modules)"
