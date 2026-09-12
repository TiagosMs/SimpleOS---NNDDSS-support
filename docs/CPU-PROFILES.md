# CPU profiles (Power management)

Three profiles for CPU, GPU, and memory (DMC) clocks on the RK3568.
Power save is gone: games ran too poorly.
Balanced was renamed **Conservative**.

Default is **High performance** (`power=3` in `userdata/settings.ini`).

## How to change it

| Action | Control |
| --- | --- |
| Open the list | START → **Power management** |
| Pick a profile | D-pad / stick / touch, then A |
| One step up / down | **Anbernic** button + right analog up / down |

Works on the home screen and in-game. The battery icon (and the OSD) show:

| Profile | Mark |
| --- | --- |
| Conservative | `−` (orange) |
| Performance | `+` |
| High performance | `++` |

## What each profile does

Frequencies are not hard-coded. SimpleOS reads the sysfs lists
(`scaling_available_frequencies` / `available_frequencies`) and picks a step.
If the CPU list is missing, it uses the usual RG DS A55 steps:
408 / 600 / 816 / 1104 / 1416 / 1608 / 1800 / 1992 MHz.

| | Conservative | Performance | High performance |
| --- | --- | --- | --- |
| Code | `1` | `2` | `3` |
| Cap (CPU/GPU/DMC) | mid step | second-to-last | maximum |
| Floor | lowest in the list | lowest in the list | same as the cap (clock locked) |
| CPU governor | `schedutil` | `schedutil` | `performance` |
| GPU/DMC governor | `simple_ondemand` | `performance` | `performance` |

With eight CPU steps, that means:

- **Conservative** — cap ~1104 MHz; the kernel can scale down. GPU/DMC on-demand.
- **Performance** — cap ~1800 MHz, still `schedutil` on the CPU; GPU/DMC at the cap.
- **High performance** — ~1992 MHz on CPU/GPU/DMC, `performance` governor (no scale-down).

If a governor is not in the kernel list, SimpleOS uses `performance`.

## When to use which

- **Conservative** — menus, home, battery: lower clocks, GPU/DMC can drop.
- **Performance** — near the top, with some CPU scale-down left.
- **High performance** — games and the default: clocks pinned, matching the
  “fast boot / no power saving in-game” goal.

## Persistence and re-apply

The value lives in `userdata/settings.ini` (`power=1|2|3`) and in
`/tmp/simpleos_power.live`. `system/apply-power.sh` applies it:

- when `loop.sh` starts
- before DraStic (`run.sh`)
- on wake from sleep (`suspend.sh`, after the temporary `powersave`)
- when you change the profile from the UI or the stick

Log: `/tmp/simpleos-hw.log` (`apply-power` lines).

In sleep the governors switch to `powersave`; on wake the saved profile returns.
Power-off (long POWER) is the PMIC, not this script.

Controls: [CONTROLS.md](CONTROLS.md).
