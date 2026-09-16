@echo off
rem ===========================================================================
rem  Forsheur evidence bundle -- Windows launcher (double-clickable)
rem
rem  All verification logic lives in verify_bundle.py (cross-platform Python).
rem  This wrapper only makes it convenient on Windows: it finds a Python 3
rem  interpreter, offers a short menu when double-clicked, installs the optional
rem  decryption dependencies when you ask to decrypt, and runs verify_bundle.py.
rem  It contains NO cryptography of its own -- a bug here can only fail to
rem  launch, never forge a pass.
rem
rem  Why a .cmd and not just the .ps1: PowerShell refuses to run downloaded
rem  scripts under the default execution policy. Batch files are not subject to
rem  it, so this works on a stock Windows with nothing to configure.
rem
rem  Usage:
rem    double-click                      -> menu
rem    verify_bundle.cmd .               -> same as: python verify_bundle.py .
rem    verify_bundle.cmd . --extract     -> any verify_bundle.py argument works
rem ===========================================================================

setlocal enabledelayedexpansion

set "HERE=%~dp0"
set "VERIFIER=%HERE%verify_bundle.py"

rem --- No arguments means the interactive menu, i.e. we own this window (a
rem double-click, typically). Hold it open at the end so the result does not
rem flash by and vanish. With arguments the caller already has a console.
set "HOLD=0"
if "%~1"=="" set "HOLD=1"

rem --- 1. Locate a Python 3 interpreter -------------------------------------
rem Prefer an x64 (AMD64) interpreter, even on an ARM64 machine where it runs
rem under emulation: the cryptography package stopped publishing win_arm64
rem wheels after its 46.0.x branch, so an ARM64 Python can only ever install a
rem frozen version -- or, worse, tries to build from source and walks the user
rem into a Rust/MSVC toolchain error. Verification itself is stdlib-only and
rem runs fine on any Python 3; the architecture only matters when decrypting.
set "PY="
set "PYARGS="
set "PYMACH="
set "PROBEOUT=%TEMP%\forsheur-pyprobe-%RANDOM%.txt"

call :scan AMD64
if not defined PY call :scan ANY

if not defined PY (
    echo.
    echo   Python 3 was not found on this system.
    echo.
    echo   Install it, then run this file again:
    echo     - https://www.python.org/downloads/   ^(tick "Add python.exe to PATH"^)
    echo     - or, in a terminal:  winget install Python.Python.3.12
    echo.
    call :hold
    exit /b 1
)

if not exist "%VERIFIER%" (
    echo.
    echo   verify_bundle.py was not found next to this file:
    echo     %HERE%
    echo.
    echo   Unpack the whole evidence ZIP, keeping all files together.
    echo.
    call :hold
    exit /b 1
)

rem --- 2. Arguments given? Pass them straight through, no menu --------------
rem Run from the caller's directory so relative bundle paths still resolve.
if not "%~1"=="" (
    call :ensure_decrypt_deps %*
    if errorlevel 1 exit /b 1
    "%PY%" %PYARGS% "%VERIFIER%" %*
    set "RC=!errorlevel!"
    call :hold
    exit /b !RC!
)

rem --- 3. No arguments: interactive menu on this bundle ---------------------
rem Is this session end-to-end encrypted? Read it from the manifest so we only
rem offer the option that can actually produce something. A pretty-printed
rem manifest puts "encryption" on its own line; "encryption_keys" does not match
rem the literal below because of the trailing quote.
set "ENCRYPTED=0"
if exist "%HERE%manifest.json" (
    findstr /i /c:"\"encryption\"" "%HERE%manifest.json" | findstr /i /v /c:"none" >nul 2>&1 && set "ENCRYPTED=1"
) else (
    echo.
    echo   manifest.json was not found next to this file -- is the ZIP fully unpacked?
    echo.
    call :hold
    exit /b 1
)

echo.
echo   Forsheur evidence bundle
echo   ========================
echo.
echo   Everything below runs entirely offline. Nothing contacts any Forsheur
echo   server: the proof holds even if Forsheur disappears, or is the party
echo   being challenged.
echo.
if "%ENCRYPTED%"=="1" (
    echo   This session is end-to-end encrypted. Its provenance can be verified
    echo   in full without revealing the content.
    echo.
    echo     [1]  Verify the evidence                            ^(default^)
    echo     [2]  Verify, then decrypt and extract the media     ^(needs your key^)
) else (
    echo     [1]  Verify the evidence                            ^(default^)
    echo     [2]  Verify, then extract the playable media files
)
echo     [Q]  Quit
echo.
set "CHOICE="
set /p "CHOICE=  Your choice [1]: "
if not defined CHOICE set "CHOICE=1"

if /i "%CHOICE%"=="Q" exit /b 0
if "%CHOICE%"=="1" (
    "%PY%" %PYARGS% "%VERIFIER%" "%HERE%."
    set "RC=!errorlevel!"
    call :hold
    exit /b !RC!
)
if not "%CHOICE%"=="2" (
    echo.
    echo   Unrecognised choice "%CHOICE%".
    call :hold
    exit /b 1
)

rem --- 3b. Option 2 ---------------------------------------------------------
if "%ENCRYPTED%"=="0" (
    "%PY%" %PYARGS% "%VERIFIER%" "%HERE%." --extract
    set "RC=!errorlevel!"
    call :hold
    exit /b !RC!
)

rem Encrypted: which key does the user hold?
echo.
echo   Which key do you have?
echo.
echo     [a]  My identity private key -- 64 hex characters or a 24-word
echo          recovery phrase. Use this if the session was shared with you. ^(default^)
echo     [b]  The session key itself (DEK) -- 64 hex characters.
echo.
set "KIND="
set /p "KIND=  Your choice [a]: "
if not defined KIND set "KIND=a"

