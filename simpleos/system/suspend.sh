#!/bin/sh
# Sleep like stock Anbernic: pm-suspend / echo mem (S3 deep). Fake blank+park
# only when SSH tests hide /sys/power/state or the kernel has no `mem`.
set -eu

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
FLAG=/tmp/simpleos_suspended
SAVE=/tmp/simpleos_suspend_save
LOCKDIR=/tmp/simpleos_suspend.lockd
SLOG=/tmp/simpleos-suspend.log

# SIMPLEOS_NOPOWEROFF: lab only. Do not infer it from SSH_CONNECTION: the
# handheld must S3 and power off when SimpleOS is the default boot.
KEEP_WIFI=0
if [ -n "${SIMPLEOS_NOPOWEROFF:-}" ]; then
	KEEP_WIFI=1
fi

slog() { echo "$(date '+%H:%M:%S') $*" >> "$SLOG"; }

now_cs() { awk '{printf "%d", $1 * 100}' /proc/uptime; }

arm_power_ignore() {
	cs=${1:-200}
	now=$(now_cs)
	[ -n "$now" ] || now=0
	echo $((now + cs)) > /tmp/simpleos_power_ignore
}

freeze_ours() {
	for name in drastic hostemu simpleos; do
		pidof "$name" >/dev/null 2>&1 || continue
		kill -STOP $(pidof "$name") 2>/dev/null || true
	done
}

thaw_ours() {
	for name in drastic hostemu simpleos; do
		pidof "$name" >/dev/null 2>&1 || continue
		kill -CONT $(pidof "$name") 2>/dev/null || true
	done
}

# shellcheck source=charge-led.sh
. "$ROOT/system/charge-led.sh"

display_off() {
	# Blank via backlight only. Do not power off compositor outputs.
	mkdir -p "$SAVE"
	for b in /sys/class/backlight/*/brightness; do
		[ -e "$b" ] || continue
		cp "$b" "$SAVE/$(echo "$b" | tr / _)" 2>/dev/null || true
		echo 0 > "$b" 2>/dev/null || true
	done
	for p in /sys/class/backlight/*/bl_power; do
		[ -e "$p" ] || continue
		echo 4 > "$p" 2>/dev/null || true
	done
}

display_on() {
	for p in /sys/class/backlight/*/bl_power; do
		[ -e "$p" ] || continue
		echo 0 > "$p" 2>/dev/null || true
	done
	for b in /sys/class/backlight/*/brightness; do
		[ -e "$b" ] || continue
		saved="$SAVE/$(echo "$b" | tr / _)"
		if [ -f "$saved" ]; then
			cat "$saved" > "$b" 2>/dev/null || true
		fi
	done
}

mute_on() {
	# Silence via DAC 0%. Do not touch other mixers (this codec has no Master;
	# unmute/100% on leftover Pulse/ALSA paths is the post-sleep blast).
	command -v amixer >/dev/null 2>&1 && amixer -q -c 0 sset DAC 0% 2>/dev/null || true
	rm -f /tmp/simpleos_vol_applied
}

restore_volume_now() {
	# `force` so DAC is written even while $FLAG is still set.
	"$ROOT/system/apply-hw.sh" force >/dev/null 2>&1 || true
	"$ROOT/system/apply-hw.sh" force >/dev/null 2>&1 || true
}

restore_volume_watch() {
	# DraStic/SDL often re-opens ALSA after CONT and slams DAC to 100%.
	(
		"$ROOT/system/apply-hw.sh" apply >/dev/null 2>&1 || true
		i=0
		while [ "$i" -lt 40 ]; do
			sleep 0.25
			[ -f "$FLAG" ] && exit 0
			"$ROOT/system/apply-hw.sh" apply >/dev/null 2>&1 || true
			i=$((i + 1))
		done
	) &
}

wifi_off() {
	[ "$KEEP_WIFI" -eq 1 ] && return 0
	mkdir -p "$SAVE"
	: > "$SAVE/wifi_ifaces"
	# Only rfkill + link down. `connmanctl disable` / `nmcli radio off` persist.
	if command -v rfkill >/dev/null 2>&1; then
		rfkill block wifi >/dev/null 2>&1 || true
		rfkill block wlan >/dev/null 2>&1 || true
	fi
	for n in /sys/class/net/*; do
		[ -d "$n" ] || continue
		iface=${n##*/}
		case "$iface" in
			wl*|wlan*|mlan*)
				echo "$iface" >> "$SAVE/wifi_ifaces"
				ip link set "$iface" down >/dev/null 2>&1 || true
				;;
		esac
	done
}

wifi_wanted() {
	f="$ROOT/userdata/net.ini"
	[ -f "$f" ] || return 0
	grep -q '^wifi=0' "$f" && return 1
	return 0
}

