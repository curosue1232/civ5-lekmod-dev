param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.0.8 VERIFY' Cyan
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
        Check 'runtime version 108' $t.Contains('local VERSION=108')
        Check 'v108 direct-offer marker' $t.Contains('-- LEK_FAIR_TRADES_DIRECT_NATIVE_OFFER_V108')
        Check 'no DoBeginDiploWithHuman' (-not $t.Contains('DoBeginDiploWithHuman'))
        Check 'direct native offer state' $t.Contains('DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER')
        Check 'native trade screen open' ($t.Contains('DoTradeScreenOpened()') -and $t.Contains('UI.OnHumanOpenedTradeScreen'))
        Check 'silent native valuation' ($t.Contains('GetDealMyValue') -and $t.Contains('GetDealTheyreValue'))
        Check 'luxury gold GPT only' $t.Contains('LUXURY_GOLD_GPT_ONLY_V108')
        Check 'strategics never' $t.Contains('S("StrategicResources","NEVER")')
        Check 'no SetUpdate scanner' (-not $t.Contains('ContextPtr:SetUpdate'))
        Check 'no load bootstrap event' (-not $t.Contains('SequenceGameInitComplete.Add'))
        Check 'real turn-start hook' $t.Contains('Events.ActivePlayerTurnStart.Add(Start)')
    }

    if(Test-LEKPath $xml){
        $xt=[IO.File]::ReadAllText($xml)
        Check 'Fair Trades context hidden' ($xt -match 'Hidden="1"')
    }

    if(Test-LEKPath $leader){
        $lt=[IO.File]::ReadAllText($leader)
        Check 'EUI LeaderHeadRoot left unpatched' (-not $lt.Contains('LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_BEGIN'))
        Check 'no old Fair AI Trades EUI markers' (-not ($lt -match 'LEK_MP_FAIR_AI_TRADES_'))
    }

    W ''
    if($good){ W 'FAIR TRADES v1.0.8 VERIFIED.' Green; exit 0 }
    W 'VERIFY FOUND A PROBLEM.' Red
    foreach($f in $failed){ W ('  - '+$f) Red }
    exit 1
} catch {
    W ('VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