if /i "%KIND%"=="a" (
    set "KEYFLAG=--id-priv"
) else if /i "%KIND%"=="b" (
    set "KEYFLAG=--dek"
) else (
    echo.
    echo   Unrecognised choice "%KIND%".
    call :hold
    exit /b 1
)

echo.
echo   You will be prompted for the key with hidden input -- it never appears
echo   on the command line, on screen, or in your command history.
echo.
call :ensure_decrypt_deps !KEYFLAG!
if errorlevel 1 exit /b 1
"%PY%" %PYARGS% "%VERIFIER%" "%HERE%." --extract !KEYFLAG!
set "RC=!errorlevel!"
call :hold
exit /b !RC!


rem ===========================================================================
rem  Subroutines
rem ===========================================================================

rem --- Look for an interpreter, in order of preference -----------------------
rem %1 = required machine (AMD64), or ANY to accept whatever is installed.
:scan
call :consider "py" "-3-64" %1
call :consider "py" "-3"    %1
call :on_path python  %1
call :on_path python3 %1
exit /b 0

rem --- Candidates named on PATH, skipping the Microsoft Store alias ----------
rem That stub is a reparse point under WindowsApps which opens the Store
rem instead of running anything; picking it would strand the user.
:on_path
for /f "delims=" %%I in ('where %1 2^>nul') do (
    echo %%I | find /i "WindowsApps" >nul 2>&1 || call :consider "%%I" "" %2
)
exit /b 0

rem --- Accept one candidate if it is Python 3 and matches the wanted arch ----
rem %1 = command, %2 = prefix arguments, %3 = required machine or ANY.
rem The probe prints the machine only under Python 3 ("AMD64" * False is the
rem empty string), so Python 2 and anything broken leave the file empty and are
rem rejected.
rem
rem The probe runs as a plain command redirected to a file, NOT inside for /f:
rem for /f hands its command to cmd /c, and cmd /c strips the first and last
rem quote of any command line that starts with a quote and holds more than two.
rem "%~1" -c "code" would come back as %~1" -c "code -- a mangled interpreter
rem name that never runs. Redirecting keeps normal quoting rules.
:consider
if defined PY exit /b 0
set "_pre=%~2"
set "_mach="
"%~1" %_pre% -c "import platform,sys;print(platform.machine()*(sys.version_info[0]==3))" > "%PROBEOUT%" 2>nul
if exist "%PROBEOUT%" set /p _mach=<"%PROBEOUT%"
del "%PROBEOUT%" >nul 2>&1
if not defined _mach exit /b 0
if /i not "%~3"=="ANY" if /i not "%_mach%"=="%~3" exit /b 0
set "PY=%~1"
set "PYARGS=%_pre%"
set "PYMACH=%_mach%"
exit /b 0

rem --- Install the optional decryption dependencies, with consent ------------
rem Only needed when a key is actually supplied; plain verification is stdlib.
:ensure_decrypt_deps
set "_want=0"
:eddloop
if "%~1"=="" goto :eddcheck
if /i "%~1"=="--dek" set "_want=1"
if /i "%~1"=="--id-priv" set "_want=1"
if /i "%~1"=="--id-priv-file" set "_want=1"
shift
goto :eddloop

:eddcheck
if "%_want%"=="0" exit /b 0
set "MISSING="
call :need cryptography cryptography
call :need nacl pynacl
call :need mnemonic mnemonic
if not defined MISSING exit /b 0
echo.
if /i "%PYMACH%"=="ARM64" (
    echo   Note: no x64 Python was found, so this is the ARM64 build. Decryption
    echo   will install an older cryptography release -- the last one published
    echo   for ARM64. It decrypts correctly; installing the 64-bit ^(x64^) Python
    echo   from python.org would get the current one instead.
    echo.
)
echo   Decryption needs these Python packages:%MISSING%
set "ANS="
set /p "ANS=  Install them now with pip? [Y/n]: "
if not defined ANS set "ANS=Y"
if /i not "%ANS%"=="Y" (
    echo   Continuing without installing -- decryption will fail if actually used.
    exit /b 0
)
rem --only-binary forbids building from source. Without it pip falls back to
rem the sdist and cryptography, being written in Rust, fails on a machine with
rem no MSVC linker -- an error no recipient can act on. With it, pip simply
rem picks the newest release that has a wheel for this Python.
"%PY%" %PYARGS% -m pip install --only-binary=:all:%MISSING%
if errorlevel 1 (
    echo.
    echo   Could not install the decryption packages.
    echo.
    if /i "%PYMACH%"=="ARM64" (
        echo   Your Python is the ARM64 build, and the cryptography package no
        echo   longer publishes ARM64 builds for Windows. Install the 64-bit
        echo   ^(x64^) Python from python.org -- it runs perfectly well on this
        echo   machine and has the packages available:
    ) else (
        echo   No prebuilt package matched your Python, which usually means a
        echo   32-bit or otherwise unusual build. Install the 64-bit ^(x64^)
        echo   Python from python.org and run this again:
    )
    echo       https://www.python.org/downloads/windows/
    echo.
    echo   Verifying the evidence needs none of these packages -- option 1 works
    echo   with any Python 3. Only decryption requires them.
    call :hold
    exit /b 1
)
exit /b 0

rem --- %1 = python module name, %2 = pip package name -----------------------
:need
"%PY%" %PYARGS% -c "import %1" >nul 2>&1
if not errorlevel 1 exit /b 0
set "MISSING=%MISSING% %2"
exit /b 0

rem --- Keep the console open when Explorer launched us ----------------------
:hold
if "%HOLD%"=="1" (
    echo.
    pause
)
exit /b 0
