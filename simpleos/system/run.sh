#!/bin/sh
set -u

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
ROM=${1:-}
EMULOG=/tmp/simpleos-emu.log

if [ -z "$ROM" ] || [ ! -f "$ROM" ]; then
	echo "simpleos: missing ROM" >&2
	exit 1
fi

# === SimpleOS Special Triggers (Apps & Stock Switch) ===
case "$ROM" in
	*Voltar_Stock*|*voltar_stock*)
		echo "Alternando para sistema Anbernic original..." >> "$EMULOG"
		touch "$ROOT/userdata/boot_stock"
		reboot
		exit 0
		;;
	*NNDDSS*|*nnddss*)
		echo "Iniciando emulador NNDDSS..." >> "$EMULOG"
		if [ -f /mnt/mmc/Roms/APPS/NNDDSS-RGDS.sh ]; then
			sh /mnt/mmc/Roms/APPS/NNDDSS-RGDS.sh
			exit $?
		elif [ -x /mnt/vendor/deep/nnddss/nnddss ]; then
			cd /mnt/vendor/deep/nnddss || exit 1
			export LD_LIBRARY_PATH="/mnt/vendor/deep/nnddss/lib:${LD_LIBRARY_PATH:-}"
			./nnddss --root /mnt/vendor/deep/nnddss --roms /mnt/mmc/Roms/NDS
			exit $?
		fi
		;;
esac

echo "simpleos: run $(date) rom=$ROM" >> "$EMULOG" 2>/dev/null || true
if [ -z "${TZ:-}" ] && [ -f "$ROOT/system/clock.sh" ]; then
	TZ=$(sh "$ROOT/system/clock.sh" print-tz 2>/dev/null || echo Europe/Rome)
	export TZ
fi

# libdrastouch converts SDL fingers to mouse. Do not also emit mouse from touch.
export SDL_TOUCH_MOUSE_EVENTS=0
export SDL_MOUSE_TOUCH_EVENTS=0

# Weston/Sway own DRM. kmsdrm after /etc/profile leaves both screens black.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -S /var/run/wayland-0 ]; then
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"
	export WAYLAND_DISPLAY=wayland-0
fi
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
	export SDL_VIDEODRIVER=wayland
	# SDL Wayland default is triple-buffer (+1 frame after commit).
	# 2.32 honors SDL_VIDEO_DOUBLE_BUFFER: flip, then wait. One change.
	# SIMPLEOS_DBLBUF=0 keeps the old triple-buffer for A/B.
	if [ "${SIMPLEOS_DBLBUF:-1}" != "0" ]; then
		export SDL_VIDEO_DOUBLE_BUFFER=1
	fi
fi
if [ -d /mnt/vendor/deep/drastic_aarch64/libs ]; then
	export LD_LIBRARY_PATH="/mnt/vendor/deep/drastic_aarch64/libs:${LD_LIBRARY_PATH:-}"
fi

find_drastic() {
	for c in \
		${DRASTIC_BIN:-} \
		/mnt/vendor/deep/drastic_aarch64/drastic \
		/mnt/vendor/deep/drastic64/drastic \
		/mnt/vendor/deep/drastic64/drastic_oga \
		/mnt/vendor/deep/drastic_aarch64/launch.sh \
		/mnt/vendor/deep/drastic64/launch.sh \
		"$ROOT/system/drastic/drastic"
	do
		[ -n "${c:-}" ] && [ -x "$c" ] && { echo "$c"; return 0; }
	done
	return 1
}

EMU=$(find_drastic || true)
HOOK="$ROOT/system/lib/libsimplehook.so"

if [ -z "$EMU" ]; then
	if [ -x "$ROOT/system/bin/hostemu" ]; then
		EMU="$ROOT/system/bin/hostemu"
	else
		echo "simpleos: DraStic not found (atteso /mnt/vendor/deep/drastic_aarch64/drastic)" >&2
		exit 1
	fi
fi

if [ -z "${DRASTIC_HOME:-}" ]; then
	if [ -d /mnt/vendor/deep/drastic_aarch64 ]; then
		DRASTIC_HOME=/mnt/vendor/deep/drastic_aarch64
	elif [ -d /mnt/vendor/deep/drastic64 ]; then
		DRASTIC_HOME=/mnt/vendor/deep/drastic64
	fi
