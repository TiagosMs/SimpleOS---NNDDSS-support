#!/bin/sh
# POWER / lid / volume via raw evdev (no evtest: piped evtest is block-buffered
# so button presses never arrived). Physical keys work even if started from SSH.
set -eu

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
export SIMPLEOS_ROOT="$ROOT"
LOG=/tmp/simpleos-powerd.log
: > "$LOG"

NOPOWER=0
[ -n "${SIMPLEOS_NOPOWEROFF:-}" ] && NOPOWER=1

# aarch64 input_event: timeval 16 + type 2 + code 2 + value 4 = 24
EV_KEY=1
EV_ABS=3
EV_SW=5
ABS_RZ=5
PWR_STICK=/tmp/simpleos_pwrstick
KEY_POWER=116
KEY_VOLUMEUP=115
KEY_VOLUMEDOWN=114
KEY_BRIGHTNESSUP=224
KEY_BRIGHTNESSDOWN=225
# Keyboard-style FN / menu
KEY_LEFTMETA=125
KEY_MENU=139
KEY_HOME=102
KEY_BACK=158
KEY_HOMEPAGE=172
KEY_OK=352
KEY_SELECT=353
KEY_GOTO=354
KEY_ESC=1
# Gamepad: MENU is BTN_MODE / KEY_HOME / KEY_BACK(158).
# RG DS evdev: L1=BTN_Y(308), R1=BTN_Z(309).
# BTN_TL(310)/BTN_TR(311) are SELECT/START on this pad, not shoulders.
BTN_Y=308
BTN_Z=309
BTN_TL=310
BTN_TR=311
BTN_TL2=312
BTN_MODE=316
FN=/tmp/simpleos_fn
SW_LID=0

log() { echo "$@" >> "$LOG"; }

now_cs() { awk '{printf "%d", $1 * 100}' /proc/uptime; }

# One physical press hits several evdev nodes (pad + adc-keys) and often
# kernel repeat as value=1. Latch until release; one step per click.
hold_set() { echo 1 > "/tmp/simpleos_hp_$1"; }
hold_clr() { rm -f "/tmp/simpleos_hp_$1"; }
hold_on() { [ -f "/tmp/simpleos_hp_$1" ]; }

stamp_cs() {
	now=$(now_cs)
	[ -n "$now" ] || now=0
	echo "$now" > "/tmp/simpleos_pdt_$1"
}

age_cs() {
	now=$(now_cs)
	[ -n "$now" ] || now=0
	prev=$(cat "/tmp/simpleos_pdt_$1" 2>/dev/null || echo 0)
	[ -n "$prev" ] || prev=0
	echo $((now - prev))
}

# Return 0 = apply this press. value=0 clears the latch.
edge_press() {
	tag=$1
	val=$2
	if [ "$val" = 0 ]; then
		hold_clr "$tag"
		return 1
	fi
	[ "$val" = 1 ] || return 1
	if hold_on "$tag"; then
		return 1
	fi
	hold_set "$tag"
	return 0
}

power_ignored() {
	until=$(cat /tmp/simpleos_power_ignore 2>/dev/null || echo 0)
	now=$(now_cs)
	[ -n "$now" ] || now=0
	[ -n "$until" ] || until=0
	[ "$now" -lt "$until" ]
}

arm_power_ignore() {
	cs=${1:-200}
	now=$(now_cs)
	[ -n "$now" ] || now=0
	echo $((now + cs)) > /tmp/simpleos_power_ignore
}

lockd=/tmp/simpleos_powerd.lockd
with_power_lock() {
	n=0
	while ! mkdir "$lockd" 2>/dev/null; do
		n=$((n + 1))
		[ "$n" -ge 80 ] && break
		sleep 0.05
	done
	"$@" || true
	rmdir "$lockd" 2>/dev/null || true
}

