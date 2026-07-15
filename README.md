# Samsung Galaxy A05 → Headless Docker Server

Turn a Samsung Galaxy A05 (SM‑A055F, MediaTek Helio G85) into a **reboot‑proof, SSH‑accessible Docker + Compose host** running on **stock Android 15** with a custom‑configured GKI kernel — **no custom ROM, no firmware downgrade, no brick risk, and fully revertible to stock.**

> **Status:** working. Containers run, pull from Docker Hub, and reach the internet. Docker + Compose auto‑start on boot; you `ssh` in and use `docker` / `docker compose` directly.

---

## 1. What

| | |
|---|---|
| **Device** | Samsung Galaxy A05, **SM‑A055F/DS** (device `a05m`) |
| **SoC** | MediaTek Helio G85 (`mt6768`), arm64‑v8a, 4 GB RAM |
| **OS** | Stock Android 15, kernel **6.6.89‑android15 (GKI 2.0)** |
| **Built against** | firmware `A055FXXSHDZF1` (binary 8) → kernel string `6.6.89-android15-8-abA055FXXSHDZF1-4k` |
| **Result** | rooted (Magisk) + AVB‑off, Termux/OpenSSH, Debian chroot, **Docker 26.1.5 + Compose v2**, host‑mode networking, boot autostart, ~70 % battery cap |

**Why a custom kernel?** Docker needs Linux namespaces/IPC that Google's GKI base ships **disabled** (`CONFIG_PID_NS`, `CONFIG_IPC_NS`, `CONFIG_POSIX_MQUEUE`). These can't be enabled from userspace — they must be compiled into the kernel `Image`. Everything else rides on top.

**Two decisions that make it work on a phone:**
- Rebuild only the **kernel `Image`**; keep every stock vendor partition → WiFi/BT/etc. keep working, and the kernel version string is kept **byte‑identical** to stock so signed vendor `.ko` modules still load.
- Run Docker in a **real Debian chroot** with **cgroup v2** (eBPF device control) and **host‑mode networking** → avoids the exact kernel configs and firewall paths that don't work on Android.

---

## 2. Repository layout

```
.
├── README.md
├── configs/
│   └── docker.config           # kernel config fragment (the container options)
├── scripts/                    # PC-side build (Linux / WSL2)
│   ├── 01-extract-source.sh
│   ├── 02-fetch-toolchain.sh
│   ├── 03-fixups.sh
│   ├── 04-build-kernel.sh
│   ├── 05-repack-boot.sh
│   └── patch-vbmeta.py
├── device/                     # runs on the phone (as root unless noted)
│   ├── install-docker.sh
│   ├── start-docker.sh         # → /data/adb/docker/start-docker.sh
│   ├── charge-cap.sh           # → /data/adb/battery/charge-cap.sh
│   ├── docker-wrapper.sh       # → …/usr/bin/docker  (Termux)
│   └── service.d/              # → /data/adb/service.d/  (Magisk boot services)
│       ├── start-docker.sh
│       ├── start-sshd.sh
│       └── charge-cap.sh
└── examples/
    └── compose.yaml
```

---

## 3. Pipeline

Phases 1–3 are non‑destructive PC work. Phase 4's unlock is the point of no return (factory reset). From Phase 5 on, everything is driven over SSH.

```
PC (Linux/WSL2)                          Phone (Odin download-mode + adb)
────────────────                         ───────────────────────────────
1. Samsung kernel source     ─┐
2. AOSP toolchain (r510928)  ─┼─►  build custom boot.img ──┐
3. add container configs     ─┘                            │
                                                           ▼
                                        4. unlock bootloader (WIPES)
                                        4. Magisk-patch init_boot (root)
                                        4. patch vbmeta (disable AVB)
                                        4. flash custom boot.img
                                        5. Termux + OpenSSH
                                        6. Debian chroot + Docker + Compose
                                        7. boot autostart + battery cap
```

---

## 4. Prerequisites

