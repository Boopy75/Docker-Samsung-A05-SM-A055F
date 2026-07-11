#!/usr/bin/env python3
"""patch-vbmeta.py  (PC)

Disable Android Verified Boot by setting the vbmeta header flags to 3
(HASHTREE_DISABLED | VERIFICATION_DISABLED). Required because the custom kernel changes
the boot/init_boot hashes, which would otherwise bootloop the device.

Extract the stock vbmeta.img from the firmware AP tar first
(tar xf AP_*.tar vbmeta.img.lz4 && lz4 -d vbmeta.img.lz4 vbmeta.img).

Usage:  ./patch-vbmeta.py vbmeta.img
"""
import struct, sys

path = sys.argv[1] if len(sys.argv) > 1 else "vbmeta.img"
d = bytearray(open(path, "rb").read())
assert d[:4] == b"AVB0", "not a vbmeta image (bad magic)"
old, = struct.unpack_from(">I", d, 120)   # flags: uint32 big-endian at header offset 120
struct.pack_into(">I", d, 120, 3)
open(path, "wb").write(d)
print(f"{path}: flags {old} -> 3 (AVB disabled)")
