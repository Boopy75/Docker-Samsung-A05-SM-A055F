#!/system/bin/sh
# Magisk late_start service  ->  install to /data/adb/service.d/start-sshd.sh
# Start Termux's sshd on boot. Prefer Termux's RUN_COMMAND (runs sshd IN the app's network
# context, so ssh sessions get working DNS); fall back to a direct su-start so you're never
# locked out. Termux boot receivers are unreliable on Samsung, hence this root service.
{
  until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 3; done
  sleep 10
  PX=/data/data/com.termux/files/usr
  HT=/data/data/com.termux/files/home

  # Phase 1: RUN_COMMAND (in-app context -> DNS works). Retry ~90s.
  i=0
  while [ $i -lt 18 ]; do
    /system/bin/pgrep sshd >/dev/null 2>&1 && break
    am startservice --user 0 -n com.termux/com.termux.app.RunCommandService \
      -a com.termux.RUN_COMMAND \
      --es com.termux.RUN_COMMAND_PATH "$PX/bin/sshd" \
      --ez com.termux.RUN_COMMAND_BACKGROUND true >/dev/null 2>&1
    sleep 5; i=$((i+1))
  done

  # Phase 2: fallback su-start (sshd up even if RUN_COMMAND didn't fire; DNS may be limited)
  if ! /system/bin/pgrep sshd >/dev/null 2>&1; then
    U=$(stat -c %u "$HT")
    su "$U" -c "export HOME=$HT PREFIX=$PX LD_LIBRARY_PATH=$PX/lib \
      PATH=$PX/bin:/system/bin TMPDIR=$PX/tmp; sshd"
  fi
} &