fi
export HOME="${DRASTIC_HOME:-$(dirname "$EMU")}"
mkdir -p "$HOME" "$HOME/config" "$ROOT/userdata"

# Overlay SAVE/LOAD/QUIT/FF use virtual joystick 16/17/18/19 (DraStic
# codes 1024+N). Keyboard F5/F7 never reach this DraStic build.
# Anbernic: do not rewrite stock cfg until the hook overlay is on — a bad
# awk pass made DraStic exit before the ROM window.
CFG_LIVE="$HOME/config/drastic.cfg"
if [ ! -f "$CFG_LIVE" ] && [ -f "$ROOT/system/drastic.cfg" ]; then
	cp "$ROOT/system/drastic.cfg" "$CFG_LIVE"
fi
HIRES_3D=0
if [ -f "$ROOT/userdata/settings.ini" ]; then
	HIRES_3D=$(awk -F= '/^hires_3d=/{v=$2} END{v+=0; print v}' "$ROOT/userdata/settings.ini" 2>/dev/null || echo 0)
	case "$HIRES_3D" in
		1) ;;
		*) HIRES_3D=0 ;;
	esac
fi
if [ -f "$CFG_LIVE" ]; then
	awk -v hires="$HIRES_3D" '
		BEGIN {
			want["controls_a[CONTROL_INDEX_MENU]"] = "65535"
			want["controls_b[CONTROL_INDEX_MENU]"] = "65535"
			want["controls_a[CONTROL_INDEX_START]"] = "1031"
			want["controls_b[CONTROL_INDEX_START]"] = "1031"
			want["controls_a[CONTROL_INDEX_SELECT]"] = "1030"
			want["controls_b[CONTROL_INDEX_SELECT]"] = "1030"
			want["controls_a[CONTROL_INDEX_SAVE_STATE]"] = "1040"
			want["controls_a[CONTROL_INDEX_LOAD_STATE]"] = "1041"
			want["controls_a[CONTROL_INDEX_QUIT]"] = "1042"
			want["controls_a[CONTROL_INDEX_FAST_FORWARD]"] = "1033"
			want["controls_a[CONTROL_INDEX_FAKE_MICROPHONE]"] = "1036"
			want["controls_b[CONTROL_INDEX_SAVE_STATE]"] = "1040"
			want["controls_b[CONTROL_INDEX_LOAD_STATE]"] = "1041"
			want["controls_b[CONTROL_INDEX_QUIT]"] = "1042"
			want["controls_b[CONTROL_INDEX_FAST_FORWARD]"] = "1033"
			want["controls_b[CONTROL_INDEX_FAKE_MICROPHONE]"] = "1036"
			want["controls_a[CONTROL_INDEX_TOUCH_CURSOR_UP]"] = "65535"
			want["controls_a[CONTROL_INDEX_TOUCH_CURSOR_DOWN]"] = "65535"
			want["controls_a[CONTROL_INDEX_TOUCH_CURSOR_LEFT]"] = "65535"
			want["controls_a[CONTROL_INDEX_TOUCH_CURSOR_RIGHT]"] = "65535"
			want["controls_a[CONTROL_INDEX_TOUCH_CURSOR_PRESS]"] = "65535"
			want["controls_b[CONTROL_INDEX_TOUCH_CURSOR_UP]"] = "65535"
			want["controls_b[CONTROL_INDEX_TOUCH_CURSOR_DOWN]"] = "65535"
			want["controls_b[CONTROL_INDEX_TOUCH_CURSOR_LEFT]"] = "65535"
			want["controls_b[CONTROL_INDEX_TOUCH_CURSOR_RIGHT]"] = "65535"
			want["controls_b[CONTROL_INDEX_TOUCH_CURSOR_PRESS]"] = "65535"
			want["mirror_touch"] = "0"
			want["threaded_3d"] = "1"
			want["hires_3d"] = hires
			want["disable_edge_marking"] = "1"
			want["interframe_blend"] = "0"
			want["screen_wait_for_vsync"] = "0"
		}
		{
			key = $0
			sub(/\r/, "", key)
			sub(/ = .*/, "", key)
			sub(/=.*/, "", key)
			gsub(/[ \t]+$/, "", key)
			if (key in want) {
				print key " = " want[key]
				seen[key] = 1
				next
			}
			print
		}
		END {
			for (k in want) if (!seen[k]) print k " = " want[k]
		}
	' "$CFG_LIVE" > "$CFG_LIVE.sos" && mv "$CFG_LIVE.sos" "$CFG_LIVE"
	echo "simpleos: overlay SAVE/LOAD/QUIT/FF/MIC joy 16/17/18/9/12 hires_3d=$HIRES_3D on $CFG_LIVE" >> /tmp/simpleos.log 2>/dev/null || true
