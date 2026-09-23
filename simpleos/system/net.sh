#!/bin/sh
# Wi-Fi / SSH helper for the home options menu. BusyBox ash.
# Do not `set -e`: a missing tool must not abort the UI.
set -u

ROOT="${SIMPLEOS_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
NETINI="$ROOT/userdata/net.ini"
LOG=/tmp/simpleos-net.log
ST=/tmp/simpleos-net.status
SC=/tmp/simpleos-net.scan
: >> "$LOG"
log() { echo "simpleos-net: $*" | tee -a "$LOG" >&2; }

run_to() {
	secs=${1:-8}
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "$secs" "$@" >/dev/null 2>&1 || return 1
	else
		"$@" >/dev/null 2>&1 || return 1
	fi
	return 0
}

nm() {
	command -v nmcli >/dev/null 2>&1 || return 1
	run_to 8 nmcli "$@"
}

read_key() {
	file=$1
	key=$2
	val=""
	if [ -f "$file" ]; then
		val=$(sed -n "s/^${key}=//p" "$file" | tail -n 1 | tr -dc '01')
	fi
	printf '%s' "$val"
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

want_wifi() { read_key "$NETINI" wifi; }
want_ssh() { read_key "$NETINI" ssh; }

persist_wifi() { patch_key "$NETINI" wifi "$1"; }
persist_ssh() { patch_key "$NETINI" ssh "$1"; }

wifi_ifaces() {
	for iface in /sys/class/net/*/wireless; do
		[ -e "$iface" ] || continue
		dev=${iface%/wireless}
		dev=${dev##*/}
		case "$dev" in
			p2p*) ;;
			*) echo "$dev" ;;
		esac
	done
}

wifi_ready() {
	[ -n "$(wifi_ifaces)" ]
}

start_nm() {
	if command -v pgrep >/dev/null 2>&1 && pgrep -x NetworkManager >/dev/null 2>&1; then
		return 0
	fi
	if [ -x /usr/sbin/NetworkManager ]; then
		/usr/sbin/NetworkManager >>"$LOG" 2>&1 || true
	elif [ -x /etc/init.d/S45network-manager ]; then
		/etc/init.d/S45network-manager start >>"$LOG" 2>&1 || true
	fi
}

# Rockchip S36: full `start` runs BT first and the script is `bash -e`.
# A BT failure aborts before start_wifi, so wlan0 never appears until stock
# Network Settings has been used. start_wifi only loads the Wi-Fi module.
bring_chip() {
	wifi_ready && return 0
	if [ -x /usr/bin/wifibt-init.sh ]; then
		run_to 25 /usr/bin/wifibt-init.sh start_wifi || true
	elif [ -x /etc/init.d/S36wifibt-init.sh ]; then
		run_to 25 /etc/init.d/S36wifibt-init.sh start || true
	fi
	i=0
	while [ "$i" -lt 30 ]; do
		wifi_ready && return 0
		sleep 0.2
		i=$((i + 1))
	done
	return 1
}

bring_wifi_up() {
	# /dev/rfkill is deleted by stock BT init; unblock if it still exists.
	if command -v rfkill >/dev/null 2>&1 && [ -e /dev/rfkill ]; then
		rfkill unblock wifi >/dev/null 2>&1 || true
		rfkill unblock wlan >/dev/null 2>&1 || true
	fi
	bring_chip || log "wifi chip not ready"
	start_nm
	nm radio wifi on || true
	nm networking on || true
	command -v connmanctl >/dev/null 2>&1 && run_to 5 connmanctl enable wifi || true
	for dev in $(wifi_ifaces); do
		ip link set "$dev" up >/dev/null 2>&1 || true
		ifconfig "$dev" up >/dev/null 2>&1 || true
		nm device set "$dev" managed yes || true
	done
}

take_wifi_down() {
	for dev in $(wifi_ifaces); do
		nm device disconnect "$dev" || true
		ip link set "$dev" down >/dev/null 2>&1 || true
	done
	nm radio wifi off || true
	command -v connmanctl >/dev/null 2>&1 && run_to 5 connmanctl disable wifi || true
	if command -v rfkill >/dev/null 2>&1 && [ -e /dev/rfkill ]; then
		rfkill block wifi >/dev/null 2>&1 || true
		rfkill block wlan >/dev/null 2>&1 || true
	fi
}

