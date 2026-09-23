#!/bin/sh
# Apply / step volume (0-20) and brightness (0 night .. 10).
# Live state is tmpfs; SD hw.ini is written later (persist) so a tap
# does not stall DraStic on mmc fsync.
set -u

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
SETTINGS="$ROOT/userdata/settings.ini"
INI="$ROOT/userdata/hw.ini"
LIVE=/tmp/simpleos_hw.live
VOL_MAX=20
BRI_MIN=0
BRI_DAY=1
BRI_MAX=10
LOG=/tmp/simpleos-hw.log

read_from() {
	file=$1
	key=$2
	def=$3
	val=$def
	if [ -f "$file" ]; then
		val=$(sed -n "s/^${key}=//p" "$file" | tail -n 1 | tr -dc '0-9')
		[ -n "$val" ] || val=$def
	fi
	echo "$val"
}

clamp() {
	v=${1:-0}
	lo=${2:-0}
	hi=${3:-0}
	v=$(echo "$v" | tr -dc '0-9')
	[ -n "$v" ] || v=0
	[ "$v" -lt "$lo" ] && v=$lo
	[ "$v" -gt "$hi" ] && v=$hi
	echo "$v"
}

load_live() {
	if [ ! -f "$LIVE" ]; then
		if [ -f "$INI" ]; then
			vol=$(read_from "$INI" volume 8)
			bri=$(read_from "$INI" brightness 6)
		elif [ -f "$SETTINGS" ]; then
			vol=$(read_from "$SETTINGS" volume 8)
			bri=$(read_from "$SETTINGS" brightness 6)
		else
			vol=8
			bri=6
		fi
		vol=$(clamp "$vol" 0 "$VOL_MAX")
		bri=$(clamp "$bri" "$BRI_MIN" "$BRI_MAX")
		printf 'volume=%s\nbrightness=%s\n' "$vol" "$bri" > "$LIVE"
	fi
	vol=$(clamp "$(read_from "$LIVE" volume 8)" 0 "$VOL_MAX")
	bri=$(clamp "$(read_from "$LIVE" brightness 6)" "$BRI_MIN" "$BRI_MAX")
}

save_live() {
	printf 'volume=%s\nbrightness=%s\n' "$vol" "$bri" > "$LIVE"
}

osd() {
	kind=$1
	printf '%s %s\n' "$kind" "$2" > /tmp/simpleos_osd
}

persist_sd() {
	mkdir -p "$ROOT/userdata"
	save_live
	cp "$LIVE" "$INI" 2>/dev/null || true
	rm -f /tmp/simpleos_hw_dirty
}

schedule_persist() {
	save_live
	echo 1 > /tmp/simpleos_hw_dirty
	[ -f /tmp/simpleos_hw_persist_pid ] && return 0
	echo 1 > /tmp/simpleos_hw_persist_pid
	( sleep 2; rm -f /tmp/simpleos_hw_persist_pid; sh "$ROOT/system/apply-hw.sh" persist ) &
}

apply_volume() {
	vol=$(clamp "$1" 0 "$VOL_MAX")
	pct=$((vol * 100 / VOL_MAX))
	last=$(cat /tmp/simpleos_vol_applied 2>/dev/null || echo)
	# Identical sset while DraStic holds the PCM is the in-game hitch,
	# especially mashing VOLUMEUP already at 20.
	[ "$last" = "$vol" ] && return 0
	# RK817 has no Master. DAC only, never unmute: after S3 the codec
	# comes back at 100% and extra mixer flags have raced the restore.
	amixer -q -c 0 sset DAC "${pct}%" 2>/dev/null || true
	echo "$vol" > /tmp/simpleos_vol_applied
}

