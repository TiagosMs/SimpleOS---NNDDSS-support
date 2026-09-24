<p align="center">
  <img src="docs/images/logo.png" alt="SimpleOS for Anbernic RG DS" width="720">
</p>

# SimpleOS — NNDDSS Support & Quick Stock Switch Edition

Custom fork of the official [SimpleOS](https://github.com/boorngos/SimpleOS) by **[TiagosMs](https://github.com/TiagosMs)** for the **[Anbernic RG DS](https://anbernic.com/)** handheld console.

This edition features **out-of-the-box NNDDSS emulator support** and a **quick switch shortcut to the original Anbernic Stock OS**, directly accessible from the SimpleOS game carousel.

---

## 🌟 What's New in this Fork?

### 1. 🚀 Out-of-the-Box NNDDSS Emulator Support
- The **NNDDSS** emulator (v1.0.1 Stable) is directly bundled inside the SimpleOS installer.
- When running the SimpleOS installation, NNDDSS is automatically deployed to `/mnt/vendor/deep/nnddss` and configured on the SD card.
- A trigger named **`NNDDSS EMUL`** is pre-installed in your game library. When launched:
  - The NNDDSS emulator opens with its native dual-screen rendering, shaders, and features.
  - Exiting NNDDSS **returns smoothly to the SimpleOS interface**.

### 2. 🔄 Quick Return to Original System (`Voltar Stock`)
- No more taking out the SD card to create manual trigger files on a PC: a **`VOLTAR STOCK`** card is available in your carousel.
- When selected:
  - The console sets the boot flag and reboots directly into the official Anbernic OS, giving you access to all other platforms (GBA, SNES, PS1, etc.), video player, and stock apps.
  - To return to SimpleOS later: go to **Applications** → **APPS** → **`SimpleOS`**.

### 3. ⚙️ Optimized `run.sh` and `loop.sh`
- The launcher dispatcher ([`run.sh`](simpleos/system/run.sh)) intercepts custom app triggers before DraStic is called.
- The process manager ([`loop.sh`](simpleos/system/loop.sh)) monitors both DraStic and NNDDSS lifecycles, ensuring clean transitions without Wayland compositor hangs.

---

## 📥 Installation

1. Download the latest `.zip` package from the [Releases](https://github.com/TiagosMs/SimpleOS---NNDDSS-support/releases) page.
2. On your PC, open the **ROMS** partition of your RG DS SD card (the one containing `Roms/`, `Emu/`, etc.).
3. Extract the contents of the zip file directly into the **root** of that partition (merge folders if prompted).
4. Safely eject the SD card, insert it into the RG DS, and power on.
5. In the official Anbernic menu, navigate to: **Applications** → **APPS** → launch **`Install SimpleOS`**.
6. Wait for the splash screens on both displays to complete (do not power off).
7. The device will automatically reboot into **SimpleOS** with **NNDDSS** and **Voltar Stock** ready to use!

---

## 🎮 Controls in SimpleOS

| Action | Control |
| :--- | :--- |
| Open / close in-game menu | **Home / Back (Menu button)** |
| Navigate in-game menu | **D-Pad Left / Right** |
| Fast-forward | **Anbernic** + **SELECT** |
| Save / Load state | **Anbernic** + **L2** / **R2** |
| Virtual microphone | **R3** (Right analog stick press) |
| Toggle FPS counter | **Anbernic** + **X** |
| Screen Brightness | **Anbernic** + **L1** (Decrease) / **R1** (Increase) |
| Night mode | Below the minimum brightness level |
| Sleep | Quick tap on **POWER** or close the lid |
| Power off | Long press **POWER** |

---

## 🔧 Troubleshooting

### Black screen when opening NNDDSS (returns to SimpleOS after 2 seconds)
If launching `NNDDSS EMUL` flashes a black screen for a couple of seconds and drops back to the SimpleOS main menu:
1. Select the **`VOLTAR STOCK`** card in SimpleOS to enter the stock Anbernic system.
2. In the Anbernic menu, navigate to **Applications** → **APPS**.
3. Run **`NNDDSS-RGDS-install.sh`** (this automatically links the necessary system fonts and stock DraStic BIOS into the `.nnddss-rgds/` directory).
4. Launch **`SimpleOS`** from **APPS** to return to SimpleOS. NNDDSS will now open properly.

---

## 📜 Credits and License

- **[boorngos](https://github.com/boorngos/SimpleOS)** — Creator of the original SimpleOS for RG DS.
- **[TiagosMs](https://github.com/TiagosMs)** — Customization, NNDDSS integration, and Stock OS switch feature.
- NNDDSS RG DS Community — For the stable RG DS patches and wrappers.
- License: **MIT License**. See [LICENSE](LICENSE) for details.
