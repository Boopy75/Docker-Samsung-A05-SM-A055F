#!/system/bin/sh
# Magisk late_start service  ->  install to /data/adb/service.d/charge-cap.sh
# Runs the battery charge-cap daemon on every boot.
{ until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done
  sleep 30
  nohup /system/bin/sh /data/adb/battery/charge-cap.sh >/dev/null 2>&1 &
} &
