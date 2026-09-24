#!/bin/bash
# NNDDSS RG DS FULL v1.0.1 Stable installer
# Direct fresh-firmware installer: no v0.1-v0.7 hotfix chain is required.
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$SELF_DIR/payload"
DEST=/mnt/vendor/deep/nnddss
LOG="$SELF_DIR/nnddss-rgds-v1.0.1-install.log"
exec >>"$LOG" 2>&1

log(){ echo "[v1.0.1] $*"; }
fail(){ echo "ERROR: $*"; sync; exit 1; }

printf '\n=== NNDDSS RG DS FULL v1.0.1 install %s ===\n' "$(date 2>/dev/null || echo unknown-time)"
BOARD="$(tr -d '\r\n\t ' </mnt/vendor/oem/board.ini 2>/dev/null || true)"
log "board=$BOARD"
[ "$BOARD" = "RGds" ] || fail "This package is only for original RG DS (board RGds); detected '$BOARD'."
[ -x "$PAYLOAD/nnddss" ] || fail "payload/nnddss missing"
[ -d "$PAYLOAD/lib" ] || fail "payload/lib missing"
[ -d "$PAYLOAD/shaders" ] || fail "payload/shaders missing"
[ -f "$PAYLOAD/tools/rgds_volume_helper.py" ] || fail "volume helper missing"

EXPECTED_BIN_SHA=c18fe24ad236f0b8b2c47c45ab833487af8111da7f04751de9f09719988b4468
GOT_BIN_SHA="$(sha256sum "$PAYLOAD/nnddss" 2>/dev/null | awk '{print $1}')"
[ "$GOT_BIN_SHA" = "$EXPECTED_BIN_SHA" ] || fail "final NNDDSS binary checksum mismatch: $GOT_BIN_SHA"

# Choose the writable ROM partition. This is where NNDDSS User/assets live so the
# tiny /mnt/vendor system partition is not consumed by saves, fonts or databases.
PERSIST_MOUNT=""
for base in /mnt/mmc /mnt/sdcard; do
  [ -d "$base" ] || continue
  probe="$base/.nnddss-rgds-write-test.$$"
  if (: >"$probe") 2>/dev/null; then rm -f "$probe"; PERSIST_MOUNT="$base"; break; fi
done
[ -n "$PERSIST_MOUNT" ] || fail "No writable TF-card mount found at /mnt/mmc or /mnt/sdcard."
PERSIST_BASE="$PERSIST_MOUNT/.nnddss-rgds"
USERSTORE="$PERSIST_BASE/User"
ASSETSTORE="$PERSIST_BASE/assets"
TOOLSTORE="$PERSIST_BASE/tools"
mkdir -p "$USERSTORE" "$ASSETSTORE" "$TOOLSTORE" "$PERSIST_BASE/backups" \
  "$PERSIST_BASE/home" "$PERSIST_BASE/tmp" "$PERSIST_BASE/xdg-config" "$PERSIST_BASE/xdg-cache" \
  || fail "Cannot create NNDDSS storage on TF card."

# Keep a prior executable on the TF card; never waste vendor-partition space on backups.
if [ -f "$DEST/nnddss" ]; then
  OLD_SHA="$(sha256sum "$DEST/nnddss" 2>/dev/null | awk '{print $1}')"
  if [ "$OLD_SHA" != "$EXPECTED_BIN_SHA" ] && [ ! -f "$PERSIST_BASE/backups/nnddss-before-v1.0.1" ]; then
    cp -p "$DEST/nnddss" "$PERSIST_BASE/backups/nnddss-before-v1.0.1" 2>/dev/null || true
  fi
fi
mkdir -p "$DEST/lib" || fail "Cannot create $DEST/lib"

migrate_tree(){
  src="$1"; dst="$2"; label="$3"
  mkdir -p "$dst" || fail "Cannot create $dst"
  if [ -L "$src" ]; then
    old="$(readlink "$src" 2>/dev/null || true)"
    if [ "$old" != "$dst" ]; then
      [ -d "$src" ] && cp -rf "$src/." "$dst/" 2>/dev/null || true
      rm -f "$src" || fail "Cannot replace $label symlink"
      ln -s "$dst" "$src" || fail "Cannot link $src -> $dst"
    fi
  elif [ -d "$src" ]; then
    cp -rf "$src/." "$dst/" || fail "Cannot migrate existing $label to TF card"
    sync
    rm -rf "$src" || fail "Cannot remove old $label directory after migration"
    ln -s "$dst" "$src" || fail "Cannot link $src -> $dst"
  elif [ -e "$src" ]; then
    fail "$src exists but is not a directory/symlink"
  else
    ln -s "$dst" "$src" || fail "Cannot link $src -> $dst"
  fi
}