- The A05, a USB‑C cable, a PC.
- **Linux build host** — Ubuntu 22.04+ (WSL2 works). ~15 GB RAM, ~30 GB free, multi‑core. Install:
  `git curl python3 make gcc bison flex libssl-dev libelf-dev zstd lz4 cpio rsync`.
- **Windows tools** — `adb`/`fastboot` (platform‑tools) and **Odin3**.

---

## 5. Files to download

| File | Source | Used for |
|---|---|---|
| **Full stock firmware** `SM-A055F_…_fac.zip` | Frija / [samfw.com](https://samfw.com/firmware/SM-A055F) (model `SM-A055F`, your CSC) | Holds `BL/AP/CP/CSC` tarballs. Extract `boot.img`, `init_boot.img`, `vbmeta.img` from **AP**; keep the whole set as the **revert kit**. |
| **Kernel source** `SM-A055F_15_Opensource.zip` | [opensource.samsung.com](https://opensource.samsung.com) → search `SM-A055F` | Contains `Kernel.tar.gz` — the tree you build. |
| **AOSP toolchain + support repos** | [android.googlesource.com](https://android.googlesource.com), branch `main-kernel-build-2024` | Samsung ships source only; Kleaf needs `prebuilts/` + `external/`. Fetched by `scripts/02-fetch-toolchain.sh`. Key: clang **r510928**. |
| **Magisk** `Magisk-vXX.apk` | [github.com/topjohnwu/Magisk](https://github.com/topjohnwu/Magisk/releases) | Root — patches `init_boot.img`. |
| **Termux** + **Termux:Boot** (arm64‑v8a) | [github.com/termux/termux-app](https://github.com/termux/termux-app/releases), [termux-boot](https://github.com/termux/termux-boot/releases) | On‑device Linux + SSH (use the **GitHub** builds). |
| **Odin3** | XDA | Windows flasher (Samsung uses download mode, not fastboot). |

> The Compose plugin is fetched on‑device by `device/install-docker.sh`.

To get `boot.img` / `init_boot.img` / `vbmeta.img` out of the firmware:
```bash
tar xf AP_A055F*.tar boot.img.lz4 init_boot.img.lz4 vbmeta.img.lz4
for f in boot init_boot vbmeta; do lz4 -d $f.img.lz4 $f.img; done
```

---

## 6. Phase 1 — Build the custom kernel (PC)

Run in order. Full details are in each script's header.

```bash
scripts/01-extract-source.sh  ~/Downloads/SM-A055F_15_Opensource.zip   # → ~/a05
scripts/02-fetch-toolchain.sh                                          # AOSP prebuilts + external
scripts/03-fixups.sh                                                   # python shim, symlink, mgk.bzl
cp configs/docker.config  ~/a05/kernel/kernel_device_modules-6.6/kernel/configs/
scripts/04-build-kernel.sh                                             # → Image.gz (version-matched)
scripts/05-repack-boot.sh  boot.img  <path>/Image.gz                  # → AP_docker.tar.md5
```

- **`configs/docker.config`** is the whole reason for the rebuild — the container options, and (in its comments) the ones that **must stay off** or the device won't boot. See footnote **[A]**.
- **`04-build-kernel.sh`** stamps `BUILD_NUMBER=A055FXXSHDZF1` so `uname` matches stock exactly; it verifies the string at the end.
- **`05-repack-boot.sh`** swaps our `Image.gz` into the stock (kernel‑only, header v4) `boot.img` and wraps a **raw** Odin AP tar (Odin rejects modern lz4).

---

## 7. Phase 2 — Unlock · root · disable AVB (device)

1. **Unlock the bootloader — ⚠️ factory‑resets the phone.** Enable OEM unlocking + USB debugging, `adb reboot download`, long‑press **Vol‑Up** to unlock. Redo setup, re‑enable USB debugging.
2. **Root — Magisk patches `init_boot`** (root lives there, separate from the kernel's `boot.img`). Install Magisk, push stock `init_boot.img`, patch in‑app (*Install → Select and Patch a File*), pull `magisk_patched-*.img`.
3. **Disable AVB** — `scripts/patch-vbmeta.py vbmeta.img` (sets header flags = 3). Required or the custom kernel bootloops.
4. **Flash** `init_boot` (patched), `vbmeta`, and the kernel `boot.img` as raw AP tars in Odin's **AP** slot (BL/CP/CSC empty). First boot takes 2–5 min.

> **Never** flash `BL/CP/CSC` from a *different* firmware version — anti‑rollback can permanently brick (footnote **[B]**). This build only touches `boot`/`init_boot`/`vbmeta`, so it's safe.

---

## 8. Phase 3 — SSH access (Termux)

Install both APKs, open **Termux** once (it bootstraps), then in the Termux terminal:
```bash
pkg update -y && pkg install -y openssh proot-distro
mkdir -p ~/.ssh && echo "ssh-ed25519 AAAA... you@host" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
sshd                                       # listens on port 8022
```
Connect: `ssh -p 8022 <termux-user>@<phone-ip>` (user from `whoami`, e.g. `u0_a262`).
Package installs must run **inside the Termux app** — via `su` from adb they fail DNS (footnote **[C]**).

Grant Termux root once, headlessly, via Magisk's policy DB (uid from `stat -c %u ~`):
```bash
adb shell su -c 'magisk --sqlite "INSERT OR REPLACE INTO policies \
  (uid,policy,until,logging,notification) VALUES (<uid>,2,0,1,0)"'
```

---

## 9. Phase 4 — Debian chroot + Docker

Install a Debian rootfs, then Docker + Compose into it (we run it as a **real chroot**, not proot):
```bash
# in Termux:
proot-distro install debian
# then, as root (over SSH or adb):
device/install-docker.sh          # docker.io + fuse-overlayfs + iptables-legacy + Compose v2
```

---

## 10. Phase 5 — Boot autostart, wrapper, battery

Install the device scripts and Magisk services:
```bash
# as root on the phone:
mkdir -p /data/adb/docker /data/adb/battery
cp device/start-docker.sh   /data/adb/docker/     && chmod 755 /data/adb/docker/start-docker.sh
cp device/charge-cap.sh     /data/adb/battery/    && chmod 755 /data/adb/battery/charge-cap.sh
cp device/service.d/*.sh    /data/adb/service.d/  && chmod 755 /data/adb/service.d/*.sh
# docker wrapper into Termux PATH (chown to the Termux uid):
TU=/data/data/com.termux/files/usr/bin/docker
cp device/docker-wrapper.sh "$TU" && chmod 755 "$TU" \
  && chown "$(stat -c %u /data/data/com.termux/files/usr/bin)":"$(stat -c %g /data/data/com.termux/files/usr/bin)" "$TU"
# start now (or reboot):
/data/adb/docker/start-docker.sh
```

- **`device/start-docker.sh`** — idempotent chroot bring‑up + `dockerd`. Every non‑obvious flag is required on Android:

  | Flag / step | Why |
  |---|---|
  | `setenforce 0` | runc's privileged mounts are blocked SELinux‑enforcing |
  | fresh `cgroup2` mount | Android's hybrid layout makes Docker pick v1 and demand a *devices* cgroup we can't enable; a pure v2 view uses eBPF (`CGROUP_BPF` is on) |
  | `--storage-driver=fuse-overlayfs` | kernel `overlay2` won't mount on Android `/data` |
  | `iptables-legacy` (set in `install-docker.sh`) | the kernel has **no nftables** |
  | `DOCKER_RAMDISK=1` | makes runc use `MS_MOVE`+chroot instead of `pivot_root` (blocked here) |
  | `--iptables=false --bridge=none` | host‑network mode — Android's netd firewall blocks bridge networking (footnote **[D]**) |
  | `mount --bind $RD $RD` | so `/` is a real mountpoint, else runc errors on remount |

- **`device/service.d/*.sh`** — Magisk `late_start` services (boot receivers are unreliable on Samsung). They start Docker, sshd, and the battery cap on every boot.
- **`device/docker-wrapper.sh`** — so the SSH user runs `docker …` / `docker compose …` transparently.
- **`device/charge-cap.sh`** — holds the battery ~70 % via `batt_slate_mode` for 24/7 use.

---

## 11. Using it

```bash
ssh -p 8022 <user>@<phone-ip>
docker run -d --network host --restart unless-stopped nginx     # service on :80
docker compose up -d                                            # see examples/compose.yaml
```

**Networking is host‑mode only** — containers use Android's own network stack (full outbound internet + DNS; services bind ports on the phone's IP). No `-p` remapping, no isolated bridge networks. Compose services need `network_mode: host` (see `examples/compose.yaml`).

### DNS

Set your resolvers once via the `DNS1` / `DNS2` / `DNS_SEARCH` variables at the top of `device/start-docker.sh` **and** `device/install-docker.sh` (use the same values in both; leave `DNS_SEARCH` blank if you have no internal search domain). They are pinned in **three** places:

| Consumer | Where | Set by |
|---|---|---|
| **Termux** | `…/usr/etc/resolv.conf` | `device/start-docker.sh` (rewritten every boot) |
| **Chroot** (apt, etc.) | `<rootfs>/etc/resolv.conf` | `device/start-docker.sh` + `install-docker.sh` |
| **Docker** containers | `<rootfs>/etc/docker/daemon.json` → `"dns"` / `"dns-search"` | `device/install-docker.sh` |

> **Gotcha:** set Docker's DNS in `daemon.json` **or** with `dockerd --dns`, **never both** — dockerd refuses to start if the same directive appears in a flag *and* the file. Host‑network containers ignore the chroot's `resolv.conf`, so `daemon.json` is what actually gives them these resolvers.

---

## 12. Revert to stock

Keep the firmware set (**BL + AP + CP + CSC**) as a revert kit. Fully stock: Download Mode → Odin → load all four slots → **Start** (CSC wipes). This always works because you flash the *same or newer* version — anti‑rollback only blocks older. To undo just the kernel during testing, flash the stock `boot.img` alone.

---

## Footnotes — dead‑ends & gotchas

- **[A] Which configs break boot.** Bisecting one config per build/flash showed `SYSVIPC`, `USER_NS`, `BRIDGE_NETFILTER`, and cgroup controllers `CGROUP_PIDS`/`CGROUP_DEVICE` each cause an **instant, pre‑console** hang → hardware‑watchdog reset (captured from MediaTek's `/proc/last_kmsg`). The GKI base and build system are fine; only these specific options are toxic. Docker works without them: IPC via `POSIX_MQUEUE` (not `SYSVIPC`), device control via cgroup‑v2 eBPF (not `CGROUP_DEVICE`), networking via host mode.
- **[B] Anti‑rollback.** This unit's fuse reads `RP SWREV 17` (Download‑Mode screen). You may flash `A055FXXSHDZF1` or newer, never older — so a 4.19‑kernel LineageOS port (needs an older "Bit 6/7" base) would risk a brick and was ruled out.
- **[C] DNS under `su`.** Running `pkg`/`apt` as an app‑uid via `su` from adb fails name resolution (Android binds DNS to an app's network via fwmark). Fix: run inside the Termux app, or start sshd via Termux's `RUN_COMMAND` as root (see `device/service.d/start-sshd.sh`). A root **chroot** has working DNS.
- **[D] Why not bridge networking.** Docker's bridge driver must create iptables chains, but Android's netd fills the `filter` table with ~69 rules and `iptables-legacy` rewrites the whole table, choking on them. Running dockerd in its own netns fixes that, but the uplink then dies on Android's fwmark policy routing (forwarded packets miss the `iif lo` rules), and the userspace fixes (`slirp4netns`, `pasta`) both need `USER_NS`, which we can't enable. `--network host` sidesteps all of it.
- **[E] Build target.** The full `…_customer_modules_install` target fails on one incomplete vendor module (`gps_scp`). We build only the `…_kernel_aarch64.user` Image — a headless server needs none of the un‑buildable vendor modules, and stock modules keep loading thanks to the matched version string.
