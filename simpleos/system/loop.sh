#!/bin/sh
# BusyBox: do not `set -e` — a failed killall must not abort the home↔emu loop.
set -u

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
export SIMPLEOS_ROOT="$ROOT"
CMDFILE="$ROOT/userdata/command"
LOOP=/tmp/simpleos_loop
# Sticky RK817 SYS_CFG3 after software halt.
command -v i2cset >/dev/null 2>&1 && i2cset -y -f 0 0x20 0xf4 0x18 2>/dev/null || true
touch "$LOOP"
LOG=/tmp/simpleos.log
DO_REBOOT=0
: >> "$LOG"
log() { echo "simpleos: $*" | tee -a "$LOG" >&2; }
# RK808 RTC does not advance while the unit is powered off. Restore the
# last stamp if the kernel clock looks unset, then let chronyd/NTP step
# once Wi-Fi is up. TZ so the home clock is local (default Europe/Rome).
if [ -z "${SIMPLEOS_HOST:-}" ] && [ -f "$ROOT/system/clock.sh" ]; then
	tz=$(sh "$ROOT/system/clock.sh" print-tz 2>/dev/null || echo Europe/Rome)
	[ -n "$tz" ] || tz=Europe/Rome
	export TZ="$tz"
	sh "$ROOT/system/clock.sh" restore || true
	sh "$ROOT/system/clock.sh" ntp >/dev/null 2>&1 &
fi
echo "simpleos: loop pid=$$ $(date)" >> "$LOG"

