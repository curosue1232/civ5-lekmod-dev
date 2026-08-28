param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.0.2 VERIFY' Cyan
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

    $checks=@(
        @('stable loader begin', (Test-LEKContains $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN')),
        @('stable loader target', (Test-LEKContains $inGame 'ContextPtr:LoadNewContext("LEKFairTrades")')),
        @('stable loader end', (Test-LEKContains $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_END')),
        @('stable runtime Lua', (Test-LEKPath $lua)),
        @('stable runtime XML', (Test-LEKPath $xml))
    )
    foreach($c in $checks){ if($c[1]){W ('PASS  '+$c[0]) Green}else{W ('FAIL  '+$c[0]) Red;$good=$false} }

    if(Test-LEKPath $lua){
        $t=[IO.File]::ReadAllText($lua)
        foreach($c in @(
            @('runtime version 102', $t.Contains('local RUNTIME_VERSION = 102')),
            @('native what-will-AI-give engine', $t.Contains('UI.DoWhatWillAIGive()')),
            @('native what-does-AI-want engine', $t.Contains('UI.DoWhatDoesAIWant()')),
            @('hard 8-call helper budget', $t.Contains('MAX_NATIVE_HELPER_CALLS_PER_TURN = 8')),
            @('human fairness gate', $t.Contains('if aiGives < humanGives then return false, "HUMAN_FAIRNESS_GATE" end')),
            @('strategics rejected', $t.Contains('UNSUPPORTED_OR_STRATEGIC_ITEM')),
            @('turn-start event hook', $t.Contains('Events.ActivePlayerTurnStart.Add(OnTurnStart)')),
            @('bounded queue retry marker', $t.Contains('-- LEK_FAIR_TRADES_QUEUE_RETRY_V102_BEGIN')),
            @('defer clears itself', $t.Contains('ContextPtr:ClearUpdate()')),
            @('defer has hard timeout', $t.Contains('TURN_START_MESSAGE_QUEUE_RETRY_TIMEOUT')),
            @('no GameDataDirty scanner', -not [regex]::IsMatch($t, '(?m)^[ \t]*(Events\.)?SerialEventGameDataDirty\.(Add|Call)[ \t]*\(')),
            @('no old GetTotalValue loop', -not $t.Contains('GetTotalValueToMeNormal'))
        )){
            if($c[1]){W ('PASS  '+$c[0]) Green}else{W ('FAIL  '+$c[0]) Red;$good=$false}
        }

        $setUpdateMatches=[regex]::Matches($t,'(?m)^[ \t]*ContextPtr:SetUpdate[ \t]*\(')
        if($setUpdateMatches.Count -le 1){
            W 'PASS  no persistent SetUpdate scanner (only bounded retry allowed)' Green
        }else{
            W ('FAIL  unexpected SetUpdate calls: '+$setUpdateMatches.Count) Red
            $good=$false
        }
    }

    if(Test-LEKPath $leader){
        $lt=[IO.File]::ReadAllText($leader)
        if($lt.Contains('LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_BEGIN')){
            W 'FAIL  v1.0.x should not patch EUI LeaderHeadRoot.lua' Red; $good=$false
        }else{ W 'PASS  EUI LeaderHeadRoot.lua left unpatched' Green }
        if($lt -match 'LEK_MP_FAIR_AI_TRADES_'){
            W 'FAIL  old Fair AI Trades EUI marker remains' Red; $good=$false
        }else{ W 'PASS  no old Fair AI Trades EUI markers' Green }
    }

    $igt=[IO.File]::ReadAllText($inGame)
    if($igt -match 'LEK_MP_FAIR_AI_TRADES_'){ W 'FAIL  old Fair AI Trades InGame marker remains' Red; $good=$false }
    else{ W 'PASS  no old Fair AI Trades InGame markers' Green }

    W ''
    if($good){ W 'FAIR TRADES v1.0.2 VERIFIED.' Green; exit 0 }
    W 'VERIFY FOUND A PROBLEM.' Red; exit 1
} catch {
    W ('VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