wifi_on() {
	wifi_wanted || return 0
	if command -v rfkill >/dev/null 2>&1; then
		rfkill unblock wifi >/dev/null 2>&1 || true
		rfkill unblock wlan >/dev/null 2>&1 || true
	fi
	if [ -f "$SAVE/wifi_ifaces" ]; then
		while IFS= read -r iface; do
			[ -n "$iface" ] || continue
			ip link set "$iface" up >/dev/null 2>&1 || true
		done < "$SAVE/wifi_ifaces"
	else
		for n in /sys/class/net/*; do
			[ -d "$n" ] || continue
			iface=${n##*/}
			case "$iface" in
				wl*|wlan*|mlan*) ip link set "$iface" up >/dev/null 2>&1 || true ;;
			esac
		done
	fi
	command -v nmcli >/dev/null 2>&1 && nmcli radio wifi on >/dev/null 2>&1 || true
	command -v nmcli >/dev/null 2>&1 && nmcli networking on >/dev/null 2>&1 || true
	command -v connmanctl >/dev/null 2>&1 && connmanctl enable wifi >/dev/null 2>&1 || true
	if command -v systemctl >/dev/null 2>&1; then
		(
			for svc in connman NetworkManager iwd; do
				systemctl is-active --quiet "$svc" 2>/dev/null || continue
				systemctl restart "$svc" >/dev/null 2>&1 || true
			done
		) &
	fi
}

park_cores() {
	for x in /sys/devices/system/cpu/cpu*/online; do
		[ -w "$x" ] || continue
		case "$x" in
			*/cpu0/online) continue ;;
		esac
		echo 0 > "$x" 2>/dev/null || true
	done
}

unpark_cores() {
	for x in /sys/devices/system/cpu/cpu*/online; do
		[ -w "$x" ] && echo 1 > "$x" 2>/dev/null || true
	done
}

gov_save_and_powersave() {
	mkdir -p "$SAVE"
	for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
		[ -r "$g" ] || continue
		cat "$g" > "$SAVE/$(echo "$g" | tr / _)" 2>/dev/null || true
		echo powersave > "$g" 2>/dev/null || true
	done
	for g in /sys/class/devfreq/*/governor /sys/devices/platform/*/devfreq/*/governor; do
		[ -w "$g" ] || continue
		echo powersave > "$g" 2>/dev/null || true
	done
}

gov_restore() {
	if [ -f "$ROOT/system/apply-power.sh" ]; then
		sh "$ROOT/system/apply-power.sh" apply || true
		return 0
	fi
	for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
		[ -w "$g" ] || continue
		echo performance > "$g" 2>/dev/null || true
	done
}

peel_power_state() {
	n=0
	while grep -q ' /sys/power/state ' /proc/mounts 2>/dev/null; do
		umount /sys/power/state 2>/dev/null || break
		n=$((n + 1))
		[ "$n" -ge 12 ] && break
	done
}

can_s3() {
	[ "$KEEP_WIFI" -eq 1 ] && return 1
	[ -r /sys/power/state ] || return 1
	grep -q mem /sys/power/state 2>/dev/null
}

enter_s3() {
	peel_power_state
	if ! can_s3; then
		slog "no mem in /sys/power/state (keep_wifi=$KEEP_WIFI)"
		return 1
	fi
	if [ -w /sys/power/mem_sleep ]; then
		echo deep > /sys/power/mem_sleep 2>/dev/null || true
	fi
	# POWER is already up (powerd suspends on release). Brief settle so the
	# kernel does not treat the same tap as a wake.
	sleep 0.25
	sync
	slog "s3 mem"
	ok=0
	if command -v pm-suspend >/dev/null 2>&1; then
		pm-suspend >>"$SLOG" 2>&1 && ok=1
	fi
	if [ "$ok" -eq 0 ]; then
		echo -n mem > /sys/power/state || {
			slog "echo mem failed"
			return 1
		}
	fi
	slog "s3 woke"
	return 0
}

do_suspend() {
	[ -f "$FLAG" ] && return 0
	touch "$FLAG"
	arm_power_ignore 400
	slog "suspend keep_wifi=$KEEP_WIFI"
	display_off
	echo 0 > /sys/class/anbernic_misc/work_led 2>/dev/null || true
	charge_led_hold
	# STOP DraStic before S3 so it cannot play at codec-default 100%
	# between kernel wake and our DAC restore.
	freeze_ours
	mute_on
	if enter_s3; then
		do_resume
		return 0
	fi
	# Fallback: blank + park (SSH tests / missing S3).
	wifi_off
	charge_led_hold
	gov_save_and_powersave
	park_cores
	arm_power_ignore 400
}

do_resume() {
	[ -f "$FLAG" ] || return 0
	arm_power_ignore 400
	slog "resume"
	unpark_cores
	gov_restore
	display_on
	restore_volume_now
	rm -f "$FLAG"
	: > /tmp/simpleos_woke
	restore_volume_watch
	thaw_ours
	wifi_on
	command -v ledcontrol >/dev/null 2>&1 && ledcontrol default >/dev/null 2>&1 || true
	charge_led_release
	arm_power_ignore 400
}

src=${1:-power}
act=${2:-}

run_toggle() {
	case "$src" in
		lid)
			if [ "$act" = close ] || [ "$act" = on ]; then
				do_suspend
			else
				do_resume
			fi
			;;
		suspend|sleep)
			do_suspend
			;;
		resume|wake)
			do_resume
			;;
		power|*)
			if [ -f "$FLAG" ]; then
				do_resume
			else
				do_suspend
			fi
			;;
	esac
}

# BusyBox flock cannot lock a file descriptor; mkdir is portable.
n=0
while ! mkdir "$LOCKDIR" 2>/dev/null; do
	n=$((n + 1))
	[ "$n" -ge 80 ] && break
	sleep 0.05
done
run_toggle
rmdir "$LOCKDIR" 2>/dev/null || true
