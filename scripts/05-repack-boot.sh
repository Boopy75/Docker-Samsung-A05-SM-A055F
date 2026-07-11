#!/usr/bin/env bash
# 05-repack-boot.sh  (PC, Linux/WSL2)
# Swap our Image.gz into the STOCK boot.img (kernel-only, header v4) and wrap it as a RAW
# Odin AP tar. Odin rejects modern-frame lz4, so we pack the raw .img.
#
# Usage:  ./05-repack-boot.sh <stock_boot.img> <Image.gz>
# Extract <stock_boot.img> from the firmware AP tar:  tar xf AP_*.tar boot.img.lz4 && lz4 -d boot.img.lz4 boot.img
set -euo pipefail

STOCK_BOOT="${1:?usage: 05-repack-boot.sh <stock_boot.img> <Image.gz>}"
IMAGE_GZ="${2:?usage: 05-repack-boot.sh <stock_boot.img> <Image.gz>}"
MKB="$HOME/a05/system/tools/mkbootimg"

# capture the stock boot.img's exact mkbootimg args, then substitute our kernel
ARGS=$(python3 "$MKB/unpack_bootimg.py" --boot_img "$STOCK_BOOT" --out ./_unpack --format mkbootimg)
NEWARGS=$(printf '%s' "$ARGS" | sed "s#--kernel [^ ]*#--kernel $IMAGE_GZ#")
python3 "$MKB/mkbootimg.py" $NEWARGS --output boot_new.img

# Odin AP tar (raw image) + trailing md5
tar -H ustar -cf AP_docker.tar boot_new.img
cp AP_docker.tar AP_docker.tar.md5
md5sum -b AP_docker.tar | sed 's/$/  AP_docker.tar/' >> AP_docker.tar.md5

echo "created: AP_docker.tar.md5  (flash in Odin's AP slot)"
