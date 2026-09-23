#!/bin/sh
# Anbernic official Linux: launch SimpleOS instead of the stock frontend.
# Copy to Roms/APPS as SimpleOS.sh, or use overlay/stock-linux/install-boot.sh
# so loadapp starts SimpleOS at boot (Anbernic /mnt/mod/ctrl/autostart).

unset SIMPLEOS_NOPOWEROFF
unset SIMPLEOS_NORESUME
unset SSH_CONNECTION
unset SSH_CLIENT

for d in \
	"${SIMPLEOS_ROOT:-}" \
	/mnt/mmc/simpleos \
	/mnt/SDCARD/simpleos
do
	[ -n "$d" ] && [ -x "$d/main.sh" ] && exec "$d/main.sh"
done

echo "simpleos: main.sh not found" >&2
exit 1
