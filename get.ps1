# win11-bypass (PowerShell/Windows)
# Windows 11 install without TPM/CPU checks / forced internet
#
# Usage:
#   .\get.ps1
#   .\get.ps1 iso Win11.iso
#   .\get.ps1 iso Win11.iso -Output out.iso
#   .\get.ps1 ventoy E:\
#   .\get.ps1 remove E:\
#
# Dependencies:
#   - 7-Zip (7z.exe) for ISO extraction
#   - oscdimg.exe (Windows ADK) for rebuilding a bootable ISO
#   - No Python is required for Ventoy configuration.

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('', 'iso', 'ventoy', 'remove', 'help')]
    [string]$Command = '',

    [Parameter(Position=1)]
    [string]$InputPath = '',

    [Alias('o')]
    [string]$Output = '',

    [Parameter(Position=2)]
    [string]$VentoyPath = ''
)

$ErrorActionPreference = 'Stop'

$RawBase = if ($env:WIN11_BYPASS_RAW) {
    $env:WIN11_BYPASS_RAW.TrimEnd('/')
} else {
    'https://raw.githubusercontent.com/nutthawutkongsopa/win11-bypass/main'
}

$TemplateRel = 'ventoy/script/win11-autounattend.xml'
$TempItems = [System.Collections.Generic.List[string]]::new()

function Info($Message) {
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Ok($Message) {
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Warn($Message) {
    Write-Warning "[!] $Message"
}

function Die($Message) {
    Write-Error "[x] $Message"
    exit 1
}

function Confirm-Action($Message) {
    $answer = Read-Host "$Message [y/N]"
    return $answer -match '^[Yy]$'
}

function Add-TempItem($Path) {
    [void]$TempItems.Add($Path)
}

function Cleanup {
    foreach ($path in $TempItems) {
        try {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function Get-ToolPath([string[]]$Names) {
    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }
    return $null
}

function Get-7Zip {
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )

    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

function Get-Oscdimg {
    $cmd = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits",
        "$env:ProgramFiles\Windows Kits"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }

        $found = Get-ChildItem -Path $root -Filter oscdimg.exe -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($found) {
            return $found.FullName
        }
    }

    return $null
}

function Get-Unattend {
    if ($script:UNATTEND -and (Test-Path -LiteralPath $script:UNATTEND)) {
        return $script:UNATTEND
    }

    # Prefer autounattend.xml next to this PowerShell script.
    # $PSScriptRoot is empty when run from a downloaded scriptblock.
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot 'autounattend.xml'
        if (Test-Path -LiteralPath $local) {
            $script:UNATTEND = $local
            return $script:UNATTEND
        }
    }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ("win11-bypass-{0}.xml" -f ([guid]::NewGuid()))
    Add-TempItem $temp

    Info "Downloading autounattend.xml"
    try {
        Invoke-WebRequest -Uri "$RawBase/autounattend.xml" -OutFile $temp -UseBasicParsing
    } catch {
        Die "Cannot download $RawBase/autounattend.xml : $($_.Exception.Message)"
    }

    $content = Get-Content -LiteralPath $temp -Raw
    if ($content -notmatch 'urn:schemas-microsoft-com:unattend') {
        Die "Downloaded autounattend.xml looks wrong"
    }

    $script:UNATTEND = $temp
    return $script:UNATTEND
}

function Get-IsoLabel([string]$Path) {
    # Primary Volume Descriptor starts at sector 16 (2048 bytes).
    # Volume identifier is offset 40 within the PVD and 32 bytes long.
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] 32
        $stream.Seek((16 * 2048) + 40, [IO.SeekOrigin]::Begin) | Out-Null
        [void]$stream.Read($buffer, 0, 32)

        $label = [Text.Encoding]::ASCII.GetString($buffer).Trim([char]0, ' ')
        return $label
    }
    finally {
        $stream.Dispose()
    }
}

