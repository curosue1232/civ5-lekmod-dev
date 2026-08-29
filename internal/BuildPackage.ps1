param(
    [string]$PackageName='LEKMOD_30_7_Combined_Stack',
    [string]$OutputDir='',
    [switch]$NoZip
)
$ErrorActionPreference='Stop'
$RepoRoot=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($OutputDir)){ $OutputDir=Join-Path $RepoRoot 'dist' }
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

$packageReadme=@'
LEKMOD 30.7 COMBINED STACK - CORE + RAS WONDER HOTFIX + FAIR TRADES
====================================================================

This is a standalone, self-contained package. It does not require Git or any
development tooling -- extract it anywhere and run the .bat files.

REQUIRED BEFORE YOU START (not included in this package)
----------------------------------------------------------
This package only patches an existing LEKMOD + EUI installation -- it never
bundles either one, because both explicitly prohibit redistributing their
files without the author's permission (LEKMOD's LICENSE; EUI's CivFanatics
"Fair use" terms). Install these two yourself first:

  1. LEKMOD v30.7 (the actual latest release as of this writing):
     https://github.com/EnormousApplePie/Lekmod/releases/tag/v30.7
     Help: https://discord.gg/VQBNPmc

  2. EUI (Enhanced User Interface), v1.28 or EARLIER -- LEKMOD does not
     support EUI v1.29 or higher:
     https://forums.civfanatics.com/resources/civ5-enhanced-user-interface.24303/

INSTALL_ALL.bat checks for both before changing anything and will offer to
open these exact links if either is missing.

COMPONENTS INCLUDED
--------------------
1. LEK Core v1.3
   - MP Reroll / Rehost v0.21 Auto-Join
   - Host Instant Start v0.1
   - UltraFast MP Startup v0.3.1 Reroll-Safe
   - RAS MP Bridge v0.8.8 Restart Settings Replay
2. RAS MP Bridge v0.8.9 - Targeted Wonder Graphics Hotfix (on top of RAS v0.8.8)
3. Fair Trades v1.2.5 - proactive AI trade offers (on top of Core only; does
   not require RAS)
4. Space Next Action v0.2 - Space bar activates the main action
   button above the minimap

USAGE
-----
1. Close Civilization V.
2. Run INSTALL_ALL.bat. It auto-detects your Civ V install (or asks for the
   folder), installs everything in the safe order, and verifies at the end.
3. To re-check an existing install, run VERIFY_ALL.bat.
4. To remove everything this package installed, run UNINSTALL_ALL.bat.

IMPORTANT RAS PREREQUISITE
---------------------------
RAS MP Bridge v0.8.8 (and the wonder hotfix built on top of it) requires an
already-installed "v0.8.7.2 Sticky Reroll Bypass" base, which this package
does not include. If it's missing, INSTALL_ALL.bat detects this before
changing any files and offers to install Core (Reroll/Rehost, Host Instant
Start, UltraFast) plus Fair Trades without RAS, or to cancel so you can
install the v0.8.7.2 base first.

SAFE INSTALL ORDER
-------------------
Reroll/Rehost -> Host Instant Start -> UltraFast -> RAS v0.8.8 -> RAS wonder
hotfix -> Fair Trades. This matters because some packages patch the same Civ V
frontend Lua files and their backups nest. UNINSTALL_ALL.bat reverses this
order.

NOTES
-----
- Install this on every human player's computer in a multiplayer game.
- Host Instant Start is host-only in function, but harmless on clients.
- This package does not install Lekmod 30.7, EUI, or the older RAS v0.8.7.x
  base -- those must already be present; each component's installer verifies
  its own prerequisites before changing anything.
- Steam file verification can overwrite patched Civ V Assets/UI files; rerun
  INSTALL_ALL.bat afterward if that happens.

WHAT'S INSIDE
-------------
INSTALL_ALL.bat / VERIFY_ALL.bat / UNINSTALL_ALL.bat  - the three entry points
internal\InstallAll.ps1 / VerifyAll.ps1 / UninstallAll.ps1  - their logic
internal\LekTools.ps1        - shared helpers (Civ V detection, file patching)
internal\CoreVerify.ps1      - combined core verifier
internal\core\               - Core v1.3 install/uninstall/verify per component
internal\ras-wonder\         - RAS wonder graphics hotfix v0.8.9
internal\fair\               - Fair Trades v1.2.5
internal\thumb-action\       - Space Next Action v0.2
'@

try {
    W '============================================================' Cyan
    W ' BUILDING STANDALONE PACKAGE' Cyan
    W '============================================================' Cyan

    $resolvedOutput=[IO.Path]::GetFullPath($OutputDir).TrimEnd('\')
    $pkgRoot=[IO.Path]::GetFullPath((Join-Path $resolvedOutput $PackageName))
    $expectedPrefix=$resolvedOutput+'\'
    if([string]::IsNullOrWhiteSpace($PackageName) -or
       $pkgRoot -eq $resolvedOutput -or
       -not $pkgRoot.StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase)){
        throw 'PackageName must resolve to a child folder inside OutputDir.'
    }
    if(Test-Path -LiteralPath $pkgRoot){
        W ('Removing previous build at '+$pkgRoot) Yellow
        Remove-Item -LiteralPath $pkgRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $pkgRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $pkgRoot 'internal') | Out-Null
    W ('Package root: '+$pkgRoot) Green

    foreach($bat in @('INSTALL_ALL.bat','VERIFY_ALL.bat','UNINSTALL_ALL.bat')){
        $src=Join-Path $RepoRoot $bat
        if(!(Test-Path -LiteralPath $src)){ throw "Missing expected launcher: $src" }
        Copy-Item -LiteralPath $src -Destination $pkgRoot -Force
    }

    $internalItems=@('LekTools.ps1','CoreVerify.ps1','InstallAll.ps1','VerifyAll.ps1','UninstallAll.ps1','core','ras-wonder','fair','thumb-action')
    foreach($item in $internalItems){
        $src=Join-Path $RepoRoot ('internal\'+$item)
        $dst=Join-Path $pkgRoot ('internal\'+$item)
        if(!(Test-Path -LiteralPath $src)){ throw "Missing expected source item: $src" }
        if((Get-Item -LiteralPath $src).PSIsContainer){
            Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        } else {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        W ('Copied internal\'+$item) DarkGray
    }

    [IO.File]::WriteAllText((Join-Path $pkgRoot 'README.txt'), $packageReadme)
    W 'Wrote README.txt' DarkGray

    if(-not $NoZip){
        $zipPath=Join-Path $resolvedOutput ($PackageName+'.zip')
        if(Test-Path -LiteralPath $zipPath){ Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path $pkgRoot -DestinationPath $zipPath -CompressionLevel Optimal
        W ('Zipped: '+$zipPath) Green
    }

    W ''
    W '============================================================' Green
    W ' PACKAGE BUILD COMPLETE' Green
    W '============================================================' Green
    W ('Folder: '+$pkgRoot) Gray
    if(-not $NoZip){ W ('Zip:    '+(Join-Path $OutputDir ($PackageName+'.zip'))) Gray }
    exit 0
} catch {
    W ''
    W ('BUILD ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    exit 1
}