# 1 = next boot may auto-launch last_game (only if we powered off in-game).
resume_allowed() {
	rom=$1
	[ -n "$rom" ] || return 1
	base=${rom##*/}
	[ -n "$base" ] || return 1
	if [ -f "$ROOT/userdata/resume/$base" ]; then
		v=$(sed -n '1p' "$ROOT/userdata/resume/$base" | tr -d '\r')
		[ "$v" = "1" ]
		return $?
	fi
	[ -f "$ROOT/userdata/noresume/$base" ] && return 1
	v=$(sed -n 's/^auto_resume=//p' "$ROOT/userdata/settings.ini" 2>/dev/null | tail -n 1 | tr -d '\r')
	[ -z "$v" ] && v=1
	[ "$v" = "1" ]
}

autoload_wanted() {
	rom=$1
	[ -n "$rom" ] || return 1
	base=${rom##*/}
	[ -n "$base" ] || return 1
	if [ -f "$ROOT/userdata/autoload/$base" ]; then
		v=$(sed -n '1p' "$ROOT/userdata/autoload/$base" | tr -d '\r')
		[ "$v" = "0" ] && return 1
	else
		v=$(sed -n 's/^autoload=//p' "$ROOT/userdata/settings.ini" 2>/dev/null | tail -n 1 | tr -d '\r')
		[ "$v" = "1" ] || return 1
	fi
	stem=${base%.*}
	[ -n "$stem" ] || return 1
	for d in /mnt/vendor/deep/drastic_aarch64/savestates /mnt/vendor/deep/drastic64/savestates /tmp/save_nds/savestates; do
		[ -f "$d/${stem}_0.dss" ] && return 0
	done
	return 1
}

set_boot_resume() {
	val=$1
	ini="$ROOT/userdata/settings.ini"
	[ -f "$ini" ] || return 0
	if grep -q '^boot_resume=' "$ini" 2>/dev/null; then
		sed -i "s/^boot_resume=.*/boot_resume=$val/" "$ini"
	else
		printf 'boot_resume=%s\n' "$val" >> "$ini"
	fi
}

# Anbernic frontend: loadapp.sh loops on /mnt/vendor/ctrl/dmenu_ln
# (dmenu.bin / muos3.bin). Touching /tmp/stopAPP.ini is the stock
# "do not relaunch menu" flag. muos2.bin on this FW is unused.
STOCK_GUARD_PID=
STOCK_UI_NAMES="muos3.bin muos2.bin dmenu.bin MainUI anbernic anbernic_menu oga_events keymon thd triggerhappy input-event-daemon"
STOCK_CHMOD=/tmp/simpleos_stock_chmod
STOCK_STOP=/tmp/stopAPP.ini

pin_stock_bins() {
	touch "$STOCK_STOP"
	: > "$STOCK_CHMOD"
	: > "$ROOT/userdata/stock_chmod"
	for b in /mnt/vendor/bin/muos3.bin /mnt/vendor/bin/muos2.bin /mnt/vendor/bin/dmenu.bin /mnt/vendor/bin/MainUI /usr/bin/MainUI; do
		if [ -x "$b" ]; then
			chmod a-x "$b" 2>/dev/null || continue
			echo "$b" >> "$STOCK_CHMOD"
			echo "$b" >> "$ROOT/userdata/stock_chmod"
			log "chmod -x $b"
		fi
	done
}

unpin_stock_bins() {
	if [ -f "$STOCK_CHMOD" ]; then
		while IFS= read -r b; do
			[ -n "$b" ] && chmod a+x "$b" 2>/dev/null || true
		done < "$STOCK_CHMOD"
		rm -f "$STOCK_CHMOD"
	fi
	rm -f "$ROOT/userdata/stock_chmod"
	rm -f "$STOCK_STOP"
	if [ -x /mnt/vendor/ctrl/loadapp.sh ] && ! pgrep -f '/mnt/vendor/ctrl/loadapp.sh' >/dev/null 2>&1; then
		log "restart loadapp.sh"
		/mnt/vendor/ctrl/loadapp.sh >/dev/null 2>&1 &
	fi
}

stop_stock_ui() {
	[ -z "${SIMPLEOS_HOST:-}" ] || return 0
	touch "$STOCK_STOP"
	if [ ! -f /tmp/simpleos_stock_ps ]; then
		touch /tmp/simpleos_stock_ps
		ps -ef 2>/dev/null | grep -E 'muos|dmenu|loadapp|simpleos|weston' | tee -a "$LOG" >/dev/null || true
	fi
	for p in $STOCK_UI_NAMES; do
		if pidof "$p" >/dev/null 2>&1; then
			log "kill stock $p"
			killall -9 "$p" 2>/dev/null || true
		fi
	done
	pkill -9 -f '/mnt/vendor/bin/muos' 2>/dev/null || true
	pkill -9 -f '/mnt/vendor/bin/dmenu' 2>/dev/null || true
	pkill -9 -f '/mnt/vendor/ctrl/dmenu_ln' 2>/dev/null || true
}

resume_stock_ui() {
	unpin_stock_bins
}

start_stock_ui_guard() {
	(
		while [ -f "$LOOP" ]; do
			stop_stock_ui
			sleep 0.25
		done
	) &
	STOCK_GUARD_PID=$!
}

# A leftover loop.sh (SSH restart used to kill simpleos but not the loop)
# reaps DraStic and makes the next launch from home fail.
me=$$
for d in /proc/[0-9]*; do
	pid=${d#/proc/}
	[ "$pid" = "$me" ] && continue
	cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null) || continue
	case "$cmd" in
		*/system/loop.sh*|*/loop.sh|./loop.sh*|sh\ ./loop.sh*|sh\ loop.sh*)
			log "kill sibling loop pid=$pid"
			kill -9 "$pid" 2>/dev/null || true
			;;
	esac
done
# Orphan simpleos left by a sibling loop would flash a second home
# a moment after DraStic returns.
killall -9 simpleos 2>/dev/null || true

# Opt-in only: SIMPLEOS_NOPOWEROFF=1 for SSH lab tests. A normal boot (and
# an SSH session without that flag) must sleep and power off for real.
SSH_TEST=0
if [ -n "${SIMPLEOS_NOPOWEROFF:-}" ]; then
	SSH_TEST=1
fi

unblock_sleep() {
	n=0
	while grep -q ' /sys/power/state ' /proc/mounts 2>/dev/null; do
		umount /sys/power/state 2>/dev/null || break
		n=$((n + 1))
		[ "$n" -ge 12 ] && break
	done
}

block_sleep() {
	# Peel leftover SSH binds so a later APPS launch can still S3.
	unblock_sleep
	[ "$SSH_TEST" -eq 1 ] || return 0
	[ -e /sys/power/state ] || return 0
	: > /tmp/simpleos_powerstate
	mount --bind /tmp/simpleos_powerstate /sys/power/state 2>/dev/null || true
}

block_sleep
cleanup_loop() {
	rm -f "$LOOP"
	if [ -n "${STOCK_GUARD_PID:-}" ]; then
		kill "$STOCK_GUARD_PID" 2>/dev/null || true
		STOCK_GUARD_PID=
	fi
	# Do not restart dmenu while we are trying to halt.
	if [ ! -f /tmp/simpleos_halt ]; then
		resume_stock_ui
		unblock_sleep
	fi
}
trap 'cleanup_loop' EXIT INT TERM

# SSH has no compositor vars; offscreen + poweroff looked like
# "main.sh disconnects and the screen does nothing".
if [ -z "${SIMPLEOS_HOST:-}" ] && [ -f /etc/profile ]; then
	set +eu
	# shellcheck disable=SC1091
	. /etc/profile >/dev/null 2>&1 || true
	set +e
	set -u
	export PATH="$ROOT/system/bin:$PATH"
	export LD_LIBRARY_PATH="$ROOT/system/lib:${LD_LIBRARY_PATH:-}"
	# Anbernic: never stop weston (owns DRM / wayland-0).
	pin_stock_bins
	stop_stock_ui
	start_stock_ui_guard
fi

if [ -z "${SIMPLEOS_HOST:-}" ] && [ -z "${STOCK_GUARD_PID:-}" ]; then
	pin_stock_bins
	stop_stock_ui
	start_stock_ui_guard
fi

import_compositor_env() {
	pid=
	pid=$(pidof weston 2>/dev/null | awk '{print $1}') || true
	[ -n "${pid:-}" ] || pid=$(pidof labwc 2>/dev/null | awk '{print $1}') || true
	[ -n "${pid:-}" ] && [ -r "/proc/$pid/environ" ] || return 1
	while IFS= read -r line; do
		case "$line" in
			WAYLAND_DISPLAY=*|XDG_RUNTIME_DIR=*|SWAYSOCK=*|XDG_SESSION_TYPE=*)
				export "$line"
				;;
		esac
	done <<EOF
$(tr '\0' '\n' < "/proc/$pid/environ")
EOF
}

