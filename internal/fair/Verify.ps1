param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.0.7 SAFE DIAGNOSTIC VERIFY' Cyan
    W '============================================================' Cyan
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    $lua=Join-LEKPath $lekUI 'LEKFairTrades.lua'
    $xml=Join-LEKPath $lekUI 'LEKFairTrades.xml'
    $leader=Get-LEKLeaderRoot $civ
    $good=$true
    $failed=New-Object System.Collections.Generic.List[string]

    function Check([string]$Label,[bool]$Ok){
        if($Ok){ W ('PASS  '+$Label) Green }
        else{ W ('FAIL  '+$Label) Red; $script:good=$false; [void]$failed.Add($Label) }
    }

    Check 'stable loader begin' (Test-LEKContains $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN')
    Check 'stable loader target' (Test-LEKContains $inGame 'ContextPtr:LoadNewContext("LEKFairTrades")')
    Check 'stable loader end' (Test-LEKContains $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_END')
    Check 'stable runtime Lua' (Test-LEKPath $lua)
    Check 'stable runtime XML' (Test-LEKPath $xml)

    if(Test-LEKPath $lua){
        $t=[IO.File]::ReadAllText($lua)
        Check 'runtime version 107' $t.Contains('local VERSION = 107')
        Check 'safe observer marker' $t.Contains('-- LEK_FAIR_TRADES_SAFE_OBSERVER_V107')
        Check 'runtime context hidden' $t.Contains('ContextPtr:SetHide(true)')
        Check 'real turn-start observer hook' $t.Contains('Events.ActivePlayerTurnStart.Add(Scan)')
        Check 'inventory diagnostics' ($t.Contains('_HumanLuxIDs') -and $t.Contains('_AILuxIDs'))
        Check 'no DoBeginDiploWithHuman anywhere' (-not $t.Contains('DoBeginDiploWithHuman'))
        Check 'no AILeaderMessage handler' (-not $t.Contains('Events.AILeaderMessage.Add'))
        Check 'no scratch deal access' (-not $t.Contains('UI.GetScratchDeal'))
        Check 'no trade-screen open' (-not $t.Contains('DoTradeScreenOpened'))
        Check 'no OnHumanOpenedTradeScreen' (-not $t.Contains('UI.OnHumanOpenedTradeScreen'))
        Check 'no GameDataDirty retry' (-not $t.Contains('SerialEventGameDataDirty'))
        Check 'no SetUpdate scanner' (-not $t.Contains('ContextPtr:SetUpdate'))
        Check 'no load bootstrap event' (-not $t.Contains('SequenceGameInitComplete.Add'))
    }

    if(Test-LEKPath $xml){
        $xt=[IO.File]::ReadAllText($xml)
        Check 'Fair Trades context remains hidden' ($xt -match 'Hidden="1"')
    }

    if(Test-LEKPath $leader){
        $lt=[IO.File]::ReadAllText($leader)
        Check 'EUI LeaderHeadRoot.lua left unpatched' (-not $lt.Contains('LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_BEGIN'))
        Check 'no old Fair AI Trades EUI markers' (-not ($lt -match 'LEK_MP_FAIR_AI_TRADES_'))
    }

    if(Test-LEKPath $inGame){
        $igt=[IO.File]::ReadAllText($inGame)
        Check 'no old Fair AI Trades InGame markers' (-not ($igt -match 'LEK_MP_FAIR_AI_TRADES_'))
    }

    W ''
    if($good){ W 'FAIR TRADES v1.0.7 SAFE DIAGNOSTIC VERIFIED.' Green; exit 0 }
    W 'VERIFY FOUND A PROBLEM.' Red
    if($failed.Count -gt 0){
        W 'Failed checks:' Red
        foreach($f in $failed){ W ('  - '+$f) Red }
    }
    exit 1
} catch {
    W ('VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
