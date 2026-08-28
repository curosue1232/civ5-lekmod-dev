param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES - CLEAN EXTENSION UNINSTALL' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before uninstalling.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }
    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    if(Test-LEKPath $inGame){
        $t=[IO.File]::ReadAllText($inGame)
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN' '-- LEK_EXT_FAIR_TRADES_LOADER_END'
        Write-LEKUtf8NoBom $inGame $t
    }
    foreach($name in @('LEKFairTrades.lua','LEKFairTrades.xml')){
        $p=Join-LEKPath $lekUI $name
        if(Test-LEKPath $p){ Remove-Item -LiteralPath $p -Force }
    }

    # Future-proof: if a later Fair Trades version ever owns the allowed stable
    # LeaderHead bridge block, remove only that block, never restore a stale file.
    $leader=Get-LEKLeaderRoot $civ
    if(Test-LEKPath $leader){
        $lt=[IO.File]::ReadAllText($leader)
        if($lt.Contains('-- LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_BEGIN')){
            $lt=Remove-LEKMarkedBlock $lt '-- LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_BEGIN' '-- LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_END'
            Write-LEKUtf8NoBom $leader $lt
        }
    }
    W ''
    W 'FAIR TRADES EXTENSION REMOVED.' Green
    W 'Frozen core stack was not uninstalled or restored from backups.' Green
    exit 0
} catch {
    W ('UNINSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