pick_wayland() {
	for dir in "${XDG_RUNTIME_DIR:-}" /run/user/0 /var/run /run /tmp; do
		[ -n "$dir" ] || continue
		for sock in "$dir"/wayland-*; do
			[ -S "$sock" ] || continue
			export XDG_RUNTIME_DIR="$dir"
			export WAYLAND_DISPLAY="${sock##*/}"
			return 0
		done
	done
	return 1
}

if [ -z "${SIMPLEOS_HOST:-}" ]; then
	import_compositor_env || true
	if [ "${SDL_VIDEODRIVER:-}" = "kmsdrm" ]; then
		unset SDL_VIDEODRIVER
	fi
	# Stale WAYLAND_DISPLAY from SSH (wayland-1 under /var/run) makes SDL
	# print "wayland not available" and fall through to offscreen.
	if pick_wayland; then
		export SDL_VIDEODRIVER=wayland
		echo "simpleos: Wayland $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" >&2
	else
		echo "simpleos: nessun socket Wayland (Weston deve restare acceso)" >&2
		unset SDL_VIDEODRIVER
	fi
	for d in \
		/mnt/vendor/deep/drastic_aarch64/libs \
		/mnt/vendor/deep/drastic_aarch64 \
		/mnt/vendor/deep/drastic64/libs
	do
		if [ -e "$d/libSDL2-2.0.so.0" ] || [ -e "$d/libSDL2-2.0.so" ]; then
			export LD_LIBRARY_PATH="$d:${LD_LIBRARY_PATH:-}"
			echo "simpleos: SDL da $d" >&2
			break
		fi
	done
	export SIMPLEOS_APPLY_HW=1
	export SIMPLEOS_LID_INVERT="${SIMPLEOS_LID_INVERT:-0}"
	# Restore saved volume/brightness (do not force 70%: that reset the panels
	# on every SimpleOS start). If a backlight is 0, apply-hw wakes both.
	if [ -x "$ROOT/system/apply-hw.sh" ]; then
		"$ROOT/system/apply-hw.sh" apply || true
	else
		for b in /sys/class/backlight/*/brightness; do
			[ -e "$b" ] || continue
			maxf="${b%brightness}max_brightness"
			max=255
			[ -r "$maxf" ] && max=$(cat "$maxf")
			[ "$max" -gt 1 ] || max=255
			cur=$(cat "$b" 2>/dev/null || echo 0)
			[ "$cur" -gt 0 ] || echo $((max * 7 / 10)) > "$b" 2>/dev/null || true
		done
	fi
fi

# CPU/GPU/DMC from the saved power mode (default: high / max clock).
if [ -x "$ROOT/system/apply-power.sh" ] || [ -f "$ROOT/system/apply-power.sh" ]; then
	sh "$ROOT/system/apply-power.sh" apply || true
else
	for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
		[ -w "$g" ] && echo performance > "$g" || true
	done
	for g in /sys/class/devfreq/*/governor /sys/devices/platform/*/devfreq/*/governor; do
		[ -w "$g" ] && echo performance > "$g" 2>/dev/null || true
	done
