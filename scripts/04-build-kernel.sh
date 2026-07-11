#!/usr/bin/env bash
# 04-build-kernel.sh  (PC, Linux/WSL2)
# Build the GKI Image (only) with the Docker configs merged in, stamped with a version
# string byte-identical to stock so signed vendor .ko modules keep loading.
#
# Prereq: copy configs/docker.config -> kernel_device_modules-6.6/kernel/configs/docker.config
# Output: .../mgk_64_k66_kernel_aarch64.user/Image.gz
set -euo pipefail

cd "$HOME/a05/kernel"

# EXACT stock build number -> uname == 6.6.89-android15-8-abA055FXXSHDZF1-4k
export BUILD_NUMBER=A055FXXSHDZF1

python kernel_device_modules-6.6/scripts/gen_build_config.py \
  --kernel-defconfig mediatek-bazel_defconfig \
  --kernel-defconfig-overlays "mt6768_overlay.config S96818AA1.config S96818AA1_debug.config docker.config" \
  --kernel-build-config-overlays "" -m user \
  -o ../out/target/product/a05m/obj/KERNEL_OBJ/build.config

export DEVICE_MODULES_DIR=kernel_device_modules-6.6
export PROJECT=mgk_64_k66 MODE=user
export OUT_DIR="$(pwd)/../out/target/product/a05m/obj/KLEAF_OBJ"

# Build ONLY the GKI Image target (skips vendor modules we can't fully build and don't need).
tools/bazel --output_user_root="$OUT_DIR" \
  build --config=stamp --noenable_bzlmod \
  --//build/bazel_mgk_rules:kernel_version=6.6 \
  //kernel_device_modules-6.6:mgk_64_k66_kernel_aarch64.user

IMG=$(find "$OUT_DIR" -path '*mgk_64_k66_kernel_aarch64.user/Image.gz' | head -1)
echo "built: $IMG"
echo -n "version: "; gunzip -c "$IMG" | strings | grep -m1 'Linux version 6.6'
echo "expected: Linux version 6.6.89-android15-8-abA055FXXSHDZF1-4k"
