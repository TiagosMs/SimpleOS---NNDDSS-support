#!/usr/bin/env python3
"""RG DS stock-Linux volume helper for NNDDSS.

Watches the physical volume keys and controls ALSA card 0, numid=15
(DAC Playback Volume).  NNDDSS uses its own audio path, so the stock
frontend's RetroArch software-volume value does not control it directly.
"""
import os
import re
import select
import struct
import subprocess
import sys
import time

EV_KEY = 1
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
EVENTS = ("/dev/input/event4", "/dev/input/event5")
EVENT_STRUCT = struct.Struct("llHHi")
MIN_NONZERO = 40
MAX_VOL = 255
STEP = 15
DEFAULT_CAP = 85
LOG_DEFAULT = "/tmp/nnddss-rgds-volume.log"


def log(msg, path=LOG_DEFAULT):
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(time.strftime("%H:%M:%S ") + str(msg) + "\n")
    except Exception:
        pass


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)
    return env


def amixer_path():
    for p in ("/usr/bin/amixer", "/bin/amixer", "/usr/sbin/amixer", "/sbin/amixer"):
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return "amixer"


def get_volume():
    cmd = [amixer_path(), "-c", "0", "cget", "numid=15"]
    out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True, env=clean_env())
    m = re.search(r": values=(\d+),(\d+)", out)
    if not m:
        m = re.search(r": values=(\d+)", out)
    if not m:
        raise RuntimeError("could not parse numid=15")
    return int(m.group(1))


def set_volume(vol):
    vol = max(0, min(MAX_VOL, int(vol)))
    cmd = [amixer_path(), "-q", "-c", "0", "cset", "numid=15", f"{vol},{vol}"]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   env=clean_env(), check=True)
    return vol


def read_state(path):
    try:
        with open(path, "r", encoding="ascii") as fh:
            v = int(fh.read().strip())
        return max(0, min(MAX_VOL, v))
    except Exception:
        return None


def write_state(path, value):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="ascii") as fh:
            fh.write(str(int(value)) + "\n")
        os.replace(tmp, path)
    except Exception as exc:
        log(f"state write failed: {exc}")


def retroarch_db_volume():
    # The stock Linux frontend persists its UI volume as RetroArch dB.
    for path in ("/.config/retroarch/retroarch_volume.cfg",
                 "/root/.config/retroarch/retroarch_volume.cfg"):
        try:
            text = open(path, "r", encoding="utf-8", errors="ignore").read()
        except Exception:
            continue
        m = re.search(r'audio_volume\s*=\s*"?(-?\d+(?:\.\d+)?)', text)
        if not m:
            continue
        db = float(m.group(1))
        # Conservative mapping: UI values near mute map to the quietest useful
        # DAC value; 0 dB maps to full hardware range.
        if db <= -60.0:
            return MIN_NONZERO
        if db >= 0.0:
            return MAX_VOL
        return int(round(MIN_NONZERO + (db + 60.0) / 60.0 * (MAX_VOL - MIN_NONZERO)))
    return None


def initial_volume(state_path):
    saved = read_state(state_path)
    if saved is not None:
        return saved
    from_ui = retroarch_db_volume()
    if from_ui is not None:
        return from_ui
    try:
        # Do not allow an unknown high mixer state to blast at first launch.
        return min(get_volume(), DEFAULT_CAP)
    except Exception:
        return MIN_NONZERO


def next_volume(cur, direction):
    if direction < 0:
        if cur <= MIN_NONZERO:
            return 0
        return max(MIN_NONZERO, cur - STEP)
    if cur == 0:
        return MIN_NONZERO
    return min(MAX_VOL, cur + STEP)


def parent_alive(ppid):
    if ppid <= 1:
        return True
    try:
        os.kill(ppid, 0)
        return True
    except OSError:
        return False


def watch(ppid, state_path, log_path):
    level = initial_volume(state_path)
    try:
        level = set_volume(level)
        write_state(state_path, level)
        log(f"init volume={level}", log_path)
    except Exception as exc:
        log(f"initial mixer set failed: {exc}", log_path)

    fds = []
    for path in EVENTS:
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            fds.append(fd)
            log(f"watching {path}", log_path)
        except OSError as exc:
            log(f"cannot open {path}: {exc}", log_path)
    if not fds:
        return 1

    try:
        while parent_alive(ppid):
            readable, _, _ = select.select(fds, [], [], 1.0)
            for fd in readable:
                try:
                    data = os.read(fd, EVENT_STRUCT.size * 32)
                except BlockingIOError:
                    continue
                for off in range(0, len(data) - EVENT_STRUCT.size + 1, EVENT_STRUCT.size):
                    _sec, _usec, ev_type, code, value = EVENT_STRUCT.unpack(
                        data[off:off + EVENT_STRUCT.size])
                    if ev_type != EV_KEY or value not in (1, 2):
                        continue
                    direction = 0
                    if code == KEY_VOLUMEDOWN:
                        direction = -1
                    elif code == KEY_VOLUMEUP:
                        direction = 1
                    if not direction:
                        continue
                    try:
                        # Read the real mixer in case another process changed it.
                        cur = get_volume()
                    except Exception:
                        cur = level
                    target = next_volume(cur, direction)
                    try:
                        level = set_volume(target)
                        write_state(state_path, level)
                        log(f"key code={code} value={value} volume={level}", log_path)
                    except Exception as exc:
                        log(f"adjust failed: {exc}", log_path)
    finally:
        for fd in fds:
            try:
                os.close(fd)
            except OSError:
                pass
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "--get":
        print(get_volume())
        return 0
    if len(argv) >= 3 and argv[1] == "--set-once":
        set_volume(int(argv[2]))
        return 0
    if len(argv) >= 3 and argv[1] == "--down":
        state = argv[2]
        cur = read_state(state)
        if cur is None:
            cur = initial_volume(state)
        cur = set_volume(next_volume(cur, -1))
        write_state(state, cur)
        print(cur)
        return 0
    if len(argv) >= 3 and argv[1] == "--up":
        state = argv[2]
        cur = read_state(state)
        if cur is None:
            cur = initial_volume(state)
        cur = set_volume(next_volume(cur, 1))
        write_state(state, cur)
        print(cur)
        return 0
    if len(argv) >= 4 and argv[1] == "--watch":
        ppid = int(argv[2])
        state = argv[3]
        log_path = argv[4] if len(argv) >= 5 else LOG_DEFAULT
        return watch(ppid, state, log_path)
    print("usage: rgds_volume_helper.py --watch PPID STATE [LOG] | --get | --set-once N | --up STATE | --down STATE", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
