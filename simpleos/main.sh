#!/bin/sh
# SimpleOS — entry point. Keep this script tiny: every millisecond counts.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export SIMPLEOS_ROOT="$HERE"
export PATH="$HERE/system/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/system/lib:${LD_LIBRARY_PATH:-}"

# Atomic update, same idea as Dedicated OS.
# OTA stages a ready system tree as system.new; zips stay for SD installs.
if [ -d "$HERE/system.new" ] && [ -f "$HERE/system.new/loop.sh" ]; then
	rm -rf "$HERE/system"
	mv "$HERE/system.new" "$HERE/system"
fi
if [ -f "$HERE/system.zip" ]; then
	cd "$HERE"
	rm -rf system.new
	mkdir system.new
	unzip -q system.zip -d system.new
	if [ -d system.new/system ]; then
		rm -rf system
		mv system.new/system system
		rm -rf system.new
	else
		rm -rf system
		mv system.new system
	fi
	rm -f system.zip
fi

mkdir -p "$HERE/userdata" "$HERE/games/archive" "$HERE/bios"
exec "$HERE/system/loop.sh"
