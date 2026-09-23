#!/bin/bash
# NNDDSS RG DS FULL v1.0.1 Stable launcher
DEST=/mnt/vendor/deep/nnddss
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$SELF_DIR/nnddss-rgds-runtime.log"
BOARD="$(tr -d '\r\n\t ' </mnt/vendor/oem/board.ini 2>/dev/null || true)"
[ "$BOARD" = "RGds" ] || { echo "wrong board: $BOARD" >>"$LOG"; exit 1; }

PERSIST_BASE=""
for base in /mnt/mmc /mnt/sdcard; do
  if [ -d "$base/.nnddss-rgds/User" ]; then PERSIST_BASE="$base/.nnddss-rgds"; break; fi
done
[ -n "$PERSIST_BASE" ] || { echo "missing TF-card writable storage (.nnddss-rgds); run NNDDSS-RGDS-install.sh" >>"$LOG"; exit 1; }
USERSTORE="$PERSIST_BASE/User"

export HOME="$PERSIST_BASE/home"
export TMPDIR="$PERSIST_BASE/tmp"
export XDG_CONFIG_HOME="$PERSIST_BASE/xdg-config"
export XDG_CACHE_HOME="$PERSIST_BASE/xdg-cache"
mkdir -p "$USERSTORE/system" "$HOME" "$TMPDIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" 2>/dev/null || true

ROMDIR=""
for d in /mnt/mmc/Roms/NDS /mnt/sdcard/Roms/NDS /mnt/mmc/Roms/nds /mnt/sdcard/Roms/nds; do
  if [ -d "$d" ]; then ROMDIR="$d"; break; fi
done
[ -n "$ROMDIR" ] || ROMDIR=/mnt/mmc/Roms/NDS

export LD_LIBRARY_PATH="$DEST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export NNDDSS_TOUCH_DEV="${NNDDSS_TOUCH_DEV:-/dev/input/event1}"
export NNDDSS_KEYS_DEV="${NNDDSS_KEYS_DEV:-/dev/input/event3}"
export NNDDSS_DEBUG_TOUCH="${NNDDSS_DEBUG_TOUCH:-0}"
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export SDL_GAMECONTROLLERCONFIG='19000000010000000100000000010000,ANBERNIC-keys,a:b1,b:b0,x:b2,y:b3,back:b8,guide:b6,start:b7,leftstick:b9,rightstick:b12,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:b10,righttrigger:b11,platform:Linux,
1900b655010000000100000000010000,ANBERNIC-rk3568-keys,a:b1,b:b0,x:b2,y:b3,back:b8,guide:b6,start:b7,leftstick:b9,rightstick:b12,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:b10,righttrigger:b11,platform:Linux,'

TPCTRL_OLD="$(cat /sys/class/anbernic_misc/tpctrl 2>/dev/null || echo '?')"
RUNAPP_OLD="$(cat /sys/class/anbernic_misc/runapp 2>/dev/null || echo '?')"
SUBSCREEN_WAS_RUNNING=0
if pidof subscreen.dge >/dev/null 2>&1; then
  SUBSCREEN_WAS_RUNNING=1
  killall subscreen.dge >/dev/null 2>&1 || true
  sleep 1
fi
# Tested RG DS touch path: Weston-native 0/0. The final binary does not rewrite tpctrl internally.
[ -w /sys/class/anbernic_misc/tpctrl ] && echo 0 >/sys/class/anbernic_misc/tpctrl 2>/dev/null || true
[ -w /sys/class/anbernic_misc/runapp ] && echo 0 >/sys/class/anbernic_misc/runapp 2>/dev/null || true

printf '\n=== NNDDSS RG DS v1.0.1 Stable run %s ===\n' "$(date 2>/dev/null || echo unknown-time)" >>"$LOG"
printf 'board=%s romdir=%s persist=%s\n' "$BOARD" "$ROMDIR" "$PERSIST_BASE" >>"$LOG"
printf 'touch-route: before tpctrl=%s runapp=%s; active tpctrl=%s runapp=%s\n' \
  "$TPCTRL_OLD" "$RUNAPP_OLD" \
  "$(cat /sys/class/anbernic_misc/tpctrl 2>/dev/null || echo '?')" \
  "$(cat /sys/class/anbernic_misc/runapp 2>/dev/null || echo '?')" >>"$LOG"

# NNDDSS bypasses the stock frontend's RetroArch software volume. Save DAC state,
# apply a quiet NNDDSS-specific persistent level, watch physical volume keys, then restore.
VOLHELPER="$PERSIST_BASE/tools/rgds_volume_helper.py"
VOLSTATE="$PERSIST_BASE/volume.raw"
VOLLOG="$SELF_DIR/nnddss-rgds-volume.log"
ORIG_DAC=""; VOLPID=""
if [ -f "$VOLHELPER" ] && command -v python3 >/dev/null 2>&1; then
  ORIG_DAC="$(python3 "$VOLHELPER" --get 2>/dev/null || true)"
  python3 "$VOLHELPER" --watch "$$" "$VOLSTATE" "$VOLLOG" >/dev/null 2>&1 &
  VOLPID=$!
  sleep 0.15
  printf 'volume-helper: pid=%s original_dac=%s state=%s\n' "$VOLPID" "${ORIG_DAC:-?}" "$(cat "$VOLSTATE" 2>/dev/null || echo '?')" >>"$LOG"
else
  echo 'volume-helper: unavailable' >>"$LOG"
fi

cd "$DEST" || exit 1
"$DEST/nnddss" --root "$DEST" --roms "$ROMDIR" >>"$LOG" 2>&1
RET=$?
printf 'exit=%s\n' "$RET" >>"$LOG"

if [ -n "$VOLPID" ]; then kill "$VOLPID" >/dev/null 2>&1 || true; wait "$VOLPID" 2>/dev/null || true; fi
if [ -n "$ORIG_DAC" ] && [ -f "$VOLHELPER" ]; then python3 "$VOLHELPER" --set-once "$ORIG_DAC" >/dev/null 2>&1 || true; fi

if [ "$SUBSCREEN_WAS_RUNNING" = 1 ] && [ -x /mnt/vendor/subscreen/launch.sh ]; then
  /mnt/vendor/subscreen/launch.sh /mnt/vendor/subscreen/default bk.jpg 0 >/dev/null 2>&1 &
else
  case "$TPCTRL_OLD" in 0|1) [ -w /sys/class/anbernic_misc/tpctrl ] && echo "$TPCTRL_OLD" >/sys/class/anbernic_misc/tpctrl 2>/dev/null || true;; esac
  case "$RUNAPP_OLD" in 0|1) [ -w /sys/class/anbernic_misc/runapp ] && echo "$RUNAPP_OLD" >/sys/class/anbernic_misc/runapp 2>/dev/null || true;; esac
fi
exit "$RET"