live_wifi() {
	if command -v nmcli >/dev/null 2>&1; then
		if command -v timeout >/dev/null 2>&1; then
			timeout 8 nmcli radio wifi 2>/dev/null | grep -qi enabled && return 0
		else
			nmcli radio wifi 2>/dev/null | grep -qi enabled && return 0
		fi
	fi
	if command -v rfkill >/dev/null 2>&1 && [ -e /dev/rfkill ]; then
		rfkill list wifi 2>/dev/null | grep -q "Soft blocked: yes" && return 1
	fi
	wifi_ready || return 1
	return 0
}

cur_ssid() {
	ssid=""
	if command -v nmcli >/dev/null 2>&1; then
		ssid=$(timeout 8 nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
	fi
	if [ -z "$ssid" ] && command -v iwgetid >/dev/null 2>&1; then
		ssid=$(iwgetid -r 2>/dev/null || true)
	fi
	if [ -z "$ssid" ]; then
		for dev in $(wifi_ifaces); do
			if command -v iw >/dev/null 2>&1; then
				ssid=$(iw dev "$dev" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -n 1)
				[ -n "$ssid" ] && break
			fi
		done
	fi
	printf '%s' "$ssid"
}

cur_ip() {
	ip=""
	if command -v hostname >/dev/null 2>&1; then
		ip=$(hostname -I 2>/dev/null | awk '{print $1}')
	fi
	if [ -z "$ip" ]; then
		for dev in $(wifi_ifaces); do
			ip=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
			[ -n "$ip" ] && break
		done
	fi
	printf '%s' "${ip:-}"
}

ssh_running() {
	if command -v pgrep >/dev/null 2>&1; then
		pgrep -x sshd >/dev/null 2>&1 && return 0
		pgrep -x dropbear >/dev/null 2>&1 && return 0
		pgrep sshd >/dev/null 2>&1 && return 0
	fi
	if command -v ss >/dev/null 2>&1; then
		ss -lnt 2>/dev/null | grep -q ':22 ' && return 0
	fi
	if command -v netstat >/dev/null 2>&1; then
		netstat -lnt 2>/dev/null | grep -q ':22 ' && return 0
	fi
	return 1
}

prepare_sshd_dirs() {
	mkdir -p /run/sshd /var/run/sshd >/dev/null 2>&1 || true
	chmod 755 /run/sshd /var/run/sshd >/dev/null 2>&1 || true
	rm -f /run/sshd.pid /var/run/sshd.pid >/dev/null 2>&1 || true
}

sys_timeout() {
	if command -v timeout >/dev/null 2>&1; then
		timeout 3 "$@" >/dev/null 2>&1 || true
	fi
}

start_ssh() {
	prepare_sshd_dirs
	if [ -x /usr/sbin/sshd ]; then
		/usr/sbin/sshd >>"$LOG" 2>&1 || true
	elif command -v sshd >/dev/null 2>&1; then
		sshd >>"$LOG" 2>&1 || true
	fi
	ssh_running && return 0
	if command -v dropbear >/dev/null 2>&1; then
		dropbear >>"$LOG" 2>&1 || true
	fi
	ssh_running && return 0
	for s in /etc/init.d/ssh /etc/init.d/sshd /etc/init.d/dropbear /etc/init.d/S50sshd; do
		[ -x "$s" ] || continue
		"$s" start >>"$LOG" 2>&1 || true
	done
	if command -v systemctl >/dev/null 2>&1; then
		sys_timeout systemctl start ssh
		sys_timeout systemctl start sshd
		sys_timeout systemctl start dropbear
	fi
}

stop_ssh() {
	if command -v pkill >/dev/null 2>&1; then
		pkill -x sshd >/dev/null 2>&1 || true
		pkill -x dropbear >/dev/null 2>&1 || true
	fi
	for s in /etc/init.d/ssh /etc/init.d/sshd /etc/init.d/dropbear /etc/init.d/S50sshd; do
		[ -x "$s" ] || continue
		"$s" stop >/dev/null 2>&1 || true
	done
	if command -v systemctl >/dev/null 2>&1; then
		sys_timeout systemctl stop ssh
		sys_timeout systemctl stop sshd
		sys_timeout systemctl stop dropbear
	fi
}

write_status() {
	wifi=0
	w=$(want_wifi)
	if [ -n "$w" ]; then
		wifi=$w
	elif live_wifi; then
		wifi=1
	fi
	ssh=0
	s=$(want_ssh)
	if [ -n "$s" ]; then
		ssh=$s
	elif ssh_running; then
		ssh=1
	fi
	ssid=$(cur_ssid)
	ip=$(cur_ip)
	{
		echo "wifi=$wifi"
		echo "ssh=$ssh"
		echo "ssid=$ssid"
		echo "ip=$ip"
	} > "$ST"
}

cmd_scan() {
	: > "$SC"
	w=$(want_wifi)
	if [ "$w" = "0" ]; then
		write_status
		return 0
	fi
	if [ "$w" = "1" ] || live_wifi; then
		bring_wifi_up
		if command -v nmcli >/dev/null 2>&1; then
			nm device wifi rescan || true
			sleep 1
			timeout 8 nmcli -t -f SSID,SECURITY device wifi list 2>/dev/null | while IFS=: read -r ssid sec rest; do
				[ -n "$ssid" ] || continue
				[ "$ssid" = "--" ] && continue
				flag=0
				case "$sec$rest" in
					*WPA*|*WEP*|*IEEE*) flag=1 ;;
				esac
				echo "$flag $ssid" >> "$SC"
			done
		fi
		if [ ! -s "$SC" ] && command -v iw >/dev/null 2>&1; then
			for dev in $(wifi_ifaces); do
				iw dev "$dev" scan 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | while read -r ssid; do
					[ -n "$ssid" ] || continue
					echo "1 $ssid" >> "$SC"
				done
				break
			done
		fi
		if [ -f "$SC" ]; then
			awk '{ n=$0; sub(/^[01] /,"",n); if(n!="" && !seen[n]++) print $0 }' "$SC" > "$SC.tmp"
			mv "$SC.tmp" "$SC"
		fi
	fi
	write_status
}

