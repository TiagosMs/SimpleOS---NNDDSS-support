#!/bin/sh
# Wall clock: last-known-time fallback (RK808 RTC does not tick when off)
# plus chronyd NTP when Wi-Fi is up. TZ is IANA (default Europe/Rome).
set -u

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
FILE="$ROOT/userdata/clock"
INI="$ROOT/userdata/settings.ini"
LOG=/tmp/simpleos.log
LOOP=/tmp/simpleos_loop
DEFAULT_TZ=Europe/Rome

log() { echo "simpleos: clock $*" >> "$LOG" 2>/dev/null || true; }

rtc_write() {
	hwclock -w -u >/dev/null 2>&1 || hwclock -w >/dev/null 2>&1 || true
}

read_file_field() {
	key=$1
	src=$2
	[ -f "$src" ] || return 0
	sed -n "s/^${key}=//p" "$src" | tail -n 1 | tr -d '\r'
}

posix_tz() {
	case "$1" in
		UTC|Etc/UTC) echo "UTC0" ;;
		Africa/Cairo) echo "EET-2EEST,M4.5.5/0,M10.5.5/0" ;;
		Africa/Casablanca) echo "WET0WEST,M3.5.0,M10.5.0/3" ;;
		Africa/Johannesburg) echo "SAST-2" ;;
		Africa/Lagos) echo "WAT-1" ;;
		Africa/Nairobi) echo "EAT-3" ;;
		America/New_York|America/Toronto) echo "EST5EDT,M3.2.0,M11.1.0" ;;
		America/Chicago|America/Mexico_City) echo "CST6CDT,M3.2.0,M11.1.0" ;;
		America/Denver) echo "MST7MDT,M3.2.0,M11.1.0" ;;
		America/Los_Angeles) echo "PST8PDT,M3.2.0,M11.1.0" ;;
		America/Anchorage) echo "AKST9AKDT,M3.2.0,M11.1.0" ;;
		America/Sao_Paulo) echo "BRT3" ;;
		America/Argentina/Buenos_Aires) echo "ART3" ;;
		America/Santiago) echo "CLT4CLST,M9.1.6/24,M4.1.6/24" ;;
		America/Lima) echo "PET5" ;;
		Asia/Dubai) echo "GST-4" ;;
		Asia/Kolkata) echo "IST-5:30" ;;
		Asia/Bangkok|Asia/Jakarta) echo "ICT-7" ;;
		Asia/Shanghai|Asia/Hong_Kong|Asia/Taipei|Asia/Singapore) echo "CST-8" ;;
		Asia/Seoul) echo "KST-9" ;;
		Asia/Tokyo) echo "JST-9" ;;
		Atlantic/Azores) echo "AZOT1AZOST,M3.5.0/0,M10.5.0/1" ;;
		Atlantic/Canary|Europe/Lisbon) echo "WET0WEST,M3.5.0/1,M10.5.0" ;;
		Australia/Perth) echo "AWST-8" ;;
		Australia/Adelaide) echo "ACST-9:30ACDT,M10.1.0,M4.1.0/3" ;;
		Australia/Sydney) echo "AEST-10AEDT,M10.1.0,M4.1.0/3" ;;
		Europe/London|Europe/Dublin) echo "GMT0BST,M3.5.0/1,M10.5.0" ;;
		Europe/Rome|Europe/Paris|Europe/Berlin|Europe/Madrid|Europe/Amsterdam|Europe/Warsaw)
			echo "CET-1CEST,M3.5.0,M10.5.0/3" ;;
		Europe/Athens|Europe/Helsinki|Europe/Istanbul) echo "EET-2EEST,M3.5.0/3,M10.5.0/4" ;;
		Europe/Moscow) echo "MSK-3" ;;
		Pacific/Honolulu) echo "HST10" ;;
		Pacific/Auckland) echo "NZST-12NZDT,M9.5.0,M4.1.0/3" ;;
		Pacific/Fiji) echo "FJT-12" ;;
		*) echo "UTC0" ;;
	esac
}

resolve_tz() {
	tz=$(read_file_field timezone "$FILE")
	[ -n "$tz" ] || tz=$(read_file_field timezone "$INI")
	[ -n "$tz" ] || tz=$DEFAULT_TZ
	echo "$tz"
}

apply_tz() {
	tz=$(resolve_tz)
	if [ -e "/usr/share/zoneinfo/$tz" ]; then
		export TZ="$tz"
	else
		export TZ="$(posix_tz "$tz")"
	fi
}

load() {
	saved=$(read_file_field epoch "$FILE" | tr -dc '0-9')
	stamp=$(read_file_field stamp "$FILE")
	tz=$(resolve_tz)
	[ -n "$saved" ] || saved=0
}

now_epoch() {
	n=$(date +%s 2>/dev/null || echo 0)
	[ -n "$n" ] || n=0
	echo "$n"
}

write_file() {
	now=$1
	[ -n "$now" ] || now=0
	if [ "$now" -lt 946684800 ]; then
		return 1
	fi
	apply_tz
	stamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo)
	[ -n "$stamp" ] || return 1
	tz=$(resolve_tz)
	mkdir -p "$ROOT/userdata"
	printf 'epoch=%s\nstamp=%s\ntimezone=%s\n' "$now" "$stamp" "$tz" > "$FILE"
	rtc_write
}

