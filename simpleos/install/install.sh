#!/bin/sh
# Install SimpleOS over official Anbernic Linux (RG DS).
# Does not flash U-Boot. Copies overlay, boot logos, autostart hook.
set -u

LOG=/tmp/simpleos-install.log
STATUS=/tmp/simpleos-install-status
UI_PID=

log() { echo "simpleos-install: $*" | tee -a "$LOG"; }

progress() {
	printf '%s\n%s\n%s\n%s\n' "$1" "$2" "$3" "${4:-run}" > "$STATUS"
}

fail() {
	log "FAIL $1"
	progress 0 "Install failed" "$1" fail
	sleep 8
	[ -n "$UI_PID" ] && kill "$UI_PID" 2>/dev/null || true
	exit 1
}

MMC=
for d in /mnt/mmc /mnt/SDCARD; do
	[ -d "$d" ] || continue
	MMC=$d
	break
done
[ -n "$MMC" ] || fail "SD not mounted"

SOS="$MMC/simpleos"
HERE=
for d in \
	"$MMC/.simpleos_update" \
	"$MMC/simpleos_update" \
	"$SOS/install" \
	"$MMC/simpleos/install" \
	"/mnt/mmc/.simpleos_update" \
	"/mnt/SDCARD/.simpleos_update"
do
	[ -f "$d/install.sh" ] || [ -f "$d/install-boot.sh" ] || continue
	HERE=$d
	break
done
[ -n "$HERE" ] || HERE="$MMC/.simpleos_update"

if [ ! -x "$SOS/main.sh" ] && [ ! -f "$SOS/main.sh" ]; then
	if [ -f "$HERE/payload/main.sh" ]; then
		progress 5 "Copying files" "simpleos" run
		mkdir -p "$SOS"
		cp -a "$HERE/payload/." "$SOS/" || fail "copy payload"
	fi
fi
[ -f "$SOS/main.sh" ] || fail "simpleos/ missing from SD"

lf() {
	[ -f "$1" ] || return 0
	sed -i 's/\r$//' "$1" 2>/dev/null || true
}

