#!/bin/sh
# Anbernic APPS entry: first-time install / repair of SimpleOS.
set -u

for d in /mnt/mmc /mnt/SDCARD; do
	for p in \
		"$d/.simpleos_update/install.sh" \
		"$d/simpleos_update/install.sh" \
		"$d/simpleos/install/install.sh"
	do
		[ -f "$p" ] || continue
		sed -i 's/\r$//' "$p" 2>/dev/null || true
		chmod 755 "$p" 2>/dev/null || true
		exec /bin/sh "$p"
	done
done

echo "simpleos: installer not found (.simpleos_update/install.sh)" >&2
exit 1
