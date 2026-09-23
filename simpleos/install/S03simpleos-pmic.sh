#!/bin/sh
# Clear RK817 DEV_OFF left by SimpleOS halt.sh (SYS_CFG3 idle = 0x18).
command -v i2cset >/dev/null 2>&1 && i2cset -y -f 0 0x20 0xf4 0x18 2>/dev/null || true

# If the user asked for stock boot, restore dmenu/muos execute bits here
# (early, before loadapp). loop.sh chmod -x persists across a reboot.
for d in /mnt/mmc/simpleos /mnt/SDCARD/simpleos; do
	[ -f "$d/userdata/boot_stock" ] || continue
	for b in /mnt/vendor/bin/muos3.bin /mnt/vendor/bin/muos2.bin \
		/mnt/vendor/bin/dmenu.bin /mnt/vendor/bin/MainUI /usr/bin/MainUI
	do
		[ -f "$b" ] && chmod a+x "$b" 2>/dev/null || true
	done
	if [ -f "$d/userdata/stock_chmod" ]; then
		while IFS= read -r b; do
			[ -n "$b" ] && [ -f "$b" ] && chmod a+x "$b" 2>/dev/null || true
		done < "$d/userdata/stock_chmod"
	fi
	break
done
exit 0