progress 8 "Preparing" "scripts" run
lf "$SOS/main.sh"
chmod 755 "$SOS/main.sh" 2>/dev/null || true
for f in "$SOS/system"/*.sh; do
	[ -f "$f" ] || continue
	lf "$f"
	chmod 755 "$f"
done
if [ -f "$SOS/system/bin/simpleos" ]; then
	chmod 755 "$SOS/system/bin/simpleos"
fi
if [ -f "$SOS/system/bin/hangmon" ]; then
	chmod 755 "$SOS/system/bin/hangmon"
fi
if [ -f "$SOS/system/lib/libsimplehook.so" ]; then
	chmod 755 "$SOS/system/lib/libsimplehook.so"
fi

touch /tmp/stopAPP.ini 2>/dev/null || true
killall -9 wait.dge 2>/dev/null || true
killall -9 muos3.bin 2>/dev/null || true
killall -9 muos2.bin 2>/dev/null || true
killall -9 dmenu.bin 2>/dev/null || true

export SIMPLEOS_ROOT="$SOS"
export PATH="$SOS/system/bin:${PATH:-}"
export LD_LIBRARY_PATH="$SOS/system/lib:${LD_LIBRARY_PATH:-}"
unset SIMPLEOS_NOPOWEROFF
unset SIMPLEOS_NORESUME
unset SDL_VIDEODRIVER

progress 12 "Installing" "screens" run
if [ -x "$SOS/system/bin/simpleos" ]; then
	SIMPLEOS_INSTALL=1 SIMPLEOS_INSTALL_STATUS="$STATUS" SIMPLEOS_ROOT="$SOS" \
		"$SOS/system/bin/simpleos" --install >>"$LOG" 2>&1 &
	UI_PID=$!
	sleep 1
fi

# Show branded loading on the Anbernic splash slots until install-boot replaces them.
INSTPNG=
for p in "$HERE/splash/installing.png" "$SOS/system/splash/installing.png"; do
	[ -f "$p" ] && INSTPNG=$p && break
done
if [ -n "$INSTPNG" ]; then
	for r in 1 2 3; do
		dir=/mnt/vendor/resource/res$r/loading
		[ -d "$dir" ] || continue
		cp "$INSTPNG" "$dir/loading.png" 2>/dev/null || true
		cp "$INSTPNG" "$dir/running_en.png" 2>/dev/null || true
		cp "$INSTPNG" "$dir/running_zh.png" 2>/dev/null || true
	done
fi
INSTPNG2=
for p in "$HERE/splash/installing2.png" "$SOS/system/splash/installing2.png"; do
	[ -f "$p" ] && INSTPNG2=$p && break
done
if [ -n "$INSTPNG2" ]; then
	for r in 1 2 3; do
		dir=/mnt/vendor/resource/res$r/boot
		[ -d "$dir" ] || continue
		cp "$INSTPNG2" "$dir/logo2.png" 2>/dev/null || true
	done
fi

progress 40 "Installing" "boot logos" run
BOOT="$HERE/install-boot.sh"
[ -f "$BOOT" ] || BOOT="$HERE/../install-boot.sh"
[ -f "$BOOT" ] || fail "install-boot.sh missing"
lf "$BOOT"
chmod 755 "$BOOT"
sh "$BOOT" >>"$LOG" 2>&1 || fail "boot overlay"

progress 70 "Installing" "APPS shortcut" run
mkdir -p "$MMC/Roms/APPS"
for src in "$HERE/simpleos.sh" "$HERE/../simpleos.sh"; do
	[ -f "$src" ] || continue
	cp "$src" "$MMC/Roms/APPS/SimpleOS.sh"
	break
done
if [ -f "$MMC/Roms/APPS/SimpleOS.sh" ]; then
	lf "$MMC/Roms/APPS/SimpleOS.sh"
	chmod 755 "$MMC/Roms/APPS/SimpleOS.sh"
fi
for src in "$HERE/Install SimpleOS.sh" "$HERE/../Install SimpleOS.sh"; do
	[ -f "$src" ] || continue
	cp "$src" "$MMC/Roms/APPS/Install SimpleOS.sh"
	lf "$MMC/Roms/APPS/Install SimpleOS.sh"
	chmod 755 "$MMC/Roms/APPS/Install SimpleOS.sh"
	break
done

progress 80 "Installing" "NNDDSS emulator" run
if [ -d "$HERE/nnddss_payload" ]; then
	DEST=/mnt/vendor/deep/nnddss
	mkdir -p "$DEST/lib"
	cp -f "$HERE/nnddss_payload/nnddss" "$DEST/nnddss" 2>/dev/null || true
	chmod +x "$DEST/nnddss" 2>/dev/null || true
	cp -rf "$HERE/nnddss_payload/lib/." "$DEST/lib/" 2>/dev/null || true
	rm -f "$DEST/lib/libc.so" "$DEST/lib/libm.so" "$DEST/lib/libdl.so" "$DEST/lib/liblog.so" \
	      "$DEST/lib/libz.so" "$DEST/lib/libGLESv2.so" "$DEST/lib/libOpenSLES.so" "$DEST/lib/libstdc++.so" 2>/dev/null || true
	PERSIST_BASE="$MMC/.nnddss-rgds"
	mkdir -p "$PERSIST_BASE/User/system" "$PERSIST_BASE/assets/shaders" "$PERSIST_BASE/assets/ui" "$PERSIST_BASE/assets/fonts" \
	         "$PERSIST_BASE/tools" "$PERSIST_BASE/home" "$PERSIST_BASE/tmp" "$PERSIST_BASE/xdg-config" "$PERSIST_BASE/xdg-cache" 2>/dev/null || true
	[ -L "$DEST/User" ] || ln -s "$PERSIST_BASE/User" "$DEST/User" 2>/dev/null || true
	[ -L "$DEST/assets" ] || ln -s "$PERSIST_BASE/assets" "$DEST/assets" 2>/dev/null || true
	cp -rf "$HERE/nnddss_payload/shaders/." "$PERSIST_BASE/User/shaders/" 2>/dev/null || true
	cp -rf "$HERE/nnddss_payload/shaders/." "$PERSIST_BASE/assets/shaders/" 2>/dev/null || true
	cp -rf "$HERE/nnddss_payload/ui/." "$PERSIST_BASE/assets/ui/" 2>/dev/null || true
	cp -f "$HERE/nnddss_payload/gamecontrollerdb.txt" "$DEST/gamecontrollerdb.txt" 2>/dev/null || true
	cp -f "$HERE/nnddss_payload/tools/rgds_volume_helper.py" "$PERSIST_BASE/tools/rgds_volume_helper.py" 2>/dev/null || true
	chmod +x "$PERSIST_BASE/tools/rgds_volume_helper.py" 2>/dev/null || true
fi
if [ -f "$HERE/NNDDSS-RGDS.sh" ]; then
	cp -f "$HERE/NNDDSS-RGDS.sh" "$MMC/Roms/APPS/NNDDSS-RGDS.sh" 2>/dev/null || true
	chmod 755 "$MMC/Roms/APPS/NNDDSS-RGDS.sh" 2>/dev/null || true
fi

progress 90 "Installing" "folders" run
mkdir -p "$SOS/userdata" "$SOS/games/archive" "$SOS/bios"
rm -f "$SOS/userdata/boot_stock"
if [ ! -f "$SOS/userdata/net.ini" ]; then
	printf 'wifi=0\nssh=0\n' > "$SOS/userdata/net.ini"
fi
date > "$SOS/userdata/install_ok" 2>/dev/null || true

progress 100 "Installed" "Rebooting" done
log "ok, reboot"
sleep 2
[ -n "$UI_PID" ] && kill "$UI_PID" 2>/dev/null || true
sync
if [ -x "$SOS/system/reboot.sh" ]; then
	exec "$SOS/system/reboot.sh"
fi
reboot -f
exit 0
