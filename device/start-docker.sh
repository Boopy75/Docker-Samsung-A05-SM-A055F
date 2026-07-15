#!/system/bin/sh
# start-docker.sh  (phone, as ROOT)  ->  install to /data/adb/docker/start-docker.sh
# Idempotent: set up the chroot mounts and start dockerd in host-network mode.
# Each non-obvious step is required on Android — see comments and README "why each flag".

RD=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs
[ -d "$RD" ] || { echo "no debian rootfs"; exit 1; }

# REQUIRED — set to your network's DNS resolvers (leave DNS_SEARCH empty if you have none).
# These feed the chroot + Termux resolv.conf below; Docker's own container DNS lives in
# the chroot's /etc/docker/daemon.json (set by install-docker.sh — use the same values).
DNS1=192.0.2.1          # primary resolver   (e.g. your gateway / Pi-hole / internal DNS)
DNS2=192.0.2.2          # secondary resolver (or repeat DNS1)
DNS_SEARCH=lan          # internal search domain, or leave blank

setenforce 0 2>/dev/null                            # runc's privileged mounts need permissive
mountpoint -q "$RD"         || mount --bind "$RD" "$RD"          # make / a real mountpoint (runc)
mountpoint -q "$RD/proc"    || mount -t proc proc "$RD/proc"
mountpoint -q "$RD/sys"     || mount -o bind /sys "$RD/sys"
mountpoint -q "$RD/dev"     || mount -o bind /dev "$RD/dev"
mountpoint -q "$RD/dev/pts" || mount -o bind /dev/pts "$RD/dev/pts"
mkdir -p "$RD/sys/fs/cgroup"
mountpoint -q "$RD/sys/fs/cgroup" || mount -t cgroup2 none "$RD/sys/fs/cgroup"   # pure cgroup v2
mkdir -p "$RD/dev/net"; [ -e "$RD/dev/net/tun" ] || ln -s /dev/tun "$RD/dev/net/tun"
# pin the resolvers for the chroot AND for Termux (both persist on /data)
RESOLV="nameserver $DNS1\nnameserver $DNS2\n"
[ -n "$DNS_SEARCH" ] && RESOLV="${RESOLV}search $DNS_SEARCH\n"
printf "$RESOLV" > "$RD/etc/resolv.conf"
printf "$RESOLV" > /data/data/com.termux/files/usr/etc/resolv.conf 2>/dev/null

chroot "$RD" /bin/bash -c '
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TMPDIR=/tmp DOCKER_RAMDISK=1
  docker version >/dev/null 2>&1 && { echo "dockerd already running"; exit 0; }
  # DOCKER_RAMDISK=1 -> runc uses MS_MOVE+chroot instead of pivot_root (blocked here)
  # fuse-overlayfs   -> kernel overlay2 wont mount on /data
  # --iptables=false --bridge=none -> host-network mode (Android netd blocks bridge NAT)
  # container DNS (the LAN resolvers) comes from /etc/docker/daemon.json — see install-docker.sh
  DOCKER_RAMDISK=1 nohup dockerd --storage-driver=fuse-overlayfs \
      --iptables=false --bridge=none >/var/log/dockerd.log 2>&1 &
  for i in $(seq 1 25); do docker version >/dev/null 2>&1 && { echo "dockerd started"; exit 0; }; sleep 2; done
  echo "dockerd FAILED"; tail -6 /var/log/dockerd.log; exit 1
'