fi
# First install writes userdata/net.ini wifi=0 ssh=0. Missing file = leave stock as-is.
if [ -x "$ROOT/system/net.sh" ] || [ -f "$ROOT/system/net.sh" ]; then
	sh "$ROOT/system/net.sh" apply || true
fi

if command -v hangmon >/dev/null 2>&1 || [ -x "$ROOT/system/bin/hangmon" ]; then
	hangmon &
	HANGMON_PID=$!
else
	HANGMON_PID=
fi

POWERD_PID=
if [ -x "$ROOT/system/powerd.sh" ] || [ -f "$ROOT/system/powerd.sh" ]; then
	export SIMPLEOS_POWERMON=1
	export SIMPLEOS_HOOK=1
	sh "$ROOT/system/powerd.sh" &
	POWERD_PID=$!
fi

# Lid = DSI-1, touch = DSI-2. SDL uses these names in Video_open.
pick_dual_outputs() {
	TOP=DSI-1
	BOT=DSI-2
	export SIMPLEOS_OUT_TOP="$TOP"
	export SIMPLEOS_OUT_BOT="$BOT"
	export SDL_VIDEO_DISPLAY_PRIORITY="${TOP},${BOT}"
	echo "simpleos: output top=$TOP bot=$BOT" >&2
	echo "simpleos: output top=$TOP bot=$BOT" >> "$LOG" 2>/dev/null || true
}

