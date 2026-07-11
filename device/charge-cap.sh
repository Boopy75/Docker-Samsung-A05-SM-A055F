#!/system/bin/sh
# charge-cap.sh  (phone, as ROOT)  ->  install to /data/adb/battery/charge-cap.sh
# Hold the battery near 70% for 24/7-plugged longevity, via Samsung's batt_slate_mode node
# (1 = stop charging, 0 = resume). 60s poll with hysteresis.
CAP=70
RESUME=65
N=/sys/class/power_supply/battery/batt_slate_mode
C=/sys/class/power_supply/battery/capacity

# single instance
for p in $(pgrep -f charge-cap.sh); do [ "$p" != "$$" ] && kill "$p" 2>/dev/null; done

while :; do
  cap=$(cat "$C" 2>/dev/null); s=$(cat "$N" 2>/dev/null)
  case "$cap" in ''|*[!0-9]*) sleep 60; continue;; esac
  [ "$cap" -ge "$CAP" ]    && [ "$s" != 1 ] && echo 1 > "$N"   # stop charging
  [ "$cap" -le "$RESUME" ] && [ "$s" != 0 ] && echo 0 > "$N"   # resume charging
  sleep 60
done