fi

# Re-apply saved volume after DraStic opens the audio sink.
# Do not use `force`: it would cancel an in-progress suspend.
(
	for t in 0.4 1 2 4 7; do
		sleep "$t"
		[ -f /tmp/simpleos_suspended ] && exit 0
		sh "$ROOT/system/apply-hw.sh" apply >/dev/null 2>&1 || true
	done
) &

# Overlay on unless SIMPLEOS_HOOK=0.
# Vendor libdrastouch does window span + finger→mouse. Keep it.
# SIMPLEOS_DRASTOUCH=0 drops it (broken layout/stylus on Weston).
# Our stylus/fill stay off unless explicitly enabled.
USE_HOOK=0
if [ "${SIMPLEOS_HOOK:-1}" != "0" ] && [ -f "$HOOK" ]; then
	USE_HOOK=1
fi
USE_DRASTOUCH=1
if [ "${SIMPLEOS_DRASTOUCH:-1}" = "0" ]; then
	USE_DRASTOUCH=0
fi
: "${SIMPLEOS_STYLUS:=0}"
: "${SIMPLEOS_INTEGER:=0}"
: "${SIMPLEOS_LATENCY:=1}"
export SIMPLEOS_STYLUS SIMPLEOS_INTEGER SIMPLEOS_LATENCY

PRELOAD=""
if [ "$USE_DRASTOUCH" = "1" ]; then
	if [ -f /usr/lib/libdrastouch.so ]; then
		PRELOAD=/usr/lib/libdrastouch.so
	elif [ -f /mnt/vendor/deep/drastic_aarch64/libs/libdrastouch.so ]; then
		PRELOAD=/mnt/vendor/deep/drastic_aarch64/libs/libdrastouch.so
	elif [ -f /mnt/vendor/deep/drastic64/libs/libdrastouch.so ]; then
		PRELOAD=/mnt/vendor/deep/drastic64/libs/libdrastouch.so
	fi
fi
if [ "$USE_HOOK" = "1" ]; then
	PRELOAD="$HOOK${PRELOAD:+:$PRELOAD}"
	echo "simpleos: DraStic + hook $HOOK drastouch=$USE_DRASTOUCH" >&2
	echo "simpleos: DraStic + hook $HOOK drastouch=$USE_DRASTOUCH" >> /tmp/simpleos.log 2>/dev/null || true
else
	echo "simpleos: DraStic $EMU (hook off) drastouch=$USE_DRASTOUCH" >&2
fi
if [ -n "$PRELOAD" ]; then
	export LD_PRELOAD="$PRELOAD${LD_PRELOAD:+:$LD_PRELOAD}"
fi

start_ndsctrl() {
	if pgrep -f ndsCtrl.dge >/dev/null 2>&1; then
		return 0
	fi
	if [ -x /mnt/mmc/ndsCtrl.dge ]; then
		/mnt/mmc/ndsCtrl.dge >/dev/null 2>&1 &
	elif [ -x /mnt/vendor/bin/ndsCtrl.dge ]; then
		/mnt/vendor/bin/ndsCtrl.dge >/dev/null 2>&1 &
	fi
}