# Install tested final launcher binary + official 1.0.2 libraries.
cp -f "$PAYLOAD/nnddss" "$DEST/nnddss" || fail "Copying final NNDDSS executable failed"
chmod +x "$DEST/nnddss"
cp -rf "$PAYLOAD/lib/." "$DEST/lib/" || fail "Copying NNDDSS libraries failed"
rm -f "$DEST/lib/libc.so" "$DEST/lib/libm.so" "$DEST/lib/libdl.so" "$DEST/lib/liblog.so" \
      "$DEST/lib/libz.so" "$DEST/lib/libGLESv2.so" "$DEST/lib/libOpenSLES.so" "$DEST/lib/libstdc++.so"

migrate_tree "$DEST/User" "$USERSTORE" "User"
migrate_tree "$DEST/assets" "$ASSETSTORE" "assets"
mkdir -p "$USERSTORE/system" "$USERSTORE/shaders" "$ASSETSTORE/bios" "$ASSETSTORE/fonts" \
         "$ASSETSTORE/shaders" "$ASSETSTORE/ui" || fail "Cannot create NNDDSS data directories"

cp -rf "$PAYLOAD/shaders/." "$USERSTORE/shaders/" || fail "Copying User shaders failed"
cp -rf "$PAYLOAD/shaders/." "$ASSETSTORE/shaders/" || fail "Copying asset shaders failed"
cp -rf "$PAYLOAD/ui/." "$ASSETSTORE/ui/" || fail "Copying UI fallback assets failed"
cp -f "$PAYLOAD/gamecontrollerdb.txt" "$USERSTORE/gamecontrollerdb.txt" || fail "Controller DB copy failed"
cp -f "$PAYLOAD/gamecontrollerdb.txt" "$DEST/gamecontrollerdb.txt" 2>/dev/null || true
cp -f "$PAYLOAD/tools/rgds_volume_helper.py" "$TOOLSTORE/rgds_volume_helper.py" || fail "Volume helper install failed"
chmod +x "$TOOLSTORE/rgds_volume_helper.py"

# Fonts: do not bundle vendor fonts. Reuse fonts from the freshly-flashed official RG DS image.
find_font(){
  mode="$1"; out=""
  roots="/usr/share/fonts /mnt/vendor/bin/ebook/resources/fonts /mnt/mod/ctrl/configs"
  if [ "$mode" = zh ]; then
    for pat in 'SourceHanSans.*\.(ttf|otf)$' 'NotoSansCJK.*\.(ttf|otf)$' 'LiHei\.ttf$' '/default\.ttf$'; do
      out="$(find $roots -type f 2>/dev/null | grep -Ei "$pat" | head -n 1 || true)"; [ -n "$out" ] && break
    done
  else
    for pat in 'DejaVuSans\.ttf$' 'LiberationSans.*\.ttf$' 'NotoSans.*\.ttf$' '/default\.ttf$'; do
      out="$(find $roots -type f 2>/dev/null | grep -Ei "$pat" | head -n 1 || true)"; [ -n "$out" ] && break
    done
  fi
  [ -n "$out" ] || out="$(find $roots -type f 2>/dev/null | grep -Ei '\.(ttf|otf)$' | head -n 1 || true)"
  echo "$out"
}
EN_FONT="$(find_font en)"
ZH_FONT="$(find_font zh)"; [ -n "$ZH_FONT" ] || ZH_FONT="$EN_FONT"
if [ ! -s "$ASSETSTORE/fonts/orbitron.ttf" ] && [ -n "$EN_FONT" ]; then cp "$EN_FONT" "$ASSETSTORE/fonts/orbitron.ttf" && log "font orbitron alias <- $EN_FONT"; fi
if [ ! -s "$ASSETSTORE/fonts/SourceHanSansSC-Normal.ttf" ] && [ -n "$ZH_FONT" ]; then cp "$ZH_FONT" "$ASSETSTORE/fonts/SourceHanSansSC-Normal.ttf" && log "Chinese font <- $ZH_FONT"; fi

# Locate stock DraStic data in the official RG DS firmware. The full port archive intentionally
# does not redistribute Nintendo/firmware BIOS files; a fresh official image already contains them.
find_stock(){
  names="$1"
  for dir in /mnt/vendor/deep/drastic64/system /mnt/vendor/deep/drastic64 \
             /mnt/vendor/deep/drastic_aarch64/system /mnt/vendor/deep/drastic_aarch64 \
             /oem/retro/system /oem/retro /mnt/vendor/deep; do
    [ -d "$dir" ] || continue
    for n in $names; do
      f="$(find "$dir" -maxdepth 4 -type f -name "$n" 2>/dev/null | grep -v '/nnddss/' | head -n 1 || true)"
      if [ -n "$f" ]; then echo "$f"; return 0; fi
    done
  done
  return 1
}

BIOS7="$(find_stock 'drastic_bios_arm7.bin nds_bios_arm7.bin' || true)"
BIOS9="$(find_stock 'drastic_bios_arm9.bin nds_bios_arm9.bin' || true)"
FW="$(find_stock 'nds_firmware.bin nds_firmware_modified.bin firmware.bin' || true)"
GDB="$(find_stock 'game_database.xml' || true)"
CHEAT="$(find_stock 'usrcheat.dat' || true)"

