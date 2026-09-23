#!/bin/sh
# SimpleOS OTA: check GitHub releases, then stage system.new for main.sh.
set -u

ROOT="${SIMPLEOS_ROOT:-}"
if [ -z "$ROOT" ]; then
	ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fi
export SIMPLEOS_ROOT="$ROOT"
PY="$ROOT/system/ota.py"
STATUS=/tmp/simpleos-ota
LOG=/tmp/simpleos-ota.log
WORK="$ROOT/userdata/update"
ZIP="$WORK/package.zip"
EXTRACT="$WORK/extract"
PIDF=/tmp/simpleos-ota.pid

log() { echo "simpleos-ota: $*" | tee -a "$LOG" >&2; }

write_status() {
	phase=$1
	pct=$2
	note=$3
	{
		printf 'phase=%s\n' "$phase"
		printf 'pct=%s\n' "$pct"
		printf 'local=%s\n' "${LOCAL_VER:-}"
		printf 'remote=%s\n' "${REMOTE_VER:-}"
		[ -n "${OTA_URL:-}" ] && printf 'url=%s\n' "$OTA_URL"
		printf 'note=%s\n' "$note"
	} > "$STATUS.tmp"
	mv "$STATUS.tmp" "$STATUS"
}

echo $$ > "$PIDF"
: >> "$LOG"
LOCAL_VER=$(sed -n '1p' "$ROOT/system/VERSION" 2>/dev/null | tr -d '\r\n ')
[ -n "$LOCAL_VER" ] || LOCAL_VER=0
REMOTE_VER=
OTA_URL=

have_py() {
	command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1
}

py() {
	if command -v python3 >/dev/null 2>&1; then
		python3 "$@"
	else
		python "$@"
	fi
}

stage_zip() {
	src_zip=$1
	write_status apply 12 "Unpacking"
	rm -rf "$EXTRACT"
	mkdir -p "$EXTRACT"
	if ! unzip -q "$src_zip" -d "$EXTRACT" >>"$LOG" 2>&1; then
		write_status fail 0 "Unpack failed"
		rm -rf "$EXTRACT"
		return 1
	fi

	SRC=
	if [ -f "$EXTRACT/simpleos/system/loop.sh" ]; then
		SRC="$EXTRACT/simpleos/system"
	elif [ -f "$EXTRACT/system/loop.sh" ]; then
		SRC="$EXTRACT/system"
	elif [ -f "$EXTRACT/loop.sh" ]; then
		SRC="$EXTRACT"
	fi
	if [ -z "$SRC" ]; then
		write_status fail 0 "Bad package"
		rm -rf "$EXTRACT"
		return 1
	fi

	write_status apply 70 "Preparing"
	rm -rf "$ROOT/system.new"
	if ! cp -a "$SRC" "$ROOT/system.new" >>"$LOG" 2>&1; then
		rm -rf "$ROOT/system.new" "$EXTRACT"
		write_status fail 0 "Copy failed"
		return 1
	fi
	if [ ! -f "$ROOT/system.new/loop.sh" ]; then
		rm -rf "$ROOT/system.new" "$EXTRACT"
		write_status fail 0 "Bad package"
		return 1
	fi
	# Never install payload main.sh: older releases drop the system.new swap.
	if [ -f "$ROOT/system/ota-main.sh" ]; then
		cp -f "$ROOT/system/ota-main.sh" "$ROOT/main.sh"
		sed -i 's/\r$//' "$ROOT/main.sh" 2>/dev/null || true
		chmod 755 "$ROOT/main.sh" 2>/dev/null || true
	fi
	chmod 755 "$ROOT/system.new"/*.sh 2>/dev/null || true
	[ -f "$ROOT/system.new/bin/simpleos" ] && chmod 755 "$ROOT/system.new/bin/simpleos"
	[ -f "$ROOT/system.new/lib/libsimplehook.so" ] && chmod 755 "$ROOT/system.new/lib/libsimplehook.so"

	rm -rf "$EXTRACT"
	write_status done 100 "Ready to reboot"
	log "staged $ROOT/system.new remote=$REMOTE_VER"
	return 0
}

cmd=${1:-check}

if [ "$cmd" = "check" ]; then
	write_status check 0 "Checking for updates"
	if [ -n "${SIMPLEOS_HOST:-}" ]; then
		write_status none 0 "Up to date"
		rm -f "$PIDF"
		exit 0
	fi
	if ! have_py || [ ! -f "$PY" ]; then
		write_status fail 0 "Updater missing"
		rm -f "$PIDF"
		exit 1
	fi
	py "$PY" check "$LOCAL_VER" >>"$LOG" 2>&1
	rc=$?
	rm -f "$PIDF"
	exit $rc
fi

if [ "$cmd" = "apply-local" ]; then
	ZIP=${SIMPLEOS_OTA_ZIP:-}
	if [ -z "$ZIP" ] && [ -f /tmp/simpleos-ota-zip ]; then
		ZIP=$(sed -n '1p' /tmp/simpleos-ota-zip | tr -d '\r\n')
	fi
	REMOTE_VER=${SIMPLEOS_OTA_REMOTE:-manual}
	if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then
		write_status fail 0 "Missing package"
		rm -f "$PIDF"
		exit 1
	fi
	if [ -n "${SIMPLEOS_HOST:-}" ]; then
		write_status done 100 "Ready to reboot"
		rm -f "$PIDF"
		exit 0
	fi
	write_status apply 4 "Updating"
	if ! stage_zip "$ZIP"; then
		rm -f "$PIDF"
		exit 1
	fi
	rm -f "$ZIP"
	log "removed $ZIP"
	rm -f "$PIDF"
	exit 0
fi

if [ "$cmd" != "apply" ]; then
	log "unknown cmd $cmd"
	rm -f "$PIDF"
	exit 1
fi

OTA_URL=${SIMPLEOS_OTA_URL:-}
REMOTE_VER=${SIMPLEOS_OTA_REMOTE:-}
if [ -z "$OTA_URL" ]; then
	write_status fail 0 "Missing package"
	rm -f "$PIDF"
	exit 1
fi

if [ -n "${SIMPLEOS_HOST:-}" ]; then
	write_status done 100 "Ready to reboot"
	rm -f "$PIDF"
	exit 0
fi

if ! have_py || [ ! -f "$PY" ]; then
	write_status fail 0 "Updater missing"
	rm -f "$PIDF"
	exit 1
fi

mkdir -p "$WORK"
rm -rf "$EXTRACT" "$ZIP"
write_status apply 4 "Downloading"
if ! py "$PY" apply "$LOCAL_VER" "$OTA_URL" "$ZIP" "$REMOTE_VER" >>"$LOG" 2>&1; then
	[ -f "$STATUS" ] || write_status fail 0 "Download failed"
	rm -f "$PIDF"
	exit 1
fi

if ! stage_zip "$ZIP"; then
	rm -f "$PIDF"
	exit 1
fi
rm -f "$ZIP"
rm -f "$PIDF"
exit 0
