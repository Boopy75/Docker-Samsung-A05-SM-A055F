#!/data/data/com.termux/files/usr/bin/bash
# docker-wrapper.sh  ->  install to /data/data/com.termux/files/usr/bin/docker
#                        (chown to the Termux uid, chmod 755)
# Lets the SSH user run `docker ...` / `docker compose ...` transparently: elevates with
# Magisk su, enters the Debian chroot, and forwards all args (safely quoted) to the real CLI.
RD=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/debian/rootfs
Q=""
for a in "$@"; do Q="$Q $(printf '%q' "$a")"; done
exec su -c "chroot $RD /usr/bin/env \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  TERM=${TERM:-xterm} /usr/bin/docker$Q"