[ -n "$BIOS7" ] && cp -f "$BIOS7" "$ASSETSTORE/bios/drastic_bios_arm7.bin" && cp -f "$BIOS7" "$USERSTORE/system/drastic_bios_arm7.bin"
[ -n "$BIOS9" ] && cp -f "$BIOS9" "$ASSETSTORE/bios/drastic_bios_arm9.bin" && cp -f "$BIOS9" "$USERSTORE/system/drastic_bios_arm9.bin"
# Also provide the alternate names used by some DraStic paths.
[ -s "$USERSTORE/system/drastic_bios_arm7.bin" ] && cp -f "$USERSTORE/system/drastic_bios_arm7.bin" "$USERSTORE/system/nds_bios_arm7.bin"
[ -s "$USERSTORE/system/drastic_bios_arm9.bin" ] && cp -f "$USERSTORE/system/drastic_bios_arm9.bin" "$USERSTORE/system/nds_bios_arm9.bin"
if [ -n "$FW" ]; then
  cp -f "$FW" "$ASSETSTORE/bios/nds_firmware.bin"
  cp -f "$FW" "$USERSTORE/system/nds_firmware.bin"
  cp -f "$FW" "$USERSTORE/system/nds_firmware_modified.bin"
fi
if [ -n "$GDB" ]; then cp -f "$GDB" "$ASSETSTORE/game_database.xml"; cp -f "$GDB" "$USERSTORE/game_database.xml"; fi
if [ -n "$CHEAT" ]; then
  [ -s "$USERSTORE/usrcheat.dat" ] && [ ! -f "$PERSIST_BASE/backups/usrcheat.dat-before-v1.0.1" ] && cp -p "$USERSTORE/usrcheat.dat" "$PERSIST_BASE/backups/usrcheat.dat-before-v1.0.1" 2>/dev/null || true
  cp -f "$CHEAT" "$USERSTORE/usrcheat.dat" || fail "Copying stock usrcheat.dat failed"
  rm -f "$USERSTORE/usrcheat_zh.dat"
  ln -s usrcheat.dat "$USERSTORE/usrcheat_zh.dat" 2>/dev/null || cp -f "$USERSTORE/usrcheat.dat" "$USERSTORE/usrcheat_zh.dat"
fi

# Final integrity/status checks.
INST_SHA="$(sha256sum "$DEST/nnddss" 2>/dev/null | awk '{print $1}')"
[ "$INST_SHA" = "$EXPECTED_BIN_SHA" ] || fail "Installed executable verification failed: $INST_SHA"
STATUS=0
for f in "$ASSETSTORE/ui/bg.png" "$ASSETSTORE/ui/icon.png" "$ASSETSTORE/fonts/orbitron.ttf" "$ASSETSTORE/fonts/SourceHanSansSC-Normal.ttf"; do
  [ -s "$f" ] || { log "MISSING: $f"; STATUS=2; }
done
for f in "$ASSETSTORE/bios/drastic_bios_arm7.bin" "$ASSETSTORE/bios/drastic_bios_arm9.bin"; do
  [ -s "$f" ] || { log "MISSING stock BIOS source: $f"; STATUS=2; }
done
[ -s "$USERSTORE/usrcheat.dat" ] || { log "WARNING: stock usrcheat.dat was not found"; STATUS=2; }

chmod +x "$SELF_DIR/NNDDSS-RGDS.sh" "$SELF_DIR/NNDDSS-RGDS-diagnose.sh" \
  "$SELF_DIR/NNDDSS-RGDS-backup-userdata.sh" "$SELF_DIR/NNDDSS-RGDS-restore-userdata.sh" \
  "$SELF_DIR/NNDDSS-RGDS-uninstall-core.sh" 2>/dev/null || true

cat > "$PERSIST_BASE/rgds-port-meta-v1.0.1" <<EOF
version=v1.0.1-stable
binary_sha256=$EXPECTED_BIN_SHA
touch_route=weston-native-0-0
touch_release=BTN_TOUCH-clears-MT-slot
ui=640x480-clean-solid-background
controller=nintendo-labels-ABXY
cheats=stock-drastic-usrcheat-with-zh-alias
volume=alsa-card0-numid15-helper
fast_forward_audio=enabled-host-mute-suppressed
EOF
sync

echo "--- storage ---"
df -h /mnt/vendor "$PERSIST_MOUNT" 2>/dev/null || true
log "persistent data: $PERSIST_BASE"
log "User link: $(readlink "$DEST/User" 2>/dev/null || echo ERROR)"
log "assets link: $(readlink "$DEST/assets" 2>/dev/null || echo ERROR)"
log "final binary: $INST_SHA"
if [ "$STATUS" -eq 0 ]; then
  log "INSTALL COMPLETE. Run NNDDSS-RGDS.sh"
  exit 0
else
  log "INSTALL COMPLETE WITH MISSING STOCK DATA. Run NNDDSS-RGDS-diagnose.sh and inspect this log."
  exit 2
fi