cmd_apply() {
	w=$(want_wifi)
	if [ "$w" = "0" ]; then
		take_wifi_down
	elif [ "$w" = "1" ]; then
		bring_wifi_up
	fi
	s=$(want_ssh)
	if [ "$s" = "0" ]; then
		stop_ssh
	elif [ "$s" = "1" ]; then
		start_ssh
	fi
	write_status
	log "apply wifi=${w:-live} ssh=${s:-live}"
}

case "${1:-status}" in
	status)
		write_status
		;;
	scan)
		cmd_scan
		;;
	apply)
		cmd_apply
		;;
	wifi-on)
		persist_wifi 1
		bring_wifi_up
		write_status
		log "wifi on ifaces=$(wifi_ifaces | tr '\n' ' ')"
		;;
	wifi-off)
		persist_wifi 0
		take_wifi_down
		write_status
		log "wifi off"
		;;
	ssh-on)
		persist_ssh 1
		start_ssh
		write_status
		if ssh_running; then
			log "ssh on"
		else
			log "ssh on failed"
		fi
		;;
	ssh-off)
		persist_ssh 0
		stop_ssh
		write_status
		log "ssh off"
		;;
	connect)
		ssid=${SIMPLEOS_SSID:-}
		psk=${SIMPLEOS_PSK:-}
		if [ -z "$ssid" ]; then
			log "connect senza SSID"
			write_status
			exit 0
		fi
		persist_wifi 1
		bring_wifi_up
		ok=0
		if command -v nmcli >/dev/null 2>&1; then
			if [ -n "$psk" ]; then
				run_to 25 nmcli device wifi connect "$ssid" password "$psk" && ok=1
			else
				run_to 25 nmcli device wifi connect "$ssid" && ok=1
			fi
		fi
		if [ "$ok" -eq 0 ] && [ -x /usr/bin/wifi-connect.sh ] && [ -n "$psk" ]; then
			run_to 25 /usr/bin/wifi-connect.sh "$ssid" "$psk" && ok=1
		fi
		log "connect $ssid ok=$ok"
		write_status
		;;
	*)
		write_status
		;;
esac
