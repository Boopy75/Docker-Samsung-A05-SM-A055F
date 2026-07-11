#!/usr/bin/env bash
# 02-fetch-toolchain.sh  (PC, Linux/WSL2)
# Samsung ships kernel SOURCE only; the MediaTek Kleaf/Bazel build also needs the AOSP
# prebuilts/ and external/ trees. Fetch them as tarballs from the branch the kernel
# manifest (common-android15-6.6) pins everything to: main-kernel-build-2024.
# Key toolchain: clang r510928.
set -euo pipefail

REF=refs/heads/main-kernel-build-2024
GS=https://android.googlesource.com
ROOT="$HOME/a05/kernel"
[ -d "$ROOT" ] || { echo "run 01-extract-source.sh first" >&2; exit 1; }

# get <dest_abs_dir> <aosp_project_name> [subdir]
get(){
  mkdir -p "$1"
  if curl -sf "$GS/$2/+archive/$REF${3:+/$3}.tar.gz" | tar xz -C "$1" 2>/dev/null; then
    echo "  ok   $2${3:+/$3}"
  else
    echo "  FAIL $2${3:+/$3}" >&2
  fi
}

echo "== clang (only r510928) + kleaf glue =="
get "$ROOT/prebuilts/clang/host/linux-x86/clang-r510928" platform/prebuilts/clang/host/linux-x86 clang-r510928
get "$ROOT/prebuilts/clang/host/linux-x86/kleaf"          platform/prebuilts/clang/host/linux-x86 kleaf

echo "== prebuilts =="
get "$ROOT/prebuilts/build-tools"        platform/prebuilts/build-tools
get "$ROOT/prebuilts/kernel-build-tools" kernel/prebuilts/build-tools
get "$ROOT/prebuilts/clang-tools"        platform/prebuilts/clang-tools
get "$ROOT/prebuilts/jdk/jdk11"          platform/prebuilts/jdk/jdk11
get "$ROOT/prebuilts/ndk-r26"            toolchain/prebuilts/ndk/r26
get "$ROOT/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8" \
    platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8

echo "== external/ (clear Samsung's empty stub symlinks, then fetch real repos) =="
for r in bazel-skylib bazelbuild-rules_cc bazelbuild-rules_java bazelbuild-rules_license \
         bazelbuild-rules_pkg bazelbuild-rules_python python/absl-py libcap libcap-ng \
         pigz zopfli bazelbuild-platforms toybox lz4 bazelbuild-apple_support; do
  rm -rf "$ROOT/external/$r"
  get "$ROOT/external/$r" "platform/external/$r"
done
# harmless empty stubs for two repos absent on this branch (rust is off in our config)
for r in bazelbuild-rules_rust stardoc; do
  mkdir -p "$ROOT/external/$r"
  : > "$ROOT/external/$r/BUILD.bazel"
  echo "workspace(name=\"$r\")" > "$ROOT/external/$r/WORKSPACE"
done

echo "== support repos above the workspace =="
get "$HOME/a05/build/bazel_common_rules" platform/build/bazel_common_rules
get "$HOME/a05/system/tools/mkbootimg"    platform/system/tools/mkbootimg

echo "done."