# Stock launch.sh does `mydir=$(dirname $0)`. Never copy it to /tmp.
prepare_anbernic() {
	dir=$1
	export HOME="$dir"
	export PATH="$dir:${PATH:-}"
	if [ -d "$dir/libs" ]; then
		export LD_LIBRARY_PATH="$dir/libs:${LD_LIBRARY_PATH:-}"
	fi
	if [ -e /sys/class/anbernic_misc/tpctrl ]; then
		echo 0 > /sys/class/anbernic_misc/tpctrl 2>/dev/null || true
	fi
	start_ndsctrl
}

case "$EMU" in
	*launch.sh)
		EMUDIR=$(CDPATH= cd -- "$(dirname "$EMU")" && pwd)
		if [ -x "$EMUDIR/drastic" ]; then
			EMU="$EMUDIR/drastic"
		elif [ -x "$EMUDIR/drastic_oga" ]; then
			EMU="$EMUDIR/drastic_oga"
		fi
		;;
esac

EMUDIR=$(CDPATH= cd -- "$(dirname "$EMU")" && pwd)
case "$EMUDIR" in
	*/drastic_aarch64|*/drastic64)
		prepare_anbernic "$EMUDIR"
		TOUCH="$EMUDIR/libs/libdrastouch.so"
		if [ "$USE_DRASTOUCH" = "1" ] && [ -f "$TOUCH" ]; then
			if [ "$USE_HOOK" = "1" ] && [ -f "$HOOK" ]; then
				export LD_PRELOAD="$HOOK:$TOUCH"
			else
				export LD_PRELOAD="$TOUCH"
			fi
		fi
		# Client-side Wayland async present. Off: SIMPLEOS_TEAR=0.
		TEAR="$ROOT/system/lib/libtearing.so"
		if [ "${SIMPLEOS_TEAR:-1}" != "0" ] && [ -f "$TEAR" ]; then
			export LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}$TEAR"
		fi
		echo "simpleos: Anbernic $EMU WAYLAND=${WAYLAND_DISPLAY:-} SDL=${SDL_VIDEODRIVER:-}" >&2
		echo "simpleos: Anbernic $EMU rom=$ROM" >> /tmp/simpleos.log 2>/dev/null || true
		;;
esac

CFG_SRC="$ROOT/system/drastic.cfg"
CFG_DST="$HOME/config/drastic.cfg"
if [ -f "$CFG_SRC" ]; then
	mkdir -p "$HOME/config"
	if [ ! -f "$CFG_DST" ]; then
		cp "$CFG_SRC" "$CFG_DST"
	fi
fi

cd "$HOME"
# Re-apply the chosen power mode (do not force GPU performance).
if [ -f "$ROOT/system/apply-power.sh" ]; then
	sh "$ROOT/system/apply-power.sh" apply || true
fi
echo "simpleos: exec $EMU $ROM cwd=$PWD preload=${LD_PRELOAD:-} dblbuf=${SDL_VIDEO_DOUBLE_BUFFER:-0} tear=${SIMPLEOS_TEAR:-1}" >> "$EMULOG" 2>/dev/null || true
touch /tmp/simpleos_ingame
rm -f /tmp/simpleos_menu_tap /tmp/simpleos_osd
RA_WPID=
if [ -f "$ROOT/userdata/ra-session" ] && [ -f "$ROOT/system/ra_http.py" ]; then
	if command -v python3 >/dev/null 2>&1; then
		python3 "$ROOT/system/ra_http.py" worker "$ROOT" >> /tmp/simpleos.log 2>&1 &
		RA_WPID=$!
		echo "simpleos: ra worker pid=$RA_WPID" >> /tmp/simpleos.log 2>/dev/null || true
	fi
fi
# Child (not exec): capture DraStic stderr. Stock used `| tee ./log.txt`
# which SIGPIPEs if vendor is read-only.
"$EMU" "$ROM" >> "$EMULOG" 2>&1
rc=$?
if [ -n "${RA_WPID:-}" ]; then
	kill "$RA_WPID" 2>/dev/null || true
fi
rm -f /tmp/simpleos_ingame /tmp/simpleos_menu_tap
echo "simpleos: drastic rc=$rc" >> "$EMULOG" 2>/dev/null || true
echo "simpleos: drastic rc=$rc" >> /tmp/simpleos.log 2>/dev/null || true
exit "$rc"