handle_power_locked() {
	value=$1
	if power_ignored; then
		log "power ignored debounce value=$value"
		return 0
	fi
	if [ -f /tmp/simpleos_suspended ]; then
		[ "$value" = 1 ] || return 0
		rm -f /tmp/simpleos_power_at
		arm_power_ignore 400
		log "power -> resume"
		sh "$ROOT/system/suspend.sh" resume || true
		arm_power_ignore 400
		return 0
	fi
	if [ "$value" = 1 ]; then
		echo "$(date +%s)" > /tmp/simpleos_power_at
		rm -f /tmp/simpleos_poweroff_sent
		(
			sleep 1
			[ -f /tmp/simpleos_power_at ] || exit 0
			[ "$NOPOWER" -eq 1 ] && exit 0
			touch /tmp/simpleos_poweroff_sent
			log "poweroff"
			killall -CONT drastic hostemu simpleos 2>/dev/null || true
			if [ -x "$ROOT/system/halt.sh" ]; then
				exec sh "$ROOT/system/halt.sh"
			fi
			exec /sbin/poweroff
		) &
	elif [ "$value" = 0 ]; then
		at=$(cat /tmp/simpleos_power_at 2>/dev/null || echo 0)
		[ -n "$at" ] || at=0
		rm -f /tmp/simpleos_power_at
		now=$(date +%s)
		if [ ! -f /tmp/simpleos_poweroff_sent ]; then
			if [ $((now - at)) -lt 1 ]; then
				arm_power_ignore 400
				log "power tap -> suspend"
				sh "$ROOT/system/suspend.sh" suspend || true
				arm_power_ignore 400
			fi
		fi
	fi
}

handle_power() {
	with_power_lock handle_power_locked "$1"
}

is_fn_key() {
	case "$1" in
		# 316=BTN_MODE (generic GUIDE). On RG DS the Anbernic MENU is
		# joystick button 8 = BTN_TL2(312), not BTN_MODE.
		"$KEY_LEFTMETA"|"$KEY_MENU"|"$BTN_MODE"|"$BTN_TL2")
			return 0
			;;
	esac
	return 1
}

is_overlay_key() {
	case "$1" in
		"$KEY_BACK"|"$KEY_HOME"|"$KEY_HOMEPAGE")
			return 0
			;;
	esac
	return 1
}

# Stock Anbernic kernel: hall is GPIO0 PC3 (gpio-19, ACTIVE_LOW) via
# anbernic_misc, not EV_SW. Closed = line low. Open lid reads hallkey=3.
lid_is_closed() {
	line=$(grep 'hall switch' /sys/kernel/debug/gpio 2>/dev/null || echo)
	case "$line" in
		*" in  lo"*|*" in lo"*)
			return 0
			;;
		*" in  hi"*|*" in hi"*)
			return 1
			;;
	esac
	hk=$(cat /sys/class/anbernic_misc/hallkey 2>/dev/null || echo)
	[ "$hk" = "0" ]
}

watch_hall() {
	log "watch hall"
	if [ -w /sys/devices/platform/anbernic_misc/power/wakeup ]; then
		echo enabled > /sys/devices/platform/anbernic_misc/power/wakeup 2>/dev/null || true
	fi
	last=
	stable=
	same=0
	while :; do
		if lid_is_closed; then
			cur=1
		else
			cur=0
		fi
		if [ "$cur" = "$stable" ]; then
			same=$((same + 1))
		else
			stable=$cur
			same=1
		fi
		if [ "$same" -ge 2 ]; then
			if [ -n "$last" ] && [ "$cur" != "$last" ]; then
				if [ "$cur" = 1 ]; then
					log "lid close"
					sh "$ROOT/system/suspend.sh" lid close || true
				else
					log "lid open"
					sh "$ROOT/system/suspend.sh" lid open || true
				fi
			fi
			last=$cur
		fi
		if [ -f /tmp/simpleos_need_vol ]; then
			rm -f /tmp/simpleos_need_vol
			sh "$ROOT/system/apply-hw.sh" apply >>/tmp/simpleos-hw.log 2>&1 &
		fi
		sleep 0.2
	done
}

