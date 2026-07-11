#!/system/bin/sh
# install-docker.sh  (phone, as ROOT)
# One-time: install Docker + Compose v2 into the Debian chroot.
# Prereq: `proot-distro install debian` has been run in Termux.
set -e

RD=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs
[ -d "$RD" ] || { echo "no debian rootfs; run: proot-distro install debian" >&2; exit 1; }

setenforce 0 2>/dev/null
mountpoint -q "$RD/proc" || mount -t proc proc "$RD/proc"
mountpoint -q "$RD/sys"  || mount -o bind /sys "$RD/sys"
mountpoint -q "$RD/dev"  || mount -o bind /dev "$RD/dev"
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$RD/etc/resolv.conf"

chroot "$RD" /bin/bash -c '
  export PATH=/usr/sbin:/usr/bin:/sbin:/bin TMPDIR=/tmp DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
      docker.io fuse-overlayfs iptables iproute2 ca-certificates wget
  # Samsung kernel has no nftables -> force the legacy iptables backend
  update-alternatives --set iptables  /usr/sbin/iptables-legacy
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
  # Compose v2 (no Debian package): drop the official plugin binary in place
  mkdir -p /usr/local/lib/docker/cli-plugins
  wget -qO /usr/local/lib/docker/cli-plugins/docker-compose \
    https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  echo "installed:"; dockerd --version; docker compose version
'
