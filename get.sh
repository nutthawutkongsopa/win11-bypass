#!/usr/bin/env bash
# win11-bypass (Linux) - Windows 11 install without hardware checks / forced internet
#   curl -fsSL https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main/get.sh | bash
#   curl -fsSL .../get.sh | bash -s -- iso Win11.iso [-o out.iso]
#   curl -fsSL .../get.sh | bash -s -- ventoy [/media/$USER/Ventoy]
#   curl -fsSL .../get.sh | bash -s -- remove [/media/$USER/Ventoy]
set -euo pipefail

RAW_BASE="${WIN11_BYPASS_RAW:-https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main}"
TEMPLATE_REL="ventoy/script/win11-autounattend.xml"

c_info=$'\e[36m'; c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
info() { printf '%s[*]%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

# stdin is the script itself under `curl | bash`, so prompts read from the terminal
ask() {
    local reply=""
    { exec 3</dev/tty; } 2>/dev/null || die "No terminal for prompts - pass all arguments instead"
    read -r -p "$1" reply <&3 || true
    exec 3<&-
    printf '%s' "$reply"
}

CLEANUP=()
cleanup() { local p; for p in "${CLEANUP[@]}"; do rm -rf -- "$p"; done; }
trap cleanup EXIT

# ---------------------------------------------------------------- autounattend
UNATTEND=""
get_unattend() {
    [[ -n "$UNATTEND" ]] && return
    local here
    here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
    if [[ -n "$here" && -f "$here/autounattend.xml" ]]; then
        UNATTEND="$here/autounattend.xml"
        return
    fi
    UNATTEND="$(mktemp --suffix=.xml)"
    CLEANUP+=("$UNATTEND")
    info "Downloading autounattend.xml"
    curl -fsSL "$RAW_BASE/autounattend.xml" -o "$UNATTEND" || die "Cannot download $RAW_BASE/autounattend.xml"
    grep -q 'urn:schemas-microsoft-com:unattend' "$UNATTEND" || die "Downloaded autounattend.xml looks wrong"
}

# ---------------------------------------------------------------- dependencies
pkg_install_cmd() {
    if command -v apt-get >/dev/null; then echo "sudo apt-get install -y"
    elif command -v dnf >/dev/null; then echo "sudo dnf install -y"
    elif command -v pacman >/dev/null; then echo "sudo pacman -S --needed --noconfirm"
    elif command -v zypper >/dev/null; then echo "sudo zypper install -y"
    fi
}

pkg_name() { # tool -> package name for the detected package manager
    local pm="$1" tool="$2"
    case "$tool:$pm" in
        7z:*apt*)      echo p7zip-full ;;
        7z:*dnf*)      echo p7zip-plugins ;;
        7z:*pacman*)   echo 7zip ;;
        7z:*zypper*)   echo 7zip ;;
        mkiso:*pacman*) echo cdrtools ;;
        mkiso:*)       echo genisoimage ;;
        python3:*pacman*) echo python ;;
        python3:*)     echo python3 ;;
    esac
}

MKISO=""
find_mkiso() {
    local t
    for t in genisoimage mkisofs; do
        command -v "$t" >/dev/null || continue
        # capture first: `cmd | grep -q` + pipefail fails on SIGPIPE
        if grep -q -- '-udf' <<<"$("$t" -help 2>&1)"; then MKISO="$t"; return 0; fi
    done
    return 1
}

need() { # need 7z mkiso python3 ...
    local missing=() tool
    for tool in "$@"; do
        case "$tool" in
            mkiso) find_mkiso || missing+=(mkiso) ;;
            *)     command -v "$tool" >/dev/null || missing+=("$tool") ;;
        esac
    done
    ((${#missing[@]} == 0)) && return
    local pm pkgs=()
    pm="$(pkg_install_cmd)"
    [[ -n "$pm" ]] || die "Missing: ${missing[*]} - install them with your package manager"
    for tool in "${missing[@]}"; do pkgs+=("$(pkg_name "$pm" "$tool")"); done
    warn "Missing tools: ${missing[*]}"
    [[ "$(ask "Run '$pm ${pkgs[*]}' now? [y/N] ")" =~ ^[Yy] ]] || die "Aborted"
    $pm "${pkgs[@]}"
    for tool in "${missing[@]}"; do
        case "$tool" in
            mkiso) find_mkiso || die "genisoimage/mkisofs with UDF support still not found" ;;
            *)     command -v "$tool" >/dev/null || die "$tool still not found" ;;
        esac
    done
}

