#!/bin/sh
# Anbernic kernel uses rk808_pm_power_off_dummy: BusyBox `poweroff` never
# sets RK817 DEV_OFF (SYS_CFG3 0xf4 bit0). Long POWER works because the
# PMIC pwrkey cuts rails in hardware. Stock muos still calls `poweroff`
# after flags; we do that too, then force the same PMIC bit via i2c.
set -u

touch /tmp/simpleos_halt
touch /tmp/shutdown.ini
touch /tmp/stopAPP.ini

# Long POWER from a game: remember to auto-launch last_game after power-on.
# Do this before killing processes — loop/home must not write boot_resume=0.
sos="${SIMPLEOS_ROOT:-/mnt/mmc/simpleos}"
export SIMPLEOS_ROOT="$sos"
[ -f "$sos/system/clock.sh" ] && sh "$sos/system/clock.sh" save || true
ini="$sos/userdata/settings.ini"
rom=$(sed -n 's/^last_game=//p' "$ini" 2>/dev/null | tail -n 1 | tr -d '\r')
base=${rom##*/}
allow=1
if [ -f "$sos/userdata/resume/$base" ]; then
	v=$(sed -n '1p' "$sos/userdata/resume/$base" | tr -d '\r')
	[ "$v" = "1" ] || allow=0
elif [ -f "$sos/userdata/noresume/$base" ]; then
	allow=0
else
	v=$(sed -n 's/^auto_resume=//p' "$ini" 2>/dev/null | tail -n 1 | tr -d '\r')
	[ -z "$v" ] && v=1
	[ "$v" = "1" ] || allow=0
fi
if [ -f "$ini" ] && [ -n "$base" ] && [ "$allow" = 1 ] \
	&& { pidof drastic >/dev/null 2>&1 || pidof hostemu >/dev/null 2>&1 || [ -f /tmp/simpleos_ingame ]; }; then
	if grep -q '^boot_resume=' "$ini" 2>/dev/null; then
		sed -i 's/^boot_resume=.*/boot_resume=1/' "$ini"
	else
		printf 'boot_resume=1\n' >> "$ini"
	fi
	sync
fi

echo 0 > /sys/class/leds/battery_full/brightness 2>/dev/null || true
echo 0 > /sys/class/leds/battery_charging/brightness 2>/dev/null || true
echo 0 > /sys/class/anbernic_misc/work_led 2>/dev/null || true
echo 1 > /sys/class/anbernic_misc/nds_pwrkey 2>/dev/null || true
rm -f "${SIMPLEOS_ROOT:-/mnt/mmc/simpleos}/userdata/command"
for b in /sys/class/backlight/*/brightness; do
	[ -e "$b" ] && echo 0 > "$b" 2>/dev/null || true
done

killall -9 autostart 2>/dev/null || true
killall -9 loadapp.sh 2>/dev/null || true
sync

# 0xf4 was 0x18 at idle (SLPPIN_RST). DEV_OFF is bit0. Keep slppin; only
# pulse DEV_OFF. Writing SLPPIN_DN (0x11) stuck across rails and the next
# power-on immediately powered off again.
if command -v i2cset >/dev/null 2>&1; then
	i2cset -y -f 0 0x20 0xf4 0x19 2>/dev/null || true
fi

echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
echo o > /proc/sysrq-trigger 2>/dev/null || true
exec /sbin/poweroff -f