function Test-FreeSpace([string]$Directory, [Int64]$IsoSize) {
    $drive = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Directory).Path)
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($drive.TrimEnd('\'))'"
    if (-not $disk) {
        Die "Cannot determine free disk space for $drive"
    }

    $required = ($IsoSize * 2) + (512MB)
    if ([Int64]$disk.FreeSpace -le $required) {
        $requiredGB = [math]::Ceiling($required / 1GB)
        $freeGB = [math]::Floor([Int64]$disk.FreeSpace / 1GB)
        Die "Need about $requiredGB GB free in $drive (have $freeGB GB)"
    }
}

function Invoke-Iso {
    param(
        [string]$In,
        [string]$Out
    )

    if ([string]::IsNullOrWhiteSpace($In)) {
        $In = Read-Host 'Path to Windows 11 ISO'
    }

    $In = [Environment]::ExpandEnvironmentVariables($In)
    if ($In.StartsWith('~\')) {
        $In = Join-Path $HOME $In.Substring(2)
    }

    if (-not (Test-Path -LiteralPath $In -PathType Leaf)) {
        Die "Not found: $In"
    }

    $In = (Resolve-Path -LiteralPath $In).Path

    if ([string]::IsNullOrWhiteSpace($Out)) {
        $base = [IO.Path]::GetFileNameWithoutExtension($In)
        $Out = Join-Path ([IO.Path]::GetDirectoryName($In)) "$base-bypass.iso"
    } else {
        $Out = [IO.Path]::GetFullPath($Out)
    }

    if ([IO.Path]::GetFullPath($In) -eq [IO.Path]::GetFullPath($Out)) {
        Die "Output must differ from input"
    }

    if (Test-Path -LiteralPath $Out) {
        if (-not (Confirm-Action "$Out exists. Overwrite?")) {
            Die 'Aborted'
        }
        Remove-Item -LiteralPath $Out -Force
    }

    $sevenZip = Get-7Zip
    if (-not $sevenZip) {
        Die '7z.exe not found. Install 7-Zip and make sure 7z.exe is available.'
    }

    $oscdimg = Get-Oscdimg
    if (-not $oscdimg) {
        Die 'oscdimg.exe not found. Install Windows ADK (Deployment Tools).'
    }

    $unattend = Get-Unattend
    $outDir = [IO.Path]::GetDirectoryName($Out)

    Test-FreeSpace $outDir ([IO.FileInfo]$In).Length

    $label = Get-IsoLabel $In
    if ([string]::IsNullOrWhiteSpace($label)) {
        $label = 'WIN11_BYPASS'
    }

    $work = Join-Path $outDir ('.win11-bypass-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Add-TempItem $work

    Info "Extracting $(Split-Path $In -Leaf) (label: $label)"
    & $sevenZip x -y '-bso0' '-bsp1' "-o$work" $In
    if ($LASTEXITCODE -ne 0) {
        Die '7-Zip extraction failed'
    }

    $bios = Join-Path $work 'boot\etfsboot.com'
    $efi  = Join-Path $work 'efi\microsoft\boot\efisys.bin'

    if (-not (Test-Path -LiteralPath $efi)) {
        Die 'efi\microsoft\boot\efisys.bin not found - is this a Windows ISO?'
    }

    $bootDir = Join-Path $work '[BOOT]'
    if (Test-Path -LiteralPath $bootDir) {
        Remove-Item -LiteralPath $bootDir -Recurse -Force
    }

    Copy-Item -LiteralPath $unattend -Destination (Join-Path $work 'autounattend.xml') -Force
    Ok 'Added autounattend.xml'

    # oscdimg requires a BIOS boot image (-b) and EFI boot image (-u2 -udfver102).
    # -bootdata creates a dual BIOS/UEFI bootable ISO.
    $biosRelative = 'boot\etfsboot.com'
    $efiRelative  = 'efi\microsoft\boot\efisys.bin'

    $args = @(
        '-m',
        '-o',
        '-u2',
        '-udfver102',
        "-l$label"
    )

    if (Test-Path -LiteralPath $bios) {
        $args += "-bootdata:2#p0,e,b`"$biosRelative`"#pEF,e,b`"$efiRelative`""
    } else {
        Warn 'boot\etfsboot.com not found - output will be UEFI-only'
        $args += "-bootdata:1#pEF,e,b`"$efiRelative`""
    }

    $args += @(
        "`"$work`"",
        "`"$Out`""
    )

    Info "Building $(Split-Path $Out -Leaf) with oscdimg.exe"
    & $oscdimg @args

    if ($LASTEXITCODE -ne 0) {
        Die "oscdimg failed with exit code $LASTEXITCODE"
    }

    Ok "Done: $Out"
    Write-Host '   Copy it to your Ventoy USB (or write it with any tool) and boot normally.'
}

function Find-Ventoy {
    param([string]$Given)

    if (-not [string]::IsNullOrWhiteSpace($Given)) {
        if (-not (Test-Path -LiteralPath $Given -PathType Container)) {
            Die "Not a directory: $Given"
        }
        return (Resolve-Path -LiteralPath $Given).Path
    }

    # Windows cannot reliably detect a mount point by filesystem LABEL alone
    # in exactly the same way as lsblk. Search mounted volumes labelled Ventoy.
    $volumes = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.FileSystemLabel -eq 'Ventoy' -and $_.DriveLetter } |
        ForEach-Object {
            "$($_.DriveLetter):\"
        }

    if (-not $volumes) {
        Die 'No mounted partition labelled Ventoy found. Plug in the USB, mount it, or pass its drive path.'
    }

    if (@($volumes).Count -gt 1) {
        for ($i = 0; $i -lt @($volumes).Count; $i++) {
            Write-Host "  [$($i + 1)] $($volumes[$i])"
        }

        $choice = Read-Host "Pick Ventoy USB [1-$(@($volumes).Count)]"
        if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt @($volumes).Count) {
            Die 'Invalid choice'
        }

        return $volumes[[int]$choice - 1]
    }

    return $volumes[0]
}

function Read-VentoyJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{}
    }

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [ordered]@{}
    }

    try {
        return ($text | ConvertFrom-Json -AsHashtable)
    } catch {
        Die "Invalid JSON: $Path : $($_.Exception.Message)"
    }
}

function Write-VentoyJson([string]$Path, $Config) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null

    # PowerShell's ConvertTo-Json produces UTF-8 text without a BOM when
    # written through .NET directly.
    $json = $Config | ConvertTo-Json -Depth 50
    [IO.File]::WriteAllText(
        $Path,
        $json + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Update-VentoyJson {
    param(
        [ValidateSet('apply', 'remove')]
        [string]$Action,

        [string]$Root,

        [string]$Template
    )

    $tplRef = '/' + ($TemplateRel -replace '\\', '/')
    $ours = @{
        VTOY_WIN11_BYPASS_CHECK = '1'
        VTOY_WIN11_BYPASS_NRO   = '1'
    }

    $path = Join-Path $Root 'ventoy\ventoy.json'
    $cfg = Read-VentoyJson $path

    # Backup existing config before modifying it.
    if (Test-Path -LiteralPath $path) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $path -Destination "$path.bak-$stamp" -Force
    }

    # Normalize control and auto_install arrays.
    $control = @()
    if ($cfg.ContainsKey('control') -and $null -ne $cfg.control) {
        foreach ($c in @($cfg.control)) {
            $remove = $false
            if ($c -is [hashtable]) {
                foreach ($key in $ours.Keys) {
                    if ($c.ContainsKey($key)) {
                        $remove = $true
                    }
                }
            }
            if (-not $remove) {
                $control += $c
            }
        }
    }

    $auto = @()
    if ($cfg.ContainsKey('auto_install') -and $null -ne $cfg.auto_install) {
        foreach ($a in @($cfg.auto_install)) {
            $templates = @()
            if ($a -is [hashtable] -and $a.ContainsKey('template')) {
                $templates = @($a.template)
            }

            if ($templates -notcontains $tplRef) {
                $auto += $a
            }
        }
    }

    if ($Action -eq 'apply') {
        foreach ($key in $ours.Keys) {
            $control += @{ $key = $ours[$key] }
        }

        $isos = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.iso' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '[\\/]+ventoy[\\/]' -and
                $_.Name -match 'win.*11'
            } |
            ForEach-Object {
                '/' + $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
            } |
            Sort-Object

        if ($isos.Count -eq 0) {
            Write-Host 'ISO with auto-install: none (copy a Win11 ISO to the USB and run again)'
        } else {
            Write-Host "ISO with auto-install: $($isos -join ', ')"
        }

        $dst = Join-Path $Root ($TemplateRel -replace '/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        Copy-Item -LiteralPath $Template -Destination $dst -Force
    }
    else {
        $dst = Join-Path $Root ($TemplateRel -replace '/', '\')
        if (Test-Path -LiteralPath $dst) {
            Remove-Item -LiteralPath $dst -Force
        }

        $scriptDir = Split-Path -Parent $dst
        if (Test-Path -LiteralPath $scriptDir) {
            try { Remove-Item -LiteralPath $scriptDir -Force -ErrorAction Stop } catch {}
        }
    }

    if ($control.Count -gt 0) {
        $cfg['control'] = @($control)
    } else {
        $cfg.Remove('control')
    }

    if ($auto.Count -gt 0) {
        $cfg['auto_install'] = @($auto)
    } else {
        $cfg.Remove('auto_install')
    }

    Write-VentoyJson $path $cfg
}

function Setup-Ventoy {
    param([string]$RootPath)

    $unattend = Get-Unattend
    $root = Find-Ventoy $RootPath

    Info "Ventoy USB: $root"
    Update-VentoyJson -Action apply -Root $root -Template $unattend

    Ok 'Ventoy configured: VTOY_WIN11_BYPASS_CHECK=1, VTOY_WIN11_BYPASS_NRO=1, ventoy/script/win11-autounattend.xml'
    Write-Host '   Needs Ventoy >= 1.0.83. Boot the ISO in normal mode (not wimboot).'
}

function Remove-Ventoy {
    param([string]$RootPath)

    $root = Find-Ventoy $RootPath
    Update-VentoyJson -Action remove -Root $root -Template ''

    Ok "Removed win11-bypass settings from $root (backup kept as ventoy.json.bak-*)"
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  win11-bypass - install Windows 11 without TPM/CPU checks or forced internet'
        Write-Host '  -------------------------------------------------------------------------'
        Write-Host '  [1] Mod ISO            (add autounattend.xml, rebuild ISO)'
        Write-Host '  [2] Setup Ventoy USB   (no ISO change, uses Ventoy plugins)'
        Write-Host '  [3] Remove Ventoy config'
        Write-Host '  [0] Exit'
        Write-Host ''

        $choice = Read-Host 'Choose'

        switch ($choice) {
            '1' { Invoke-Iso -In '' -Out '' }
            '2' { Setup-Ventoy -RootPath '' }
            '3' { Remove-Ventoy -RootPath '' }
            '0' { return }
            'q' { return }
            ''  { return }
            default { Warn 'Invalid choice' }
        }
    }
}

try {
    switch ($Command) {
        '' {
            Show-Menu
        }

        'iso' {
            Invoke-Iso -In $InputPath -Out $Output
        }

        'ventoy' {
            $root = if ($InputPath) { $InputPath } else { $VentoyPath }
            Setup-Ventoy -RootPath $root
        }

        'remove' {
            $root = if ($InputPath) { $InputPath } else { $VentoyPath }
            Remove-Ventoy -RootPath $root
        }

        'help' {
            Write-Host @'
Usage:
  .\get.ps1
  .\get.ps1 iso FILE [-o OUT]
  .\get.ps1 ventoy [DRIVE]
  .\get.ps1 remove [DRIVE]

Examples:
  .\get.ps1 iso .\Win11.iso
  .\get.ps1 iso .\Win11.iso -o .\Win11-bypass.iso
  .\get.ps1 ventoy E:\
  .\get.ps1 remove E:\
'@
        }
    }
}
finally {
    Cleanup
}