# ---------------------------------------------------------------- mod ISO
iso_label() { # primary volume descriptor, volume id at byte 32808
    dd if="$1" bs=1 skip=32808 count=32 status=none | tr -d '\0' | sed 's/ *$//'
}

mod_iso() {
    local in="${1:-}" out="${2:-}"
    [[ -n "$in" ]] || in="$(ask "Path to Windows 11 ISO: ")"
    in="${in/#\~/$HOME}"
    [[ -f "$in" ]] || die "Not found: $in"
    [[ -n "$out" ]] || out="${in%.[iI][sS][oO]}-bypass.iso"
    [[ "$(realpath -m "$in")" != "$(realpath -m "$out")" ]] || die "Output must differ from input"
    if [[ -e "$out" ]]; then
        [[ "$(ask "$out exists. Overwrite? [y/N] ")" =~ ^[Yy] ]] || die "Aborted"
    fi

    need 7z mkiso
    get_unattend

    local outdir size free label work
    outdir="$(dirname -- "$(realpath -m "$out")")"
    size=$(stat -c %s "$in")
    free=$(( $(df -Pk "$outdir" | awk 'NR==2{print $4}') * 1024 ))
    (( free > size * 2 + 512*1024*1024 )) \
        || die "Need ~$(( size * 2 / 1024**3 + 1 )) GB free in $outdir (have $(( free / 1024**3 )) GB)"

    label="$(iso_label "$in")"
    [[ -n "$label" ]] || label="WIN11_BYPASS"
    # work dir next to the output: /tmp is often a small tmpfs
    work="$(mktemp -d -p "$outdir" .win11-bypass.XXXXXX)"
    CLEANUP+=("$work")

    info "Extracting $(basename -- "$in") (label: $label)"
    7z x -y -bso0 -bsp1 -o"$work" "$in"
    local bios efi
    bios="$(cd "$work" && find . -ipath './boot/etfsboot.com' | head -1)"
    efi="$(cd "$work" && find . -ipath './efi/microsoft/boot/efisys.bin' | head -1)"
    [[ -n "$efi" ]] || die "efi/microsoft/boot/efisys.bin not found - is this a Windows ISO?"
    [[ -d "$work/[BOOT]" ]] && rm -rf -- "$work/[BOOT]"

    cp -- "$UNATTEND" "$work/autounattend.xml"
    ok "Added autounattend.xml"

    local args=(-iso-level 3 -udf -J -joliet-long -D -N -relaxed-filenames -V "$label")
    [[ "$MKISO" == genisoimage ]] && args+=(-allow-limited-size)
    if [[ -n "$bios" ]]; then
        args+=(-b "${bios#./}" -no-emul-boot -boot-load-seg 0x07C0 -boot-load-size 8 -c boot.catalog -eltorito-alt-boot)
    else
        warn "boot/etfsboot.com not found - output will be UEFI-only"
        args+=(-c boot.catalog)
    fi
    if grep -q -- '-efi-boot' <<<"$("$MKISO" -help 2>&1)"; then
        args+=(-e "${efi#./}" -no-emul-boot)
    else
        args+=(-eltorito-platform efi -b "${efi#./}" -no-emul-boot)
    fi

    info "Building $(basename -- "$out") with $MKISO"
    "$MKISO" "${args[@]}" -quiet -o "$out" "$work"
    ok "Done: $out"
    echo "   Copy it to your Ventoy USB (or write it with any tool) and boot normally."
}

