#!/system/bin/sh
# install-docker.sh  (phone, as ROOT)
# One-time: install Docker + Compose v2 into the Debian chroot.
# Prereq: `proot-distro install debian` has been run in Termux.
set -e

RD=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs
[ -d "$RD" ] || { echo "no debian rootfs; run: proot-distro install debian" >&2; exit 1; }

# REQUIRED — set to your network's DNS resolvers (same values as device/start-docker.sh).
# Leave DNS_SEARCH empty if you have no internal search domain.
DNS1=192.0.2.1          # primary resolver
DNS2=192.0.2.2          # secondary resolver (or repeat DNS1)
DNS_SEARCH=lan          # internal search domain, or leave blank
export DNS1 DNS2 DNS_SEARCH        # inherited through chroot for the daemon.json below

setenforce 0 2>/dev/null
mountpoint -q "$RD/proc" || mount -t proc proc "$RD/proc"
mountpoint -q "$RD/sys"  || mount -o bind /sys "$RD/sys"
mountpoint -q "$RD/dev"  || mount -o bind /dev "$RD/dev"
# resolvers for the chroot — needed so apt/wget resolve during install
RESOLV="nameserver $DNS1\nnameserver $DNS2\n"
[ -n "$DNS_SEARCH" ] && RESOLV="${RESOLV}search $DNS_SEARCH\n"
printf "$RESOLV" > "$RD/etc/resolv.conf"

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
  # container DNS = your resolvers. Host-net containers otherwise inherit Android/systemd
  # DNS; this pins them explicitly. Values come from the DNS* vars exported above.
  mkdir -p /etc/docker
  if [ -n "$DNS_SEARCH" ]; then
    printf "{\n  \"dns\": [\"%s\", \"%s\"],\n  \"dns-search\": [\"%s\"]\n}\n" "$DNS1" "$DNS2" "$DNS_SEARCH" > /etc/docker/daemon.json
  else
    printf "{\n  \"dns\": [\"%s\", \"%s\"]\n}\n" "$DNS1" "$DNS2" > /etc/docker/daemon.json
  fi
  echo "installed:"; dockerd --version; docker compose version
'
