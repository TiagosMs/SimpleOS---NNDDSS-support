SimpleOS for Anbernic RG DS
==============================

Overlay on official Anbernic Linux. It does not replace the kernel and
does not flash U-Boot. DraStic and Nintendo BIOS files are not included:
use the copies already present on the Anbernic firmware.

Installation
------------
1. Flash official Anbernic Linux onto the TF card (Anbernic tool).
   Boot it at least once if the firmware asks you to.
2. On a PC, open the user partition of that card (the one with Roms/).
3. Copy the CONTENTS of this zip into the root of that partition,
   next to Roms/, without creating an extra folder:
      simpleos/
      simpleos/install/
      .simpleos_update/
      Roms/APPS/Install SimpleOS.sh
      README.txt
   If Windows asks to merge Roms/, confirm.
4. Eject the card, insert it in the RG DS, power on.
5. In the Anbernic menu open APPS and launch "Install SimpleOS".
   SimpleOS splash screens appear on both displays. Do not power off.
   The device reboots into SimpleOS by itself.

First install: Wi-Fi and SSH are off. START -> Network -> Wi-Fi
turns the radio on, then you can scan.

Games
-----
Put .nds / .dsi / .zip files in:
  simpleos/games
and/or the stock NDS folder (Roms/NDS).

Controls
--------
Home: START opens options (Network, Update, Game settings,
Power management). MENU on a highlighted title opens This
game (Auto-load, Auto-resume, HIGH RES 3D, Shader, Controls).
MENU+L1 / MENU+R1 brightness; below the minimum is NIGHT.
Anbernic + right analog: Conservative / Performance /
High performance. Tap POWER or close the lid for sleep;
long POWER powers off.

In game: MENU opens RESUME / SAVE / LOAD / ARCHIVE / VIDEO /
CONTROLS / RESET / HOME. Left/right change title. Tap a voice
on the touch screen to highlight; second tap confirms.
Anbernic+SELECT fast-forward, Anbernic+L2 load (LOADED),
Anbernic+R2 save (SAVED), Anbernic+X FPS. R3 is the virtual
microphone. MENU+POWER unlocks a freeze (hangmon).

VIDEO: this game only. HIGH RES 3D ON / OFF (A apply, restarts
DraStic). SHADER with left/right (←/→). CONTROLS: this game
only; A bind, X add, DEFAULT clears. Game settings: START for
global Auto-load / Auto-resume / HIGH RES 3D / Shader; MENU
on a title for GLOBAL / ON / OFF (shader cycles names).

Changelog
---------
See CHANGELOG.txt in this zip (also copied to simpleos/CHANGELOG.txt).

Update
------
From the home screen: START -> Update.
- OTA — needs Wi-Fi. Reads the latest GitHub release
  (SimpleOS-RGDS-YYYYMMDD.zip). Confirm Update now; do not
  power off. The device reboots by itself.
- Manual update — copy the zip next to Roms/, then pick the
  file from the list. Same screen as OTA; the zip is deleted
  if the install succeeds.

On a PC you can also replace simpleos/ (or copy system.zip
into simpleos/) and run APPS -> Install SimpleOS again.
This zip is a local install package.

Return to Anbernic
------------------
Create the empty file:
  simpleos/userdata/boot_stock
Then reboot. Original logos are kept as *.anbernic next to the replacements.

Do not power off the RG DS during installation.