handle() {
	type=$1
	code=$2
	value=$3
	role=${4:-}
	if [ "$type" = "$EV_SW" ]; then
		log "sw type=$type code=$code value=$value"
		# SW_LID is 0. Some kernels report the hall as another SW code.
		[ "$code" = "$SW_LID" ] || [ "$code" -le 2 ] || return 0
		closed=$value
		# GPIO_ACTIVE_LOW hall on RG DS sometimes reports 0 = cerniera chiusa.
		if [ "${SIMPLEOS_LID_INVERT:-0}" = "1" ]; then
			if [ "$value" -eq 0 ]; then closed=1; else closed=0; fi
		fi
		if [ "$closed" -ne 0 ]; then
			log "lid close sw"
			sh "$ROOT/system/suspend.sh" lid close || true
		else
			log "lid open sw"
			sh "$ROOT/system/suspend.sh" lid open || true
		fi
		return 0
	fi
	if [ "$type" = "$EV_ABS" ]; then
		[ "$code" = "$ABS_RZ" ] || return 0
		[ -f "$FN" ] || return 0
		[ -f /tmp/simpleos_suspended ] && return 0
		if [ "$value" -le -2000 ]; then
			[ -f "$PWR_STICK" ] && return 0
			echo up > "$PWR_STICK"
			echo 1 > /tmp/simpleos_fncombo
			log "power+ stick value=$value"
			sh "$ROOT/system/apply-power.sh" up >>/tmp/simpleos-hw.log 2>&1 &
		elif [ "$value" -ge 2000 ]; then
			[ -f "$PWR_STICK" ] && return 0
			echo down > "$PWR_STICK"
			echo 1 > /tmp/simpleos_fncombo
			log "power- stick value=$value"
			sh "$ROOT/system/apply-power.sh" down >>/tmp/simpleos-hw.log 2>&1 &
		elif [ "$value" -gt -800 ] && [ "$value" -lt 800 ]; then
			rm -f "$PWR_STICK"
		fi
		return 0
	fi
	[ "$type" = "$EV_KEY" ] || return 0
	# MENU also emits ESC on this board; stock UI treats it as "open menu".
	[ "$code" = "$KEY_ESC" ] && return 0
	log "key code=$code value=$value"
	if is_fn_key "$code"; then
		if [ "$value" = 1 ]; then
			echo 1 > "$FN"
			rm -f /tmp/simpleos_fncombo
			log "fn down code=$code"
		elif [ "$value" = 0 ]; then
			rm -f "$FN"
			rm -f /tmp/simpleos_fncombo
			rm -f "$PWR_STICK"
			hold_clr bril
			hold_clr brir
			log "fn up code=$code"
		fi
		return 0
	fi
	if is_overlay_key "$code"; then
		if [ "$value" = 0 ] && [ -f /tmp/simpleos_ingame ]; then
			age=$(age_cs ovl)
			if [ "$age" -ge 25 ]; then
				stamp_cs ovl
				echo 1 > /tmp/simpleos_menu_tap
				log "overlay tap code=$code"
			else
				log "overlay tap skip bounce code=$code"
			fi
		fi
		return 0
	fi
	if [ -f /tmp/simpleos_suspended ]; then
		case "$code" in
			"$KEY_VOLUMEUP"|"$KEY_VOLUMEDOWN"|"$KEY_BRIGHTNESSUP"|"$KEY_BRIGHTNESSDOWN"|"$BTN_Y"|"$BTN_Z"|"$BTN_TL2")
				return 0
				;;
		esac
	fi
	# Brightness: Anbernic + L1/R1 only (308/309). SELECT/START are 310/311.
	if [ -f "$FN" ]; then
		case "$code" in
			"$BTN_Y"|"$KEY_BRIGHTNESSDOWN")
				if [ "$value" = 0 ]; then
					hold_clr bril
					return 0
				fi
				if [ "$value" = 1 ]; then
					echo 1 > /tmp/simpleos_fncombo
					if hold_on bril; then return 0; fi
					age=$(age_cs bril)
					hold_set bril
					if [ "$age" -lt 20 ]; then return 0; fi
					stamp_cs bril
					log "bri- pad code=$code"
					sh "$ROOT/system/apply-hw.sh" "bri-" >>/tmp/simpleos-hw.log 2>&1 &
				fi
				return 0
				;;
			"$BTN_Z"|"$KEY_BRIGHTNESSUP")
				if [ "$value" = 0 ]; then
					hold_clr brir
					return 0
				fi
				if [ "$value" = 1 ]; then
					echo 1 > /tmp/simpleos_fncombo
					if hold_on brir; then return 0; fi
					age=$(age_cs brir)
					hold_set brir
					if [ "$age" -lt 20 ]; then return 0; fi
					stamp_cs brir
					log "bri+ pad code=$code"
					sh "$ROOT/system/apply-hw.sh" "bri+" >>/tmp/simpleos-hw.log 2>&1 &
				fi
				return 0
				;;
		esac
	fi
	if [ "$code" = "$KEY_VOLUMEUP" ] || [ "$code" = "$KEY_VOLUMEDOWN" ]; then
		if [ "$code" = "$KEY_VOLUMEUP" ]; then
			tag=volu
			act=vol+
		else
			tag=vold
			act=vol-
		fi
		edge_press "$tag" "$value" || return 0
		stamp_cs "$tag"
		log "$act role=$role"
		step=1
		[ "$act" = "vol-" ] && step=-1
		cur=$(cat /tmp/simpleos_vol_delta 2>/dev/null || echo 0)
		case "$cur" in
			''|*[!0-9+-]*|*[+-]*[+-]*) cur=0 ;;
		esac
		echo $((cur + step)) > /tmp/simpleos_vol_delta
		if mkdir /tmp/simpleos_vol_run 2>/dev/null; then
			sh "$ROOT/system/apply-hw.sh" volpump >>/tmp/simpleos-hw.log 2>&1 &
		fi
		return 0
	fi
	[ "$value" = 2 ] && return 0
	if [ "$code" = "$KEY_POWER" ]; then
		handle_power "$value"
	fi
}

