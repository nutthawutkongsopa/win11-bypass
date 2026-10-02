# win11-bypass — ติดตั้ง Windows 11 ไม่ต้องต่อเน็ต ข้าม TPM 2.0 / Secure Boot ผ่าน Ventoy

**ติดตั้ง Windows 11 บนเครื่องสเป็คไม่ถึง (ไม่มี TPM 2.0, CPU รุ่นเก่า, ไม่มี Secure Boot) และสร้างบัญชี Local Account ได้โดยไม่ต้องต่ออินเทอร์เน็ต ไม่ต้องใช้ Microsoft Account** — ทำได้เหมือน Rufus แต่ใช้กับ **Ventoy** ได้ และรันบน **Linux** ได้ด้วยคำสั่งเดียว

> English: Install Windows 11 on unsupported hardware (bypass TPM 2.0, Secure Boot, RAM, CPU checks) and skip the forced internet / Microsoft account (BypassNRO, local account) — a Rufus-style `autounattend.xml` for **Ventoy** users, plus a one-command Linux script to patch the ISO. [Jump to English guide ↓](#english)

---

## ทำอะไรได้บ้าง

| ปัญหาตอนติดตั้ง Windows 11 | win11-bypass |
|---|---|
| "This PC can't run Windows 11" (ไม่มี TPM 2.0 / Secure Boot / CPU ไม่รองรับ / RAM น้อย) | ✅ ข้ามการเช็คสเป็ค |
| บังคับต่อ Wi-Fi / อินเทอร์เน็ตตอนตั้งค่าเครื่อง (OOBE) | ✅ ข้ามได้ |
| บังคับล็อกอิน Microsoft Account | ✅ ซ่อนหน้า MS Account — พิมพ์ชื่อผู้ใช้ Local เอง |
| หน้า EULA / คำถามความเป็นส่วนตัว | ✅ ข้ามให้ |
| ล้างดิสก์ผิดลูก | ❌ ไม่แตะ — ยังเลือกพาร์ติชันเองเหมือนปกติ |

ใช้ได้ 2 แบบ เลือกอย่างใดอย่างหนึ่ง:

1. **ตั้งค่า USB Ventoy** (แนะนำ) — ไม่ต้องแก้ไฟล์ ISO, ใช้ ISO ต้นฉบับจาก Microsoft ได้ทุกเวอร์ชัน
2. **แก้ไฟล์ ISO** — ได้ ISO ใหม่ที่ฝังการตั้งค่าไว้แล้ว เอาไปใช้กับ Ventoy, Rufus หรือ VM ได้ทุกที่

---

## วิธีใช้บน Linux (คำสั่งเดียว)

เปิด Terminal แล้ววาง:

```bash
curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash
```

จะขึ้นเมนู:

```
  [1] Mod ISO            (add autounattend.xml, rebuild ISO)
  [2] Setup Ventoy USB   (no ISO change, uses Ventoy plugins)
  [3] Remove Ventoy config
  [0] Exit
```

- **[1] Mod ISO** — ใส่ path ไฟล์ ISO (เช่น `~/Downloads/Win11_24H2_Thai_x64.iso`) จะได้ไฟล์ `...-bypass.iso` อยู่ข้าง ๆ กัน
- **[2] Setup Ventoy USB** — เสียบ USB ที่ลง Ventoy ไว้ (คัดลอก ISO Windows 11 ลง USB ก่อน) สคริปต์จะหา USB เอง
- **[3] Remove** — ลบการตั้งค่าที่สคริปต์ใส่ไว้ ไม่แตะการตั้งค่าอื่นของ Ventoy

แบบไม่ผ่านเมนู:

```bash
curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash -s -- iso ~/Downloads/Win11.iso
curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash -s -- ventoy /media/$USER/Ventoy
```

**ต้องมี:** `7z` และ `genisoimage` (หรือ `mkisofs`) สำหรับโหมด ISO, `python3` สำหรับโหมด Ventoy — ถ้าไม่มี สคริปต์จะถามก่อนติดตั้งให้ (รองรับ apt / dnf / pacman / zypper) • พื้นที่ว่างประมาณ 2 เท่าของขนาด ISO

> 💡 แนะนำให้ [อ่านสคริปต์](get.sh) ก่อนรันทุกครั้ง — เป็นนิสัยที่ดีกับคำสั่ง `curl | bash` ทุกตัว

---

## วิธีใช้บน Windows / macOS (ตั้งค่า Ventoy ด้วยมือ ~2 นาที)

1. ติดตั้ง [Ventoy](https://www.ventoy.net) ลง USB (เวอร์ชัน **1.0.83 ขึ้นไป**) แล้วคัดลอกไฟล์ ISO Windows 11 ลงไป
2. ดาวน์โหลด [`autounattend.xml`](autounattend.xml) ไปวางที่ `ventoy\script\win11-autounattend.xml` บน USB
3. สร้าง/แก้ไฟล์ `ventoy\ventoy.json` บน USB (เปลี่ยน `/Win11.iso` ให้ตรงชื่อไฟล์ของคุณ):

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

> ถ้ามี `ventoy.json` อยู่แล้ว ให้เพิ่มเฉพาะรายการด้านบนเข้าไป อย่าลบของเดิม และบันทึกเป็น UTF-8 (ไม่มี BOM)

---

## ขั้นตอนติดตั้ง Windows 11 หลังเตรียม USB

1. บูตเครื่องจาก USB → เลือก ISO Windows 11 ในเมนู Ventoy (โหมดปกติ ไม่ใช่ wimboot)
2. เลือกภาษา / พาร์ติชันตามปกติ — **จะไม่เจอหน้า "This PC can't run Windows 11"**
3. หลังรีสตาร์ท ถึงหน้าตั้งค่าเครื่อง (OOBE) **ไม่ต้องต่อเน็ต** → พิมพ์ชื่อผู้ใช้และรหัสผ่านของ Local Account
4. เสร็จ 🎉

## คำถามที่พบบ่อย (FAQ)

**ใช้กับ Windows 11 24H2 / 25H2 ได้ไหม?** — ได้ ทดสอบสร้าง ISO กับ build 26300 แล้ว (UDF, บูตได้ทั้ง UEFI และ Legacy BIOS, install.wim ขนาดเกิน 4GB ได้)

**ต่างจาก Rufus ยังไง?** — Rufus ต้องเขียนลง USB ทีละ ISO และใช้ได้บน Windows เท่านั้น ส่วนนี้ใช้กับ Ventoy (USB อันเดียวใส่ได้หลาย ISO) และรันบน Linux ได้

**ยังขึ้นบังคับต่อเน็ต?** — ตรวจว่า Ventoy เวอร์ชัน ≥ 1.0.83 และบูตแบบโหมดปกติ (normal mode) ถ้า Microsoft ปิดช่องทางนี้ใน build ใหม่ กรุณาเปิด [Issue](https://github.com/nutthawutkongsopa/win11-bypass/issues)

**ปลอดภัยไหม?** — สคริปต์ไม่แก้ไฟล์ระบบ Windows ใน ISO แค่เพิ่ม `autounattend.xml` (ไฟล์ตั้งค่าการติดตั้งมาตรฐานของ Microsoft) อ่านได้ทุกบรรทัดใน repo นี้

**เครื่องที่ไม่ผ่านสเป็คจะได้อัปเดตไหม?** — Microsoft ไม่รับประกันการอัปเดตบนเครื่องที่ไม่รองรับอย่างเป็นทางการ ใช้ด้วยความเข้าใจความเสี่ยงนี้

---

<a id="english"></a>
## English

**win11-bypass** lets you install Windows 11 on unsupported PCs and finish setup offline with a local account:

- Bypasses TPM 2.0, Secure Boot, RAM, CPU and storage checks (`LabConfig`)
- Skips the forced internet connection in OOBE (`BypassNRO`)
- Hides Microsoft account, Wi-Fi, EULA and privacy pages — you still type your own local user name
- Never touches disk/partition settings

**Linux one-liner** (menu: patch ISO / configure Ventoy USB / remove):

```bash
curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash
```

**Windows / macOS:** configure Ventoy by hand — copy [`autounattend.xml`](autounattend.xml) to `ventoy/script/win11-autounattend.xml` on the USB and add the `ventoy.json` snippet [above](#วิธีใช้บน-windows--macos-ตั้งค่า-ventoy-ด้วยมือ-2-นาที). Requires Ventoy ≥ 1.0.83, boot the ISO in normal mode.

The patched ISO is UDF with both BIOS (`etfsboot.com`) and UEFI (`efisys.bin`) El Torito entries, so it also works with Rufus, VMs, or any USB writer.

## License

[MIT](LICENSE) — not affiliated with Microsoft or Ventoy.

<!-- keywords: ติดตั้ง windows 11 ไม่ต้องต่อเน็ต, windows 11 ข้าม tpm, ventoy windows 11 bypass, ลง windows 11 เครื่องสเป็คไม่ถึง, windows 11 local account, bypass tpm 2.0 secure boot, bypassnro, autounattend.xml, rufus alternative linux, windows 11 offline install -->
