param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

function Get-FairEUITradeFiles([string]$Civ){
    $base=Join-LEKPath $Civ 'Assets\DLC\UI_bc1'
    if(!(Test-LEKPath $base -Container)){ return $null }
    $tradeLogic=Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'TradeLogic.lua' -and (Test-LEKContains $_.FullName 'function LeaderMessageHandler') } |
        Select-Object -ExpandProperty FullName -First 1
    $owner=Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'DiploTrade.lua' -and (Test-LEKContains $_.FullName 'Events.AILeaderMessage.Add( LeaderMessageHandler') } |
        Select-Object -ExpandProperty FullName -First 1
    if(!$tradeLogic -or !$owner){ return $null }
    return [pscustomobject]@{ TradeLogic=$tradeLogic; Owner=$owner }
}

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.2.1 AUTHORITATIVE RELATIONSHIP PRICING VERIFY' Cyan
    W '============================================================' Cyan
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    $lua=Join-LEKPath $lekUI 'LEKFairTrades.lua'
    $xml=Join-LEKPath $lekUI 'LEKFairTrades.xml'
    $leader=Get-LEKLeaderRoot $civ
    $euiTrade=Get-FairEUITradeFiles $civ
    $tradeLogic=if($euiTrade){$euiTrade.TradeLogic}else{$null}
    $diploTrade=if($euiTrade){$euiTrade.Owner}else{$null}
    $good=$true
    $failed=New-Object System.Collections.Generic.List[string]

    function Check([string]$Label,[bool]$Ok){
        if($Ok){ W ('PASS  '+$Label) Green }
        else{ W ('FAIL  '+$Label) Red; $script:good=$false; [void]$failed.Add($Label) }
    }

    Check 'stable loader begin' (Test-LEKContains $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN')
    Check 'stable loader target' (Test-LEKContains $inGame 'ContextPtr:LoadNewContext("LEKFairTrades")')
    Check 'stable loader end' (Test-LEKContains $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_END')
    Check 'runtime Lua present' (Test-LEKPath $lua)
    Check 'runtime XML present' (Test-LEKPath $xml)
    Check 'EUI TradeLogic present' (Test-LEKPath $tradeLogic)
    Check 'EUI diplotrade present' (Test-LEKPath $diploTrade)
    Check 'EUI diplotrade owns LeaderMessageHandler registration' ((Test-LEKPath $diploTrade) -and (Test-LEKContains $diploTrade 'Events.AILeaderMessage.Add( LeaderMessageHandler'))

    if(Test-LEKPath $lua){
        $t=[IO.File]::ReadAllText($lua)
        Check 'runtime version 121' $t.Contains('local VERSION=121')
        Check 'v1.2.1 authoritative relationship pricing marker' $t.Contains('-- LEK_FAIR_TRADES_AUTHORITATIVE_RELATIONSHIP_PRICING_V121')
        Check 'v1.2.1 runtime patch' $t.Contains('V121_AUTHORITATIVE_RELATIONSHIP_PRICING')
        Check 'no human-open/fake-event policy' $t.Contains('V118_NO_HUMAN_OPEN_NO_FAKE_AI_EVENT')
        Check 'luxury Gold GPT only' $t.Contains('LUXURY_FLAT_GOLD_GPT_ONLY_V121')
        Check 'explicit relationship GPT rates' ($t.Contains('MAJOR_CIV_APPROACH_GUARDED then return 3') -and $t.Contains('MAJOR_CIV_APPROACH_NEUTRAL then return 5') -and $t.Contains('MAJOR_CIV_APPROACH_FRIENDLY or a==T.MAJOR_CIV_APPROACH_AFRAID then return 7'))
        Check 'flat Gold equals GPT rate times duration' $t.Contains('(rate*Duration()) or rate')
        Check 'currency explicit pricing has no native value veto' (-not $t.Contains('FINAL_AI_ACCEPTANCE_GATE'))
        Check 'old symmetric currency price range removed' (-not ($t.Contains('NO_MUTUALLY_FAIR_CURRENCY_RANGE') -or $t.Contains('local minAmount=') -or $t.Contains('local maxAmount=')))
        Check 'fixed currency shapes cost no native evaluations' $t.Contains('local cost=(shape=="SWAP") and 1 or 0')
        Check 'luxury swaps retain strict two-sided fairness' $t.Contains('if not BothFair(v) then return nil,"NATIVE_SWAP_VALUE_GATE" end')
        Check 'currency offers both ways' $t.Contains('LUXURY_FOR_GOLD_OR_GPT_BOTH_WAYS')
        Check 'both sides preserve last copy' $t.Contains('BOTH_SIDES_PRESERVE_LAST_COPY')
        Check 'spare luxury requires two copies' $t.Contains('GetNumResourceAvailable(r.ID,true) or 0)>=2')
        Check 'native same-side value APIs used' ($t.Contains('GetDealMyValue') -and $t.Contains('GetDealTheyreValue'))
        Check 'native fairness checks both players' $t.Contains('v.aiThey>=v.aiMy and v.hThey>=v.hMy')
        Check '8-evaluation ceiling' $t.Contains('local MAX_EVALS=8')
        Check 'human luxury for AI Gold shape' $t.Contains('HUMAN_LUX_FOR_AI_GOLD')
        Check 'human luxury for AI GPT shape' $t.Contains('HUMAN_LUX_FOR_AI_GPT')
        Check 'AI luxury for human Gold shape' $t.Contains('AI_LUX_FOR_HUMAN_GOLD')
        Check 'AI luxury for human GPT shape' $t.Contains('AI_LUX_FOR_HUMAN_GPT')
        Check 'Gold legality uses canonical amount-only signature' $t.Contains('Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD,amount)')
        Check 'GPT legality uses canonical duration signature' $t.Contains('Possible(d,from,to,TradeableItems.TRADE_ITEM_GOLD_PER_TURN,amount,Duration())')
        Check 'no zero-duration currency legality probe' (-not ($t.Contains('TRADE_ITEM_GOLD,amount,0') -or $t.Contains('TRADE_ITEM_GOLD_PER_TURN,amount,0')))
        Check 'distinct currency luxury picker present' $t.Contains('local function PickOtherRes')
        Check 'Gold and GPT use distinct AI luxury picks' ($t.Contains('local aGoldRes=PickRes') -and $t.Contains('local aGPTRes=PickOtherRes'))
        Check 'Gold and GPT use distinct human luxury picks' ($t.Contains('local hGoldRes=PickRes') -and $t.Contains('local hGPTRes=PickOtherRes'))
        Check 'distinct picker preserves singleton/noncollision picks' $t.Contains('#list<=1 or picked~=avoid')
        Check 'distinct picker rotates a collided pick' $t.Contains('list[(i%#list)+1]')
        Check 'per-shape currency luxury ID telemetry' ($t.Contains('_HUMAN_GOLD_ResourceID') -and $t.Contains('_HUMAN_GPT_ResourceID') -and $t.Contains('_AI_GOLD_ResourceID') -and $t.Contains('_AI_GPT_ResourceID'))
        Check 'no native trade helper' (-not ($t.Contains('UI.DoWhatWillAIGive') -or $t.Contains('UI.DoWhatDoesAIWant') -or $t.Contains('UI.DoEqualizeDealWithHuman')))
        Check 'no executable human-open trade call' ([regex]::Matches($t,'UI\.OnHumanOpenedTradeScreen\s*\(').Count -eq 0)
        Check 'no executable spoofed AILeaderMessage event' ([regex]::Matches($t,'Events\.AILeaderMessage\s*\(').Count -eq 0)
        Check 'private LuaEvents bridge used' $t.Contains('LuaEvents.LEKFairTradesAIOffer(ai,FAIR_MESSAGE)')
        Check 'bridge ready guard' $t.Contains('LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_READY')
        Check 'bridge handled acknowledgement' $t.Contains('LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_LAST_HANDLED_AI')
        Check 'one backend trade-session open call' ([regex]::Matches($t,'(?m)^\s*Players\[ai\]:DoTradeScreenOpened\(\)\s*$').Count -eq 1)
        Check 'direct rebuild function present' $t.Contains('local function RebuildCandidate')
        Check 'strategics never' $t.Contains('S("StrategicResources","NEVER")')
        Check 'no SetUpdate scanner' (-not $t.Contains('ContextPtr:SetUpdate'))
        Check 'real turn-start hook' $t.Contains('Events.ActivePlayerTurnStart.Add(Start)')

        Check 'multi-AI candidate search present' $t.Contains('local function FindCandidate')
        Check 'multi-AI presession search protected' $t.Contains('local ok,seed,reason=pcall(function()')
        Check 'shared evaluation budget reset once' ([regex]::Matches($t,'evals=0; S\("OfferNativeEvals",0\)').Count -eq 1)
        Check 'candidate carried into display handoff' $t.Contains('local candidate=seed.candidate')
        Check 'multi-AI rejection telemetry' $t.Contains('_PartnerRejected')
        $tryIndex=$t.IndexOf('local candidate,why=TryShapes')
        $sessionIndex=$t.IndexOf('Players[ai]:DoTradeScreenOpened()')
        $rebuildIndex=$t.IndexOf('RebuildCandidate(d,candidate,h,ai)')
        $bridgeIndex=$t.IndexOf('LuaEvents.LEKFairTradesAIOffer(ai,FAIR_MESSAGE)')
        Check 'candidate search happens before backend session' ($tryIndex -ge 0 -and $sessionIndex -gt $tryIndex)
        Check 'direct rebuild happens after backend session' ($rebuildIndex -gt $sessionIndex)
        Check 'EUI handler dispatch happens after rebuild' ($bridgeIndex -gt $rebuildIndex)
        if($sessionIndex -ge 0){
            $afterSession=$t.Substring($sessionIndex)
            Check 'no GetDealMyValue after backend opens' (-not $afterSession.Contains('GetDealMyValue'))
            Check 'no GetDealTheyreValue after backend opens' (-not $afterSession.Contains('GetDealTheyreValue'))
            Check 'no IsPossibleToTradeItem after backend opens' (-not $afterSession.Contains('IsPossibleToTradeItem'))
        } else {
            Check 'no GetDealMyValue after backend opens' $false
            Check 'no GetDealTheyreValue after backend opens' $false
            Check 'no IsPossibleToTradeItem after backend opens' $false
        }
    }

    if(Test-LEKPath $diploTrade){
        $dt=[IO.File]::ReadAllText($diploTrade)
        Check 'direct EUI bridge begin' $dt.Contains('-- LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_BEGIN')
        Check 'direct EUI bridge end' $dt.Contains('-- LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_END')
        Check 'exactly one direct EUI bridge' ([regex]::Matches($dt,'LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_BEGIN').Count -eq 1)
        Check 'EUI bridge ready marker' $dt.Contains('LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_READY = true')
        Check 'EUI bridge listens to private LuaEvent' $dt.Contains('LuaEvents.LEKFairTradesAIOffer.Add')
        Check 'EUI bridge calls LeaderMessageHandler directly' $dt.Contains('pcall(LeaderMessageHandler, iPlayer, DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER, szMessage, -1, 0)')
        Check 'EUI bridge acknowledges handled AI' $dt.Contains('LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_LAST_HANDLED_AI = iPlayer')
        Check 'Fair Trades offer tracks active AI' $dt.Contains('LEK_FAIR_TRADES_EUI_OFFER_ACTIVE_AI = iPlayer')
        Check 'Fair Trades offer pauses automatic turn progress' ($dt.Contains('UI.incTurnTimerSemaphore()') -and $dt.Contains('LEK_FAIR_TRADES_EUI_OFFER_TURN_PAUSED = true'))
        Check 'Fair Trades turn pause has balanced one-shot release' ($dt.Contains('local function LEKFairTradesReleaseTurnPause()') -and $dt.Contains('UI.decTurnTimerSemaphore()') -and ([regex]::Matches($dt,'LEKFairTradesReleaseTurnPause\(\)').Count -ge 4))
        Check 'Fair Trades turn pause releases on bridge failure' ($dt.Contains('if not handled then') -and $dt.Contains('error(handleError)'))
        Check 'accepted Fair Trades offer auto-exits leader view' ($dt.Contains('DIPLO_UI_STATE_TRADE_AI_ACCEPTS_OFFER') -and $dt.Contains('DIPLO_UI_STATE_BLANK_DISCUSSION') -and $dt.Contains('UI.SetLeaderHeadRootUp(false)') -and $dt.Contains('UI.RequestLeaveLeader()'))
        Check 'post-accept auto-exit is one-shot' $dt.Contains('LEK_FAIR_TRADES_EUI_OFFER_AUTO_EXIT_CLOSING')
        Check 'Fair Trades marker clears when leader view leaves' $dt.Contains('Events.LeavingLeaderViewMode.Add')
    }

    if(Test-LEKPath $tradeLogic){
        $tl=[IO.File]::ReadAllText($tradeLogic)
        $bridgeBegin='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_BEGIN'
        $bridgeEnd='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_END'
        $fairMessage='I have a trade proposal that I believe is fair to both of us.'
        $hasBegin=$tl.Contains($bridgeBegin)
        $hasEnd=$tl.Contains($bridgeEnd)
        $hasScoped=($tl -match 'AIOfferingLux\(\)') -and $tl.Contains($fairMessage)
        if($hasBegin -or $hasEnd){
            Check 'optional luxury bridge markers paired' ($hasBegin -and $hasEnd)
            Check 'optional luxury bridge is message-scoped' $hasScoped
        } else {
            W 'PASS  optional luxury bridge not required by this EUI layout' Green
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
    if($good){ W 'FAIR TRADES v1.2.1 AUTHORITATIVE RELATIONSHIP PRICING VERIFIED.' Green; exit 0 }
    W 'VERIFY FOUND A PROBLEM.' Red
    foreach($f in $failed){ W ('  - '+$f) Red }
    exit 1
} catch {
    W ('VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