watch_one() {
	dev=$1
	role=${2:-}
	log "watch $dev role=$role"
	while :; do
		raw=$(dd if="$dev" bs=24 count=1 2>/dev/null | od -An -tu2) || break
		[ -n "${raw:-}" ] || break
		# 12×u16; skip 8 timeval words; type=9 code=10; value=u16[10]+u16[11]<<16
		set -- $raw
		[ "$#" -ge 12 ] || continue
		type=${9}
		code=${10}
		value=$(( ${11} + ${12} * 65536 ))
		[ "$value" -gt 2147483647 ] && value=$((value - 4294967296))
		handle "$type" "$code" "$value" "$role" || true
	done
}

# Prefer a single pad + one power key. adc-keys clones volume; bt-powerkey
# clones POWER; watching both is why one tap became 5 steps.
pick_devs() {
	pad=
	pwr=
	adc=
	hall=
	for dev in /dev/input/event*; do
		[ -e "$dev" ] || continue
		name=""
		nfile="/sys/class/input/${dev##*/}/device/name"
		[ -r "$nfile" ] && name=$(cat "$nfile")
		echo "$name" | grep -qiE 'touch|accel|gyro|imu|goodix|gt9xx|haptic|rumble|dierct' && continue
		log "device $dev name=$name"
		echo "$name" | grep -qi 'ANBERNIC' && pad=$dev
		echo "$name" | grep -qiE 'rk805|pwrkey' && echo "$name" | grep -qvi 'bt-power' && [ -z "$pwr" ] && pwr=$dev
		echo "$name" | grep -qi 'adc-keys' && adc=$dev
		echo "$name" | grep -qiE 'hall|lid' && hall=$dev
	done
	[ -n "$pad" ] && echo "$pad pad"
	[ -n "$pwr" ] && [ "$pwr" != "$pad" ] && echo "$pwr pwr"
	# adc-keys clones VOLUME; a second watcher re-enters apply/amixer
	# on every UP tap. Pad already has 114/115 on RG DS.
	[ -n "$adc" ] && [ -z "$pad" ] && [ "$adc" != "$pwr" ] && echo "$adc adc"
	[ -n "$hall" ] && [ "$hall" != "$pad" ] && [ "$hall" != "$pwr" ] && [ "$hall" != "$adc" ] && echo "$hall hall"
	if [ -z "$pad" ] && [ -z "$pwr" ]; then
		for dev in /dev/input/event*; do
			[ -e "$dev" ] || continue
			name=""
			nfile="/sys/class/input/${dev##*/}/device/name"
			[ -r "$nfile" ] && name=$(cat "$nfile")
			echo "$name" | grep -qiE 'touch|accel|gyro|imu|goodix|gt9xx|haptic|rumble|adc|bt-power' && continue
			echo "$dev pad"
		done
	fi
}

log "powerd start nopower=$NOPOWER"
# Drop leftover watchers from a previous SSH restart (dd+od on every event*).
me=$$
for d in /proc/[0-9]*; do
	pid=${d#/proc/}
	[ "$pid" = "$me" ] && continue
	[ -r "$d/cmdline" ] || continue
	cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || true
	[ -n "$cmd" ] || continue
	case "$cmd" in
		*system/powerd.sh*)
			log "kill sibling powerd pid=$pid"
			kill -9 "$pid" 2>/dev/null || true
			;;
		*"dd if=/dev/input/event"*)
			kill -9 "$pid" 2>/dev/null || true
			;;
	esac
done
rm -f "$FN"
watch_hall &
devs=$(pick_devs)
if [ -n "$devs" ]; then
	echo "$devs" | while IFS= read -r line; do
		[ -n "$line" ] || continue
		set -- $line
		dev=$1
		role=${2:-}
		[ -n "$dev" ] || continue
		watch_one "$dev" "$role" &
	done
else
	log "no input devices"
fi
wait