save() {
	apply_tz
	load
	now=$(now_epoch)
	if [ "$now" -lt 946684800 ]; then
		return 0
	fi
	if [ "$saved" -gt 0 ] && [ "$now" -lt $((saved + 45)) ] && [ "$now" -ge "$saved" ]; then
		return 0
	fi
	write_file "$now"
}

# Frozen last-off time only if the kernel clock looks unset (no RTC tick).
restore() {
	apply_tz
	load
	now=$(now_epoch)
	if [ "$now" -lt 946684800 ] && [ "$saved" -ge 946684800 ]; then
		if date -s "@$saved" >/dev/null 2>&1; then
			:
		elif [ -n "$stamp" ]; then
			date -s "$stamp" >/dev/null 2>&1 || true
		fi
		rtc_write
		log "restore @$saved tz=$TZ"
		return 0
	fi
	save
}

set_clock() {
	apply_tz
	if [ -n "${2:-}" ] && [ -n "${3:-}" ]; then
		date -s "$2 $3" >/dev/null 2>&1 || true
	fi
	write_file "$(now_epoch)"
	log "set ${2:-} ${3:-} tz=$TZ"
}

install_zoneinfo() {
	tz=$1
	[ -n "$tz" ] || return 0
	if [ -e "/usr/share/zoneinfo/$tz" ]; then
		ln -sfn "/usr/share/zoneinfo/$tz" /etc/localtime
		printf '%s\n' "$tz" > /etc/timezone 2>/dev/null || true
	fi
}

set_tz() {
	want=${2:-}
	[ -n "$want" ] || want=$DEFAULT_TZ
	mkdir -p "$ROOT/userdata"
	load
	now=$(now_epoch)
	[ "$now" -ge 946684800 ] || now=$saved
	if [ -f "$INI" ]; then
		if grep -q '^timezone=' "$INI" 2>/dev/null; then
			sed -i "s|^timezone=.*|timezone=$want|" "$INI"
		else
			printf 'timezone=%s\n' "$want" >> "$INI"
		fi
	fi
	printf 'epoch=%s\nstamp=\ntimezone=%s\n' "${now:-0}" "$want" > "$FILE"
	install_zoneinfo "$want"
	apply_tz
	stamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo)
	printf 'epoch=%s\nstamp=%s\ntimezone=%s\n' "${now:-0}" "$stamp" "$want" > "$FILE"
	log "tz $want TZ=$TZ"
}

# Restart chronyd so a manual date -s offset is not treated as NTP truth.
# burst + waitsync with a 1s cap unsyncs the daemon and keeps the offset.
resync() {
	apply_tz
	if [ -x /etc/init.d/S49chronyd ]; then
		/etc/init.d/S49chronyd restart >/dev/null 2>&1 || true
	else
		killall chronyd >/dev/null 2>&1 || true
		ensure_chrony
		n=0
		while [ "$n" -lt 8 ]; do
			pidof chronyd >/dev/null 2>&1 && break
			sleep 1
			n=$((n + 1))
		done
	fi
	if command -v chronyc >/dev/null 2>&1; then
		chronyc waitsync 25 0 0 0.4 >/dev/null 2>&1 || true
		chronyc makestep >/dev/null 2>&1 || true
	fi
	now=$(now_epoch)
	if [ "$now" -ge 946684800 ]; then
		write_file "$now"
		log "resync $now tz=$TZ"
	fi
}

ensure_chrony() {
	pidof chronyd >/dev/null 2>&1 && return 0
	if [ -x /etc/init.d/S49chronyd ]; then
		/etc/init.d/S49chronyd start >/dev/null 2>&1 &
		return 0
	fi
	command -v chronyd >/dev/null 2>&1 && chronyd >/dev/null 2>&1 &
}

# Let NTP step the clock (Wi-Fi). Persist when it moves; never rewind NTP.
ntp_watch() {
	if [ -f /tmp/simpleos_clock_ntp ]; then
		old=$(cat /tmp/simpleos_clock_ntp 2>/dev/null || echo)
		if [ -n "$old" ] && [ -d "/proc/$old" ]; then
			return 0
		fi
	fi
	echo $$ > /tmp/simpleos_clock_ntp
	apply_tz
	ensure_chrony
	n=0
	while [ -f "$LOOP" ]; do
		apply_tz
		if command -v chronyc >/dev/null 2>&1; then
			chronyc makestep >/dev/null 2>&1 || true
		fi
		load
		now=$(now_epoch)
		if [ "$now" -lt 946684800 ]; then
			restore
		else
			st=$(chronyc tracking 2>/dev/null | sed -n 's/^Stratum *: *//p' | tr -dc '0-9')
			[ -n "$st" ] || st=0
			if [ "$st" -ge 1 ] && [ "$st" -lt 16 ]; then
				if [ "$saved" -eq 0 ] || [ "$now" -ge $((saved + 20)) ] || [ "$saved" -ge $((now + 20)) ]; then
					write_file "$now"
					log "ntp stratum=$st $now tz=$TZ"
				fi
			fi
		fi
		n=$((n + 1))
		if [ "$n" -lt 12 ]; then
			sleep 3
		else
			sleep 15
		fi
	done
	rm -f /tmp/simpleos_clock_ntp
}

cmd=${1:-restore}
case "$cmd" in
	save) apply_tz; save ;;
	restore) restore ;;
	set) set_clock "$@" ;;
	tz) set_tz "$@" ;;
	resync) resync ;;
	print-tz) resolve_tz ;;
	ntp) ntp_watch ;;
	*) restore ;;
esac
