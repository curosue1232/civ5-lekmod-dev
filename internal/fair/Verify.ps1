param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.1.3 ONE-SESSION NATIVE VERIFY' Cyan
    W '============================================================' Cyan
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    $lua=Join-LEKPath $lekUI 'LEKFairTrades.lua'
    $xml=Join-LEKPath $lekUI 'LEKFairTrades.xml'
    $leader=Get-LEKLeaderRoot $civ
    $tradeLogic=Join-LEKPath $civ 'Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua'
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
    Check 'EUI TradeLogic present' (Test-LEKPath $tradeLogic)

    if(Test-LEKPath $lua){
        $t=[IO.File]::ReadAllText($lua)
        Check 'runtime version 113' $t.Contains('local VERSION=113')
        Check 'v1.1.3 one-session marker' $t.Contains('-- LEK_FAIR_TRADES_ONE_SESSION_NATIVE_V113')
        Check 'one-session runtime patch' $t.Contains('V113_ONE_SESSION_NATIVE_HELPER')
        Check 'luxury Gold GPT only' $t.Contains('LUXURY_FLAT_GOLD_GPT_ONLY_V113')
        Check 'currency offers both ways' $t.Contains('LUXURY_FOR_GOLD_OR_GPT_BOTH_WAYS')
        Check 'both sides preserve last copy' $t.Contains('BOTH_SIDES_PRESERVE_LAST_COPY')
        Check 'spare luxury requires two copies' $t.Contains('GetNumResourceAvailable(r.ID,true) or 0)>=2')
        Check 'last-copy helper result rejected' $t.Contains('NATIVE_HELPER_USED_LAST_LUXURY')
        Check 'native give helper' $t.Contains('UI.DoWhatWillAIGive')
        Check 'native want helper' $t.Contains('UI.DoWhatDoesAIWant')
        Check 'native equalizer fallback' $t.Contains('UI.DoEqualizeDealWithHuman')
        Check 'helpers bounded to three tries' $t.Contains('local MAX_HELPER_TRIES=3')
        Check 'flat Gold result validation' $t.Contains('TRADE_ITEM_GOLD')
        Check 'GPT result validation' $t.Contains('TRADE_ITEM_GOLD_PER_TURN')
        Check 'human luxury for AI Gold shape' $t.Contains('HUMAN_LUX_FOR_AI_GOLD')
        Check 'human luxury for AI GPT shape' $t.Contains('HUMAN_LUX_FOR_AI_GPT')
        Check 'AI luxury for human Gold shape' $t.Contains('AI_LUX_FOR_HUMAN_GOLD')
        Check 'AI luxury for human GPT shape' $t.Contains('AI_LUX_FOR_HUMAN_GPT')
        Check 'no custom native value math' (-not ($t.Contains('GetDealMyValue') -or $t.Contains('GetDealTheyreValue') -or $t.Contains('MAX_EVALS')))
        Check 'no custom currency insertion' (-not ($t.Contains('AddGoldTrade') -or $t.Contains('AddGoldPerTurnTrade')))
        Check 'one trade-session open call in runtime' ([regex]::Matches($t,'DoTradeScreenOpened\(\)').Count -eq 1)
        Check 'one human-opened trade call in runtime' ([regex]::Matches($t,'UI\.OnHumanOpenedTradeScreen').Count -eq 1)
        Check 'native scratch shown in place' $t.Contains('NO_SNAPSHOT_REBUILD_SHOW_NATIVE_SCRATCH_IN_PLACE')
        Check 'unique Fair Trades offer message' $t.Contains('I have a trade proposal that I believe is fair to both of us.')
        Check 'native AI offer state' $t.Contains('DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER')
        Check 'no DoBeginDiploWithHuman' (-not $t.Contains('DoBeginDiploWithHuman'))
        Check 'strategics never' $t.Contains('S("StrategicResources","NEVER")')
        Check 'no SetUpdate scanner' (-not $t.Contains('ContextPtr:SetUpdate'))
        Check 'no load bootstrap event' (-not $t.Contains('SequenceGameInitComplete.Add'))
        Check 'real turn-start hook' $t.Contains('Events.ActivePlayerTurnStart.Add(Start)')
    }

    # EUI layouts differ. The bridge is helpful when the known luxury
    # suppression branch exists, but alternate EUI layouts are non-fatal.
    if(Test-LEKPath $tradeLogic){
        $tl=[IO.File]::ReadAllText($tradeLogic)
        $bridgeBegin='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_BEGIN'
        $bridgeEnd='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_END'
        $fairMessage='I have a trade proposal that I believe is fair to both of us.'
        $hasBegin=$tl.Contains($bridgeBegin)
        $hasEnd=$tl.Contains($bridgeEnd)
        $hasScoped=($tl -match 'AIOfferingLux\(\)') -and $tl.Contains($fairMessage)
        $simpleSuppression=[regex]::IsMatch($tl,'(?m)^[ \t]*(?:if|elseif)[ \t]+AIOfferingLux\(\)[ \t]+then(?:[ \t]*(?:--[^\r\n]*)?)$')

        if($hasBegin -or $hasEnd){
            Check 'EUI bridge markers paired' ($hasBegin -and $hasEnd)
            Check 'message-scoped EUI luxury bridge' $hasScoped
            Check 'exactly one EUI bridge' ([regex]::Matches($tl,'LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_BEGIN').Count -eq 1)
        } elseif($hasScoped) {
            W 'PASS  existing message-scoped EUI luxury handling' Green
        } elseif($simpleSuppression) {
            W 'WARN  EUI has a simple AIOfferingLux suppression branch without our bridge.' Yellow
        } elseif($tl -match 'AIOfferingLux\(\)') {
            W 'PASS  alternate EUI AIOfferingLux layout accepted' Green
        } else {
            W 'PASS  EUI has no AIOfferingLux suppression branch; bridge not required' Green
        }
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
    if($good){ W 'FAIR TRADES v1.1.3 ONE-SESSION NATIVE VERIFIED.' Green; exit 0 }
    W 'VERIFY FOUND A PROBLEM.' Red
    foreach($f in $failed){ W ('  - '+$f) Red }
    exit 1
} catch {
    W ('VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
