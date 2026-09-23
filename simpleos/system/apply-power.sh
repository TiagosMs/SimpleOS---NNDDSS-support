#!/bin/sh
# CPU/GPU/DMC clocks: 1 conservative, 2 performance, 3 high.
set -u

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
SETTINGS="$ROOT/userdata/settings.ini"
LIVE=/tmp/simpleos_power.live
LOG=/tmp/simpleos-hw.log
PWR_MIN=1
PWR_MAX=3

log() { echo "$(awk '{print $1}' /proc/uptime) apply-power $*" >> "$LOG" 2>/dev/null || true; }

read_from() {
	file=$1
	key=$2
	def=$3
	val=$def
	if [ -f "$file" ]; then
		val=$(sed -n "s/^${key}=//p" "$file" | tail -n 1 | tr -dc '0-9-')
		[ -n "$val" ] || val=$def
	fi
	echo "$val"
}

clamp() {
	v=${1:-0}
	lo=${2:-0}
	hi=${3:-0}
	v=$(echo "$v" | tr -dc '0-9-')
	[ -n "$v" ] || v=0
	case "$v" in
		-*) v=0 ;;
	esac
	[ "$v" -lt "$lo" ] && v=$lo
	[ "$v" -gt "$hi" ] && v=$hi
	echo "$v"
}

patch_key() {
	file=$1
	key=$2
	val=$3
	dir=$(dirname "$file")
	mkdir -p "$dir"
	if [ -f "$file" ] && grep -q "^${key}=" "$file"; then
		sed -i "s/^${key}=.*/${key}=${val}/" "$file"
	else
		printf '%s=%s\n' "$key" "$val" >> "$file"
	fi
}

nth_asc() {
	n=$1
	shift
	i=0
	last=
	for w in $*; do
		i=$((i + 1))
		last=$w
		[ "$i" -eq "$n" ] && echo "$w" && return 0
	done
	echo "$last"
}

count_words() {
	n=0
	for _w in $*; do
		n=$((n + 1))
	done
	echo "$n"
}

sort_asc() {
	echo "$*" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -n | tr '\n' ' '
}

cpu_freqs() {
	f=/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
	if [ -r "$f" ]; then
		sort_asc "$(cat "$f")"
	else
		echo "408000 600000 816000 1104000 1416000 1608000 1800000 1992000 "
	fi
}

dev_freqs() {
	d=$1
	if [ -r "$d/available_frequencies" ]; then
		sort_asc "$(cat "$d/available_frequencies")"
	fi
}

pick_mode_freq() {
	mode=$1
	freqs=$2
	n=$(count_words $freqs)
	[ "$n" -ge 1 ] || return 0
	case "$mode" in
		1)
			idx=$(( (n + 1) / 2 ))
			[ "$idx" -lt 1 ] && idx=1
			[ "$idx" -gt "$n" ] && idx=$n
			;;
		2)
			idx=$((n - 1))
			[ "$idx" -lt 1 ] && idx=1
			;;
		*)
			idx=$n
			;;
	esac
	nth_asc "$idx" $freqs
}

pick_min_freq() {
	mode=$1
	freqs=$2
	n=$(count_words $freqs)
	[ "$n" -ge 1 ] || return 0
	case "$mode" in
		3)
			pick_mode_freq 3 "$freqs"
			;;
		*)
			nth_asc 1 $freqs
			;;
	esac
}

write_if() {
	file=$1
	val=$2
	[ -n "$val" ] || return 0
	[ -w "$file" ] || return 0
	printf '%s\n' "$val" > "$file" 2>/dev/null || true
}

apply_cpu() {
	mode=$1
	freqs=$(cpu_freqs)
	max=$(pick_mode_freq "$mode" "$freqs")
	min=$(pick_min_freq "$mode" "$freqs")
	[ -n "$max" ] || return 0
	[ -n "$min" ] || min=$max
	case "$mode" in
		1|2) gov=schedutil ;;
		*) gov=performance ;;
	esac
	for g in /sys/devices/system/cpu/cpu*/cpufreq; do
		[ -d "$g" ] || continue
		low=$(nth_asc 1 $freqs)
		write_if "$g/scaling_min_freq" "$low"
		write_if "$g/scaling_max_freq" "$max"
		write_if "$g/scaling_min_freq" "$min"
		if [ -w "$g/scaling_governor" ]; then
			if grep -qw "$gov" "$g/scaling_available_governors" 2>/dev/null; then
				write_if "$g/scaling_governor" "$gov"
			else
				write_if "$g/scaling_governor" performance
			fi
		fi
	done
	log "cpu mode=$mode min=$min max=$max gov=$gov"
}

apply_devfreq() {
	mode=$1
	path=$2
	[ -d "$path" ] || return 0
	freqs=$(dev_freqs "$path")
	[ -n "$freqs" ] || return 0
	max=$(pick_mode_freq "$mode" "$freqs")
	min=$(pick_min_freq "$mode" "$freqs")
	[ -n "$max" ] || return 0
	[ -n "$min" ] || min=$max
	case "$mode" in
		1) gov=simple_ondemand ;;
		*) gov=performance ;;
	esac
	low=$(nth_asc 1 $freqs)
	write_if "$path/min_freq" "$low"
	write_if "$path/max_freq" "$max"
	write_if "$path/min_freq" "$min"
	if [ -w "$path/governor" ]; then
		if grep -qw "$gov" "$path/available_governors" 2>/dev/null; then
			write_if "$path/governor" "$gov"
		else
			write_if "$path/governor" performance
		fi
	fi
	log "devfreq $path mode=$mode min=$min max=$max gov=$gov"
}

apply_clocks() {
	mode=$1
	apply_cpu "$mode"
	apply_devfreq "$mode" /sys/class/devfreq/fde60000.gpu
	apply_devfreq "$mode" /sys/class/devfreq/dmc
}

persist() {
	mode=$1
	printf 'power=%s\n' "$mode" > "$LIVE"
	mkdir -p "$ROOT/userdata"
	patch_key "$SETTINGS" power "$mode"
}

osd() {
	printf 'p %s\n' "$1" > /tmp/simpleos_osd
}

load_mode() {
	if [ -f "$LIVE" ]; then
		mode=$(clamp "$(read_from "$LIVE" power 3)" "$PWR_MIN" "$PWR_MAX")
	else
		mode=$(clamp "$(read_from "$SETTINGS" power 3)" "$PWR_MIN" "$PWR_MAX")
		printf 'power=%s\n' "$mode" > "$LIVE"
	fi
}

cmd=${1:-apply}
arg2=${2:-}

load_mode

case "$cmd" in
	set)
		mode=$(clamp "${arg2:-3}" "$PWR_MIN" "$PWR_MAX")
		persist "$mode"
		apply_clocks "$mode"
		osd "$mode"
		;;
	up|+)
		mode=$(clamp $((mode + 1)) "$PWR_MIN" "$PWR_MAX")
		persist "$mode"
		apply_clocks "$mode"
		osd "$mode"
		;;
	down|-)
		mode=$(clamp $((mode - 1)) "$PWR_MIN" "$PWR_MAX")
		persist "$mode"
		apply_clocks "$mode"
		osd "$mode"
		;;
	apply|*)
		persist "$mode"
		apply_clocks "$mode"
		;;
esac