apply_brightness() {
	bri=$(clamp "$1" "$BRI_MIN" "$BRI_MAX")
	need_dim=0
	any=0
	for b in /sys/class/backlight/*/brightness; do
		[ -e "$b" ] || continue
		any=1
		maxf="${b%brightness}max_brightness"
		max=255
		[ -r "$maxf" ] && max=$(tr -dc '0-9' < "$maxf")
		[ -n "$max" ] || max=255
		[ "$max" -ge 1 ] || max=255
		day=$((BRI_DAY * max / BRI_MAX))
		[ "$day" -lt 1 ] && day=1
		if [ "$bri" -ge "$BRI_DAY" ]; then
			raw=$((bri * max / BRI_MAX))
			[ "$raw" -lt 1 ] && raw=1
		else
			raw=1
			[ "$day" -le 1 ] && need_dim=1
		fi
		cur=$(tr -dc '0-9' < "$b" 2>/dev/null || echo)
		[ "$cur" = "$raw" ] && continue
		printf '%s\n' "$raw" > "$b" 2>/dev/null || true
	done
	if [ "$bri" -le "$BRI_MIN" ]; then
		[ "$any" -eq 0 ] && need_dim=1
		echo "$need_dim" > /tmp/simpleos_nightdim
	else
		echo 0 > /tmp/simpleos_nightdim
	fi
}

read_vol_delta() {
	if [ ! -f /tmp/simpleos_vol_delta ]; then
		echo 0
		return
	fi
	d=$(cat /tmp/simpleos_vol_delta 2>/dev/null || echo 0)
	case "$d" in
		''|*[!0-9+-]*|*[+-]*[+-]*) echo 0 ;;
		*) echo "$d" ;;
	esac
}

# Mash-safe: keep one worker, toast on change, one amixer after a quiet gap.
volpump() {
	applied=$(cat /tmp/simpleos_vol_applied 2>/dev/null || echo -1)
	last_osd=-1
	idle=0
	while :; do
		d=$(read_vol_delta)
		echo 0 > /tmp/simpleos_vol_delta
		if [ "$d" != 0 ]; then
			nv=$(clamp $((vol + d)) 0 "$VOL_MAX")
			if [ "$nv" != "$vol" ]; then
				vol=$nv
				save_live
			fi
			osd v "$vol"
			last_osd=$vol
			idle=0
			continue
		fi
		idle=$((idle + 1))
		# ~200ms quiet: join nearby UP taps in one mixer set.
		if [ "$idle" -lt 4 ]; then
			sleep 0.05
			continue
		fi
		if [ "$applied" != "$vol" ]; then
			maybe_vol "$vol"
			applied=$vol
		fi
		break
	done
	schedule_persist
	rmdir /tmp/simpleos_vol_run 2>/dev/null || true
	d=$(read_vol_delta)
	if [ "$d" != 0 ] && mkdir /tmp/simpleos_vol_run 2>/dev/null; then
		sh "$ROOT/system/apply-hw.sh" volpump >>"$LOG" 2>&1 &
	fi
}

lockd=/tmp/simpleos_hw.lockd
cmd=${1:-apply}
if [ "$cmd" != volpump ]; then
	lk=0
	while [ "$lk" -lt 20 ]; do
		if mkdir "$lockd" 2>/dev/null; then
			lk=99
			break
		fi
		lk=$((lk + 1))
		sleep 0.01
	done
	trap 'rmdir "$lockd" 2>/dev/null || true' EXIT INT TERM
fi
arg2=${2:-}
if [ "$cmd" = force ]; then
	cmd=apply
	IGNORE_SLEEP=1
fi
asleep=0
if [ -z "${IGNORE_SLEEP:-}" ] && [ -f /tmp/simpleos_suspended ]; then
	asleep=1
fi

load_live

maybe_vol() { [ "$asleep" -eq 1 ] || apply_volume "$1"; }
maybe_bri() { [ "$asleep" -eq 1 ] || apply_brightness "$1"; }

log() { echo "$(awk '{print $1}' /proc/uptime) $cmd vol=$vol bri=$bri asleep=$asleep $*" >> "$LOG" 2>/dev/null || true; }

case "$cmd" in
	volpump)
		volpump
		log
		exit 0
		;;
	persist)
		persist_sd
		log
		exit 0
		;;
	set-volume)
		vol=$(clamp "${arg2:-0}" 0 "$VOL_MAX")
		save_live
		rm -f /tmp/simpleos_vol_applied
		maybe_vol "$vol"
		persist_sd
		osd v "$vol"
		;;
	set-brightness)
		bri=$(clamp "${arg2:-1}" "$BRI_MIN" "$BRI_MAX")
		save_live
		maybe_bri "$bri"
		persist_sd
		osd b "$bri"
		;;
	"vol+"|volume+)
		vol=$(clamp $((vol + 1)) 0 "$VOL_MAX")
		maybe_vol "$vol"
		schedule_persist
		osd v "$vol"
		;;
	"vol-"|volume-)
		vol=$(clamp $((vol - 1)) 0 "$VOL_MAX")
		maybe_vol "$vol"
		schedule_persist
		osd v "$vol"
		;;
	"bri+"|brightness+)
		bri=$(clamp $((bri + 1)) "$BRI_MIN" "$BRI_MAX")
		maybe_bri "$bri"
		schedule_persist
		osd b "$bri"
		;;
	"bri-"|brightness-)
		bri=$(clamp $((bri - 1)) "$BRI_MIN" "$BRI_MAX")
		maybe_bri "$bri"
		schedule_persist
		osd b "$bri"
		;;
	bri|brightness)
		maybe_bri "$bri"
		;;
	apply|*)
		load_live
		rm -f /tmp/simpleos_vol_applied
		maybe_bri "$bri"
		maybe_vol "$vol"
		;;
esac
log
