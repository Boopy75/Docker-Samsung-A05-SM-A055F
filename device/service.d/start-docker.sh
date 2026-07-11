#!/system/bin/sh
# Magisk late_start service  ->  install to /data/adb/service.d/start-docker.sh
# Starts Docker on every boot (runs as root, after the filesystem/Termux settle).
{ until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 3; done
  sleep 20
  /system/bin/sh /data/adb/docker/start-docker.sh >> /data/adb/docker/boot.log 2>&1
} &
