#!/bin/sh
# Install SimpleOS as the default Anbernic boot (loadapp autostart hook),
# userspace logos, and boot-partition RSCE splash. Does not flash U-Boot SPL.
# Run on the RG DS as root, or via the Windows deploy script.
set -u

SOS=
for d in /mnt/mmc/simpleos /mnt/SDCARD/simpleos; do
	[ -d "$d/system" ] && SOS=$d && break
done
[ -n "$SOS" ] || { echo "simpleos: root not found" >&2; exit 1; }

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SPLASH="$HERE/splash"
[ -d "$SPLASH" ] || SPLASH="$SOS/system/splash"
AUTO="$HERE/autostart"
[ -f "$AUTO" ] || AUTO="$HERE/../autostart"
[ -f "$AUTO" ] || AUTO="$SOS/system/autostart"
[ -f "$AUTO" ] || { echo "simpleos: autostart not found" >&2; exit 1; }

mkdir -p /mnt/mod/ctrl
cp "$AUTO" /mnt/mod/ctrl/autostart
sed -i 's/\r$//' /mnt/mod/ctrl/autostart
chmod 755 /mnt/mod/ctrl/autostart

PMIC="$HERE/S03simpleos-pmic.sh"
[ -f "$PMIC" ] || PMIC="$HERE/../S03simpleos-pmic.sh"
if [ -f "$PMIC" ]; then
	cp "$PMIC" /etc/init.d/S03simpleos-pmic.sh
	sed -i 's/\r$//' /etc/init.d/S03simpleos-pmic.sh
	chmod 755 /etc/init.d/S03simpleos-pmic.sh
fi

bk() {
	src=$1
	[ -f "$src" ] || return 0
	[ -f "$src.anbernic" ] && return 0
	cp -a "$src" "$src.anbernic"
}

if [ -f "$SPLASH/bootlogo.bmp" ]; then
	bk /mnt/vendor/ctrl/waiting/bootlogo.bmp
	cp "$SPLASH/bootlogo.bmp" /mnt/vendor/ctrl/waiting/bootlogo.bmp
fi
if [ -f "$SPLASH/logo.png" ]; then
	for r in 1 2 3; do
		dir=/mnt/vendor/resource/res$r/boot
		[ -d "$dir" ] || continue
		bk "$dir/logo.png"
		cp "$SPLASH/logo.png" "$dir/logo.png"
		if [ -f "$SPLASH/logo2.png" ]; then
			bk "$dir/logo2.png"
			cp "$SPLASH/logo2.png" "$dir/logo2.png"
		fi
	done
fi
if [ -f "$SPLASH/loading.png" ]; then
	for r in 1 2 3; do
		dir=/mnt/vendor/resource/res$r/loading
		[ -d "$dir" ] || continue
		bk "$dir/loading.png"
		cp "$SPLASH/loading.png" "$dir/loading.png"
		for n in running_en.png running_zh.png; do
			[ -f "$SPLASH/$n" ] || continue
			bk "$dir/$n"
			cp "$SPLASH/$n" "$dir/$n"
		done
	done
fi

# Early U-Boot/kernel splash lives in the boot FIT resource (logo.bmp),
# not in the userspace PNG. Flash SimpleOS there; keep a one-time dump.
BOOTDEV=
for d in /dev/block/by-name/boot /dev/mmcblk1p3; do
	[ -e "$d" ] && BOOTDEV=$d && break
done
FLASH=
for b in "$SOS/system/bin/sosbootlogo" "$HERE/sosbootlogo" "$HERE/../bin/sosbootlogo"; do
	[ -x "$b" ] && FLASH=$b && break
done
TOPBMP="$SPLASH/logo.bmp"
BOTBMP="$SPLASH/logo2.bmp"
if [ -n "$BOOTDEV" ] && [ -n "$FLASH" ] && [ -f "$TOPBMP" ] && [ -f "$BOTBMP" ]; then
	mkdir -p "$SOS/userdata"
	chmod 755 "$FLASH"
	"$FLASH" --boot "$BOOTDEV" --top "$TOPBMP" --bot "$BOTBMP" \
		--backup "$SOS/userdata/boot.img.anbernic" || {
		echo "simpleos: boot partition logo flash failed" >&2
		exit 1
	}
else
	echo "simpleos: skip boot-partition logos (tool or bmp missing)" >&2
fi

echo "simpleos: default boot installed (touch $SOS/userdata/boot_stock to use Anbernic menu)"