# ---------------------------------------------------------------- Ventoy
find_ventoy() {
    local given="${1:-}"
    if [[ -n "$given" ]]; then
        [[ -d "$given" ]] || die "Not a directory: $given"
        printf '%s' "$given"; return
    fi
    local lines=() line dev mnt
    mapfile -t lines < <(lsblk -rno PATH,LABEL,MOUNTPOINT | awk '$2=="Ventoy"')
    ((${#lines[@]})) || die "No partition labelled 'Ventoy' found. Plug the USB in, or pass its mount point."
    if ((${#lines[@]} > 1)); then
        local i
        for i in "${!lines[@]}"; do echo "  [$((i+1))] ${lines[$i]}" >/dev/tty; done
        i="$(ask "Pick Ventoy USB [1-${#lines[@]}]: ")"
        [[ "$i" =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#lines[@]} )) || die "Invalid choice"
        line="${lines[$((i-1))]}"
    else
        line="${lines[0]}"
    fi
    dev="$(awk '{print $1}' <<<"$line")"
    mnt="$(awk '{print $3}' <<<"$line")"
    if [[ -z "$mnt" ]]; then
        command -v udisksctl >/dev/null || die "$dev is not mounted - mount it and pass the mount point"
        info "Mounting $dev"
        udisksctl mount -b "$dev" >/dev/null
        mnt="$(lsblk -rno MOUNTPOINT "$dev" | head -1)"
    fi
    printf '%b' "$mnt"   # lsblk escapes spaces as \x20
}

ventoy_json() { # action root [template]
    python3 - "$@" <<'PY'
import json, os, re, shutil, sys, time

action, root = sys.argv[1], sys.argv[2]
tpl_rel = "ventoy/script/win11-autounattend.xml"
tpl_ref = "/" + tpl_rel
ours = {"VTOY_WIN11_BYPASS_CHECK": "1", "VTOY_WIN11_BYPASS_NRO": "1"}
path = os.path.join(root, "ventoy", "ventoy.json")

cfg = {}
if os.path.exists(path):
    with open(path, encoding="utf-8-sig") as f:
        text = f.read()
    cfg = json.loads(text) if text.strip() else {}
    shutil.copy2(path, path + ".bak-" + time.strftime("%Y%m%d-%H%M%S"))

control = [c for c in cfg.get("control", []) if not (set(c) & set(ours))]
auto = [a for a in cfg.get("auto_install", []) if tpl_ref not in a.get("template", [])]

if action == "apply":
    control += [{k: v} for k, v in ours.items()]
    isos = []
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x.lower() != "ventoy" and not x.startswith(".")]
        for name in files:
            if name.lower().endswith(".iso") and re.search(r"win.*11", name, re.I):
                isos.append("/" + os.path.relpath(os.path.join(d, name), root).replace(os.sep, "/"))
    for iso in sorted(isos):
        auto.append({"image": iso, "template": [tpl_ref], "autosel": 1})
    print("ISO with auto-install: " + (", ".join(sorted(isos)) or "none (copy a Win11 ISO to the USB and run again)"))
    dst = os.path.join(root, tpl_rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(sys.argv[3], dst)
else:
    try:
        os.remove(os.path.join(root, tpl_rel))
        os.rmdir(os.path.dirname(os.path.join(root, tpl_rel)))
    except OSError:
        pass

for key, val in (("control", control), ("auto_install", auto)):
    if val:
        cfg[key] = val
    else:
        cfg.pop(key, None)

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8", newline="\n") as f:  # Ventoy needs UTF-8 without BOM
    json.dump(cfg, f, indent=4, ensure_ascii=False)
    f.write("\n")
PY
}

setup_ventoy() {
    need python3
    get_unattend
    local root; root="$(find_ventoy "${1:-}")"
    info "Ventoy USB: $root"
    ventoy_json apply "$root" "$UNATTEND"
    sync
    ok "Ventoy configured: VTOY_WIN11_BYPASS_CHECK=1, VTOY_WIN11_BYPASS_NRO=1, $TEMPLATE_REL"
    echo "   Needs Ventoy >= 1.0.83. Boot the ISO in normal mode (not wimboot)."
}

remove_ventoy() {
    need python3
    local root; root="$(find_ventoy "${1:-}")"
    ventoy_json remove "$root"
    sync
    ok "Removed win11-bypass settings from $root (backup kept as ventoy.json.bak-*)"
}

# ---------------------------------------------------------------- main
menu() {
    while true; do
        cat >/dev/tty <<EOF

  win11-bypass - install Windows 11 without TPM/CPU checks or forced internet
  -------------------------------------------------------------------------
  [1] Mod ISO            (add autounattend.xml, rebuild ISO)
  [2] Setup Ventoy USB   (no ISO change, uses Ventoy plugins)
  [3] Remove Ventoy config
  [0] Exit

EOF
        case "$(ask "Choose: ")" in
            1) mod_iso ;;
            2) setup_ventoy ;;
            3) remove_ventoy ;;
            0|q|"") return ;;
            *) warn "Invalid choice" ;;
        esac
    done
}

main() {
    local cmd="${1:-}"; shift || true
    case "$cmd" in
        "")     menu ;;
        iso)
            local in="" out=""
            while (($#)); do
                case "$1" in
                    -o|--output) out="${2:?}"; shift 2 ;;
                    *) in="$1"; shift ;;
                esac
            done
            mod_iso "$in" "$out" ;;
        ventoy) setup_ventoy "${1:-}" ;;
        remove) remove_ventoy "${1:-}" ;;
        -h|--help|help) sed -n '2,7p' "${BASH_SOURCE[0]}" 2>/dev/null || echo "usage: get.sh [iso FILE [-o OUT] | ventoy [DIR] | remove [DIR]]" ;;
        *) die "Unknown command: $cmd (use: iso | ventoy | remove)" ;;
    esac
}

main "$@"
