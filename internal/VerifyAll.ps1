param(
    [string]$CivPath='',
    [ValidateSet('Auto','Required','Skip')]
    [string]$RASMode='Auto'
)
$ErrorActionPreference='Stop'
$Root=$PSScriptRoot
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

function Invoke-Verify([string]$Label,[string]$Script,[string]$Civ,[string[]]$ExtraArgs=@()){
    W ''
    W ('==== VERIFY '+$Label+' ====') Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script -CivPath $Civ @ExtraArgs
    if($LASTEXITCODE -ne 0){ throw "$Label verification failed." }
}

try {
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ throw 'Civilization V not found. Pass -CivPath if it is in a nonstandard Steam library.' }
    W ('Civ V: '+$civ) Green

    if(Test-LEKModPresent $civ){
        W 'LEKMOD v30.7 detected.' Green
    } else {
        W 'LEKMOD v30.7 not detected at Assets\DLC\LEKMOD_V30.7 -- everything below depends on it.' Yellow
    }

    Invoke-Verify 'Frozen Core v1.3 (Reroll/Host/UltraFast/RAS v0.8.8)' (Join-Path $Root 'CoreVerify.ps1') $civ @('-RASMode',$RASMode)

    # RAS wonder hotfix and Fair Trades are independent siblings on top of Core --
    # neither depends on the other. Each is verified only if it looks installed
    # (RASMode=Skip means base RAS v0.8.8 itself was skipped, so the wonder hotfix
    # -- which requires v0.8.8 -- cannot be present either).
    $startGame=Join-LEKPath $civ 'Assets\UI\FrontEnd\Multiplayer\GTAS_StartGame.lua'
    $rasWonderInstalled=(Test-LEKPath $startGame) -and (Test-LEKContains $startGame 'GTAS_MP_V089_WONDER_RUNTIME_BEGIN')
    if($RASMode -eq 'Skip'){
        W ''
        W 'RAS wonder hotfix verification skipped (RASMode=Skip: base RAS v0.8.8 was not installed).' Yellow
    } elseif($RASMode -eq 'Required' -or $rasWonderInstalled){
        Invoke-Verify 'RAS wonder hotfix v0.8.9' (Join-Path $Root 'ras-wonder\Verify.ps1') $civ
    } else {
        W ''
        W 'RAS wonder hotfix marker not detected; skipping its verification automatically.' Yellow
    }

    $fairLua=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\LEKFairTrades.lua'
    if(Test-LEKPath $fairLua){
        Invoke-Verify 'Fair Trades' (Join-Path $Root 'fair\Verify.ps1') $civ
    } else {
        W ''
        W 'Fair Trades runtime not detected; skipping its verification automatically.' Yellow
    }

    W ''
    W 'ALL EXPECTED PATCHES VERIFIED.' Green
    exit 0
} catch {
    W ''
    W ('VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    exit 1
}
