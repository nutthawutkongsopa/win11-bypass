# win11-bypass — Install Windows 11 without TPM 2.0, Secure Boot or internet (Ventoy)

**Install Windows 11 on unsupported hardware (no TPM 2.0, older CPU, no Secure Boot, low RAM) and finish setup offline with a local account — no Microsoft account required.** Does what Rufus does, but works with **Ventoy** and runs on **Linux** with a single command.

---

## What it does

| Windows 11 setup problem | win11-bypass |
|---|---|
| "This PC can't run Windows 11" (no TPM 2.0 / Secure Boot / unsupported CPU / low RAM) | ✅ Hardware checks skipped |
| Forced Wi-Fi / internet connection during setup (OOBE) | ✅ Skipped |
| Forced Microsoft account sign-in | ✅ Hidden — you type your own local user name |
| EULA and privacy questions | ✅ Skipped |
| Wiping the wrong disk | ❌ Never touched — you still pick the partition yourself |

Two ways to use it — pick one:

1. **Configure a Ventoy USB** (recommended) — the ISO is left untouched, so any official Microsoft ISO works.
2. **Patch the ISO** — produces a new ISO with the settings built in; use it with Ventoy, Rufus, a VM, anything.

---

## Linux: one command

Open a terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash
```

You get a menu:

```
  [1] Mod ISO            (add autounattend.xml, rebuild ISO)
  [2] Setup Ventoy USB   (no ISO change, uses Ventoy plugins)
  [3] Remove Ventoy config
  [0] Exit
```

- **[1] Mod ISO** — enter the ISO path (e.g. `~/Downloads/Win11_24H2_English_x64.iso`); a `...-bypass.iso` is written next to it.
- **[2] Setup Ventoy USB** — plug in your Ventoy USB (copy the Windows 11 ISO onto it first); the script finds it automatically.
- **[3] Remove** — removes only what this script added; your other Ventoy settings stay.

Without the menu:

```bash
curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash -s -- iso ~/Downloads/Win11.iso
curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash -s -- ventoy /media/$USER/Ventoy
```

**Requirements:** `7z` and `genisoimage` (or `mkisofs`) for ISO mode, `python3` for Ventoy mode — if missing, the script asks before installing them (apt / dnf / pacman / zypper). Free disk space of about 2× the ISO size.

> 💡 [Read the script](get.sh) before running it — a good habit with any `curl | bash` command.

---

## Windows / macOS: configure Ventoy by hand (~2 minutes)

1. Install [Ventoy](https://www.ventoy.net) **1.0.83 or newer** on a USB drive and copy your Windows 11 ISO onto it.
2. Download [`autounattend.xml`](autounattend.xml) and save it on the USB as `ventoy\script\win11-autounattend.xml`.
3. Create or edit `ventoy\ventoy.json` on the USB (change `/Win11.iso` to your file name):

```json
{
    "control": [
        { "VTOY_WIN11_BYPASS_CHECK": "1" },
        { "VTOY_WIN11_BYPASS_NRO": "1" }
    ],
    "auto_install": [
        {
            "image": "/Win11.iso",
            "template": [ "/ventoy/script/win11-autounattend.xml" ],
            "autosel": 1
        }
    ]
}
```

> If `ventoy.json` already exists, add just these entries and keep the rest. Save it as UTF-8 **without BOM**.

---

## Installing Windows 11 after preparing the USB

1. Boot from the USB → pick the Windows 11 ISO in the Ventoy menu (normal mode, not wimboot).
2. Choose language and partition as usual — **no "This PC can't run Windows 11" screen**.
3. After the reboot, at the device setup screens (OOBE) **no internet is needed** → enter a user name and password for your local account.
4. Done 🎉

## FAQ

**Does it work with Windows 11 24H2 / 25H2?** — Yes. ISO patching was tested with build 26300 (UDF, boots in both UEFI and legacy BIOS, handles `install.wim` larger than 4 GB).

**How is this different from Rufus?** — Rufus writes one ISO per USB and runs on Windows only. This works with Ventoy (many ISOs on one USB) and runs on Linux.

**Setup still asks for internet?** — Check that Ventoy is ≥ 1.0.83 and the ISO is booted in normal mode. If a new Windows build closes this path, please open an [issue](https://github.com/nutthawutkongsopa/win11-bypass/issues).

**Is it safe?** — Nothing inside Windows itself is modified; only an `autounattend.xml` (Microsoft's standard answer file) is added. Every line is readable in this repo.

**Will unsupported PCs get updates?** — Microsoft does not guarantee updates on officially unsupported hardware. Use it knowing that risk.

## How it works

- `windowsPE` pass: sets `HKLM\SYSTEM\Setup\LabConfig` `BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`, `BypassCPUCheck`, `BypassStorageCheck`
- `specialize` pass: sets `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE\BypassNRO`
- `oobeSystem` pass: `HideOnlineAccountScreens`, `HideWirelessSetupInOOBE`, `HideEULAPage`, `ProtectYourPC=3`
- No disk, locale, product key or user account settings — setup stays interactive where it matters
- Patched ISO: UDF with both BIOS (`etfsboot.com`) and UEFI (`efisys.bin`) El Torito boot entries

## License

[MIT](LICENSE) — not affiliated with Microsoft or Ventoy.

<!-- keywords: install windows 11 without internet, windows 11 bypass tpm, ventoy windows 11 bypass, windows 11 unsupported hardware, windows 11 local account, bypass tpm 2.0 secure boot, bypassnro, autounattend.xml, rufus alternative linux, windows 11 offline install, ติดตั้ง windows 11 ไม่ต้องต่อเน็ต, windows 11 ข้าม tpm -->
