<#
.SYNOPSIS
  Windows / PowerShell launcher for the Forsheur evidence-bundle verifier.

  Prefer verify_bundle.cmd: it is double-clickable and is not subject to the
  PowerShell execution policy, which blocks downloaded .ps1 files by default.
  This script is here for people who would rather stay in PowerShell.

.DESCRIPTION
  All verification logic lives in verify_bundle.py (cross-platform Python). This
  wrapper only makes it convenient on Windows: it finds a Python 3 interpreter,
  installs the optional decryption dependencies when you ask to decrypt, and runs
  verify_bundle.py with the exact same arguments. It does NOT reimplement any of
  the cryptography — a bug here can only fail to launch, never forge a pass.

.EXAMPLE
  .\verify_bundle.ps1 .
  .\verify_bundle.ps1 . --extract --id-priv
  .\verify_bundle.ps1 . --extract --dek

  The key is never passed on the command line: --id-priv / --dek prompt for it
  with hidden input (nothing is written to your PowerShell history).

.NOTES
  If Windows blocks the script ("running scripts is disabled on this system"),
  either use verify_bundle.cmd instead, or clear the internet mark and bypass
  the policy for this one process:
    Unblock-File .\verify_bundle.ps1
    powershell -ExecutionPolicy Bypass -File .\verify_bundle.ps1 .
  A machine-wide Group Policy overrides -ExecutionPolicy; verify_bundle.cmd
  works regardless.
#>

$ErrorActionPreference = 'Stop'

# --- 1. Locate a Python 3 interpreter -------------------------------------
# Prefer an x64 (AMD64) interpreter, even on an ARM64 machine where it runs
# under emulation: the cryptography package stopped publishing win_arm64 wheels
# after its 46.0.x branch, so an ARM64 Python can only ever install a frozen
# version -- or tries to build from source and walks the user into a Rust/MSVC
# toolchain error. Verification itself is stdlib-only and runs on any Python 3;
# the architecture only matters when decrypting.
function Find-Python {
    param([string] $WantMachine)   # 'AMD64', or empty to accept any

    $candidates = @(
        @{ Exe = 'py';      Pre = @('-3-64') },
        @{ Exe = 'py';      Pre = @('-3')    },
        @{ Exe = 'python';  Pre = @()        },
        @{ Exe = 'python3'; Pre = @()        }
    )
    foreach ($c in $candidates) {
        if (-not (Get-Command $c.Exe -ErrorAction SilentlyContinue)) { continue }
        try {
            # Prints the machine only under Python 3: "AMD64" * False is the
            # empty string, so Python 2 is rejected along with anything broken.
            $m = & $c.Exe @($c.Pre) '-c' `
                 'import platform,sys;print(platform.machine()*(sys.version_info[0]==3))' 2>$null
            $m = "$m".Trim()
            if (-not $m) { continue }
            if ($WantMachine -and $m -ne $WantMachine) { continue }
            $c.Machine = $m
            return $c
        } catch { }
    }
    return $null
}

$py = Find-Python -WantMachine 'AMD64'
if ($null -eq $py) { $py = Find-Python }
if ($null -eq $py) {
    Write-Host 'Python 3 was not found on this system.' -ForegroundColor Red
    Write-Host 'Install it, then re-run:'
    Write-Host '  - https://www.python.org/downloads/  (tick "Add python.exe to PATH")'
    Write-Host '  - or:  winget install Python.Python.3.12'
    exit 1
}
$pyExe = $py.Exe
$pyPre = $py.Pre
$pyMachine = $py.Machine

# --- 2. Locate verify_bundle.py (next to this script) ---------------------
$verifier = Join-Path $PSScriptRoot 'verify_bundle.py'
if (-not (Test-Path $verifier)) {
    Write-Host "verify_bundle.py was not found next to this script:" -ForegroundColor Red
    Write-Host "  $PSScriptRoot"
    exit 1
}

# --- 3. If decryption was requested, ensure the optional deps import ------
$needDecrypt = $false
foreach ($a in $args) {
    if ($a -eq '--dek' -or $a -eq '--id-priv' -or $a -eq '--id-priv-file') { $needDecrypt = $true }
}

if ($needDecrypt) {
    # module import name -> pip package name
    $wanted = @(
        @{ Mod = 'cryptography'; Pkg = 'cryptography' },  # AES-256-GCM
        @{ Mod = 'nacl';         Pkg = 'pynacl'       },  # crypto_box_seal_open (--id-priv)
        @{ Mod = 'mnemonic';     Pkg = 'mnemonic'     }   # BIP39 24-word --id-priv form
    )
    $missing = @()
    foreach ($w in $wanted) {
        & $pyExe @pyPre '-c' "import $($w.Mod)" 2>$null
        if ($LASTEXITCODE -ne 0) { $missing += $w.Pkg }
    }
    if ($missing.Count -gt 0) {
        if ($pyMachine -eq 'ARM64') {
            Write-Host 'Note: no x64 Python was found, so this is the ARM64 build. Decryption' -ForegroundColor Yellow
            Write-Host 'will install an older cryptography release — the last one published for' -ForegroundColor Yellow
            Write-Host 'ARM64. It decrypts correctly; installing the 64-bit (x64) Python from' -ForegroundColor Yellow
            Write-Host 'python.org would get the current one instead.' -ForegroundColor Yellow
        }
        Write-Host ("Decryption needs these Python packages: " + ($missing -join ', ')) -ForegroundColor Yellow
        $ans = Read-Host 'Install them now with pip? [Y/n]'
        if ($ans -eq '' -or $ans -match '^[Yy]') {
            # --only-binary forbids building from source. Without it pip falls back
            # to the sdist and cryptography, being written in Rust, fails on a
            # machine with no MSVC linker — an error no recipient can act on. With
            # it, pip picks the newest release that has a wheel for this Python.
            & $pyExe @pyPre '-m' 'pip' 'install' '--only-binary=:all:' @missing
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'Could not install the decryption packages.' -ForegroundColor Red
                if ($pyMachine -eq 'ARM64') {
                    Write-Host 'Your Python is the ARM64 build, and the cryptography package no longer'
                    Write-Host 'publishes ARM64 builds for Windows. Install the 64-bit (x64) Python from'
                    Write-Host 'python.org — it runs perfectly well on this machine:'
                } else {
                    Write-Host 'No prebuilt package matched your Python, which usually means a 32-bit or'
                    Write-Host 'otherwise unusual build. Install the 64-bit (x64) Python from python.org:'
                }
                Write-Host '    https://www.python.org/downloads/windows/'
                Write-Host ''
                Write-Host 'Verifying the evidence needs none of these packages — plain verification'
                Write-Host 'works with any Python 3. Only decryption requires them.'
                exit 1
            }
        } else {
            Write-Host 'Continuing without installing; decryption will error if actually used.'
        }
    }
}

# --- 4. Run the verifier, passing every argument straight through ---------
& $pyExe @pyPre $verifier @args
exit $LASTEXITCODE
