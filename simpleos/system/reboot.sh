#!/bin/sh
# BusyBox `reboot` asks init; on this image rcK blanks the DSI panels and
# the restart never finishes (same class of bug as dummy poweroff).
# sysrq-b / reboot -f reset the SoC without walking rcK.
set -u

touch /tmp/simpleos_halt
touch /tmp/stopAPP.ini
rm -f "${SIMPLEOS_ROOT:-/mnt/mmc/simpleos}/userdata/command"
sync

echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
echo b > /proc/sysrq-trigger 2>/dev/null || true
if [ -e /dev/watchdog ]; then
	echo 1 > /dev/watchdog 2>/dev/null || true
fi
exec /sbin/reboot -f