wake_panels() {
	pick_dual_outputs
	for x in /sys/devices/system/cpu/cpu*/online; do
		[ -w "$x" ] && echo 1 > "$x" 2>/dev/null || true
	done
	killall -CONT drastic hostemu simpleos 2>/dev/null || true
	for p in /sys/class/backlight/*/bl_power; do
		[ -e "$p" ] && echo 0 > "$p" 2>/dev/null || true
	done
	restore_hw force
}

restore_hw() {
	[ -f "$ROOT/system/apply-hw.sh" ] && sh "$ROOT/system/apply-hw.sh" "${1:-apply}" || true
}

# DraStic / PipeWire often reset sink volume after the process starts.
# Never use `force` here: it ignores the sleep flag and wakes the panels.
restore_hw_after_emu() {
	(
		for t in 0.4 0.8 1.5 3 6; do
			sleep "$t"
			[ -f /tmp/simpleos_suspended ] && exit 0
			restore_hw apply
		done
	) &
}

EMU_FAIL=0
BOOT_RESUME=1

emu_running() {
	pidof drastic >/dev/null 2>&1 && return 0
	pidof hostemu >/dev/null 2>&1 && return 0
	pidof nnddss >/dev/null 2>&1 && return 0
	return 1
}

# DraStic / NNDDSS must be fully gone before the next start, otherwise
# the second launch from home fails (SDL/Wayland still busy).
stop_emu() {
	killall -TERM drastic hostemu nnddss 2>/dev/null || true
	n=0
	while [ "$n" -lt 20 ]; do
		emu_running || break
		sleep 0.1
		n=$((n + 1))
	done
	killall -9 drastic hostemu nnddss 2>/dev/null || true
	n=0
	while [ "$n" -lt 15 ]; do
		emu_running || break
		sleep 0.1
		n=$((n + 1))
	done
	if emu_running; then
		log "warning: emu ancora vivo dopo stop"
	fi
}

# Home SDL/Wayland surfaces must drop before DraStic opens, or the lid
# keeps a leftover rectangle and the bottom panel stays black.
# After run_simpleos returns the UI is already gone; any leftover simpleos
# is an older instance (stale ROM list). Kill it immediately — waiting
# would flash that old home for up to ~2s.
wait_home_gone() {
	if pidof simpleos >/dev/null 2>&1; then
		log "kill leftover simpleos"
		killall -9 simpleos 2>/dev/null || true
	fi
	sleep 0.08
}

launch_rom() {
	rom=$1
	EMU_FAIL=0
	rm -f /tmp/simpleos_autoload
	if [ "${2:-0}" = "1" ]; then
		touch /tmp/simpleos_autoload
		log "autoload savestate $rom"
	fi
	if [ -f /tmp/simpleos_suspended ]; then
		sh "$ROOT/system/suspend.sh" resume >/dev/null 2>&1 || true
	fi
	rm -f /tmp/simpleos_suspended
	stop_emu
	wake_panels
	sleep 0.35
	restore_hw_after_emu
	touch /tmp/simpleos_ingame
	log "avvio DraStic $rom"
	"$ROOT/system/run.sh" "$rom" || EMU_FAIL=$?
	log "DraStic uscito code=${EMU_FAIL:-0}"
	stop_emu
	if [ "$EMU_FAIL" -ne 0 ]; then
		echo "simpleos: DraStic uscito $EMU_FAIL (139=segfault), menu" >&2
	fi
	restore_hw force
	# Long POWER kills DraStic before halt finishes. Keep last_game for
	# the next boot; home UI clears the flag when it actually starts.
	if [ -f /tmp/simpleos_halt ] || [ -f /tmp/simpleos_poweroff_sent ]; then
		if resume_allowed "$rom"; then
			set_boot_resume 1
		else
			set_boot_resume 0
		fi
		return
	fi
	rm -f /tmp/simpleos_ingame
}

run_simpleos() {
	rc=0
	if [ -f /tmp/simpleos_halt ] || [ -f /tmp/simpleos_poweroff_sent ]; then
		return 2
	fi
	# Showing home: next boot must not auto-launch unless we enter a game.
	set_boot_resume 0
	rm -f /tmp/simpleos_ingame
	killall -9 simpleos 2>/dev/null || true
	stop_stock_ui
	pick_dual_outputs
	restore_hw force
	export SDL_TOUCH_MOUSE_EVENTS=0
	export SDL_MOUSE_TOUCH_EVENTS=0
	if [ -e /sys/class/anbernic_misc/tpctrl ]; then
		echo 0 > /sys/class/anbernic_misc/tpctrl 2>/dev/null || true
	fi
	"$ROOT/system/bin/simpleos" || rc=$?
	return "$rc"
}

if [ -z "${SIMPLEOS_HOST:-}" ]; then
	pick_dual_outputs
fi

while [ -f "$LOOP" ]; do
	[ -f "$ROOT/system/clock.sh" ] && sh "$ROOT/system/clock.sh" save || true
	if [ -f /tmp/simpleos_halt ] || [ -f /tmp/simpleos_poweroff_sent ]; then
		log "halt in corso, esco dal loop"
		rm -f "$LOOP"
		break
	fi
	cmd="home"
	rom=""
	if [ -f "$CMDFILE" ]; then
		cmd=$(sed -n '1p' "$CMDFILE" | tr -d '\r' || true)
		rom=$(sed -n '2p' "$CMDFILE" | tr -d '\r' || true)
		rm -f "$CMDFILE"
		# Leftover from last halt (simpleos writes command then returns 2
		# before the poweroff branch can unlink it). Must not halt again.
		if [ "$BOOT_RESUME" -eq 1 ]; then
			case "$cmd" in
				poweroff|reboot)
					log "ignore stale ipc $cmd"
					cmd="home"
					rom=""
					;;
			esac
		fi
		[ "$cmd" = "home" ] || log "ipc cmd=$cmd rom=$rom"
	elif [ "$BOOT_RESUME" -eq 1 ] && [ "$SSH_TEST" -eq 0 ] && [ -z "${SIMPLEOS_NORESUME:-}" ] && [ -f "$ROOT/userdata/settings.ini" ]; then
		# Auto-resume only if the last shutdown happened in-game.
		want=$(sed -n 's/^boot_resume=//p' "$ROOT/userdata/settings.ini" | tail -n 1 | tr -d '\r')
		rom=$(sed -n 's/^last_game=//p' "$ROOT/userdata/settings.ini" | tail -n 1 | tr -d '\r')
		if [ "$want" = "1" ] && [ -n "$rom" ] && [ -f "$rom" ] && resume_allowed "$rom"; then
			cmd="launch"
			log "auto-resume boot $rom"
		fi
	fi
	BOOT_RESUME=0
	EMU_FAIL=0

	case "$cmd" in
		launch|reset)
			touch /tmp/simpleos_splashed
			unset SIMPLEOS_SPLASH
			if [ -n "$rom" ] && [ -f "$rom" ]; then
				wait_home_gone
				want_al=0
				[ "$cmd" = "launch" ] && autoload_wanted "$rom" && want_al=1
				launch_rom "$rom" "$want_al"
			else
				log "launch senza ROM valida ($rom)"
				run_simpleos || true
			fi
			;;
		poweroff)
			rm -f "$LOOP" "$CMDFILE"
			break
			;;
		reboot)
			rm -f "$LOOP" "$CMDFILE"
			DO_REBOOT=1
			break
			;;
		home|*)
			if [ ! -f /tmp/simpleos_splashed ]; then
				export SIMPLEOS_SPLASH=1
			else
				unset SIMPLEOS_SPLASH
			fi
			rc=0
			run_simpleos || rc=$?
			if [ "$rc" -eq 2 ]; then
				rm -f "$LOOP" "$CMDFILE"
				break
			fi
			if [ "$rc" -eq 3 ]; then
				DO_REBOOT=1
				rm -f "$LOOP" "$CMDFILE"
				break
			fi
			;;
	esac
	sync
done

if [ -n "${HANGMON_PID:-}" ]; then
	kill "$HANGMON_PID" 2>/dev/null || true
fi
if [ -n "${POWERD_PID:-}" ]; then
	pkill -P "$POWERD_PID" 2>/dev/null || true
	kill "$POWERD_PID" 2>/dev/null || true
fi

if [ "${SIMPLEOS_HOST:-}" ] || [ "$SSH_TEST" -eq 1 ]; then
	rm -f "$LOOP"
	if [ -n "${STOCK_GUARD_PID:-}" ]; then
		kill "$STOCK_GUARD_PID" 2>/dev/null || true
		STOCK_GUARD_PID=
	fi
	resume_stock_ui
	unblock_sleep
	exit 0
fi

unblock_sleep
# Let BusyBox init deliver SIGTERM; do not ignore it (that blocked halt).
touch /tmp/simpleos_halt
trap - EXIT INT TERM
if [ "$DO_REBOOT" -eq 1 ]; then
	if [ -x "$ROOT/system/reboot.sh" ]; then
		exec sh "$ROOT/system/reboot.sh"
	fi
	sync
	echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
	echo b > /proc/sysrq-trigger 2>/dev/null || true
	exec /sbin/reboot -f
fi
if [ -x "$ROOT/system/halt.sh" ]; then
	exec sh "$ROOT/system/halt.sh"
fi
exec /sbin/poweroff
