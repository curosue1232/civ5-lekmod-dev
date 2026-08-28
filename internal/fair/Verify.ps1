param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.0.6 VERIFY' Cyan
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
        Check 'runtime version 106' $t.Contains('local VERSION=106')
        Check 'silent native valuation marker' $t.Contains('-- LEK_FAIR_TRADES_SILENT_NATIVE_VALUATION_V106')
        Check 'inventory-first luxury discovery' $t.Contains('-- LEK_FAIR_TRADES_INVENTORY_SEED_FIX_V106')
        Check 'transient ready-signal marker' $t.Contains('-- LEK_FAIR_TRADES_TRANSIENT_READY_SIGNAL_V106_BEGIN')
        Check 'runtime context hidden' $t.Contains('ContextPtr:SetHide(true)')
        Check 'native GetDealMyValue engine' $t.Contains('GetDealMyValue(d)')
        Check 'native GetDealTheyreValue engine' $t.Contains('GetDealTheyreValue(d)')
        Check 'hard 8-evaluation budget' $t.Contains('local MAX_EVALS=8')
        Check 'AI native acceptance gate' $t.Contains('if v.aiThey<v.aiMy then')
        Check 'human native fairness gate' $t.Contains('if v.hThey<v.hMy then')
        Check 'strategics rejected structurally' $t.Contains('UNSUPPORTED_OR_STRATEGIC_ITEM')
        Check 'two-sided deal required' $t.Contains('ONE_SIDED_DEAL')
        Check 'turn-start event hook' $t.Contains('Events.ActivePlayerTurnStart.Add(Start)')
        Check 'turn-end retry cleanup' $t.Contains('Events.ActivePlayerTurnEnd.Add(Finish)')
        Check 'transient GameDataDirty add' $t.Contains('Events.SerialEventGameDataDirty.Add(Ready)')
        Check 'transient GameDataDirty remove' $t.Contains('Events.SerialEventGameDataDirty.Remove(Ready)')
        Check 'rolling scan trail' $t.Contains('OfferScanTrail')
        Check 'seed inventory IDs diagnostics' ($t.Contains('_HumanLuxIDs') -and $t.Contains('_AILuxIDs'))
        Check 'no executable SetUpdate' (-not [regex]::IsMatch($t, '(?m)^[ \t]*ContextPtr:SetUpdate[ \t]*\('))
        Check 'no executable DoWhatWillAIGive' (-not [regex]::IsMatch($t, '(?m)^[ \t]*UI\.DoWhatWillAIGive[ \t]*\('))
        Check 'no executable DoWhatDoesAIWant' (-not [regex]::IsMatch($t, '(?m)^[ \t]*UI\.DoWhatDoesAIWant[ \t]*\('))

        # Count executable registrations/removals even when the call is guarded
        # later on the line (e.g. "if retryRegistered then Events....Remove").
        # Comments are excluded so documentation cannot affect verification.
        $dirtyAddCount=[regex]::Matches($t,'(?m)^[ \t]*(?!--)[^\r\n]*\bEvents\.SerialEventGameDataDirty\.Add[ \t]*\(').Count
        $dirtyRemoveCount=[regex]::Matches($t,'(?m)^[ \t]*(?!--)[^\r\n]*\bEvents\.SerialEventGameDataDirty\.Remove[ \t]*\(').Count
        Check 'exactly one transient dirty add' ($dirtyAddCount -eq 1)
        Check 'exactly one transient dirty remove' ($dirtyRemoveCount -eq 1)
        Check 'no old GetTotalValue loop' (-not $t.Contains('GetTotalValueToMeNormal'))

        $spare=[regex]::Match($t,'(?s)local function SpareLux\(.*?local function Prep').Value
        $prematurePossible=$false
        if($spare){ $prematurePossible=[regex]::IsMatch($spare,'(?m)^[ \t]*(?!--).*\bPossible[ \t]*\(') }
        Check 'no premature executable Possible() in inventory discovery' ($spare -and -not $prematurePossible)
    }

    if(Test-LEKPath $xml){
        $xt=[IO.File]::ReadAllText($xml)
        Check 'event-driven Fair Trades context is hidden' ($xt -match 'Hidden="1"')
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
    if($good){ W 'FAIR TRADES v1.0.6 VERIFIED.' Green; exit 0 }
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
