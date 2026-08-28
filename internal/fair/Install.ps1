param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

function Get-FairEUITradeFiles([string]$Civ){
    $base=Join-LEKPath $Civ 'Assets\DLC\UI_bc1'
    if(!(Test-LEKPath $base -Container)){ return $null }
    $tradeLogic=$null
    $owner=$null
    foreach($relative in @('LeaderHead\TradeLogic.lua')){
        $p=Join-LEKPath $base $relative
        if((Test-LEKPath $p) -and (Test-LEKContains $p 'function LeaderMessageHandler')){ $tradeLogic=$p; break }
    }
    if(!$tradeLogic){
        $tradeLogic=Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq 'TradeLogic.lua' -and (Test-LEKContains $_.FullName 'function LeaderMessageHandler') } |
            Select-Object -ExpandProperty FullName -First 1
    }
    foreach($relative in @('bugfixes\diplotrade.lua','Improvements\DiploTrade.lua')){
        $p=Join-LEKPath $base $relative
        if((Test-LEKPath $p) -and (Test-LEKContains $p 'Events.AILeaderMessage.Add( LeaderMessageHandler')){ $owner=$p; break }
    }
    if(!$owner){
        $owner=Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq 'DiploTrade.lua' -and (Test-LEKContains $_.FullName 'Events.AILeaderMessage.Add( LeaderMessageHandler') } |
            Select-Object -ExpandProperty FullName -First 1
    }
    if(!$tradeLogic -or !$owner){ return $null }
    return [pscustomobject]@{ TradeLogic=$tradeLogic; Owner=$owner }
}

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.1.5 EUI DIRECT OFFER BRIDGE INSTALLER' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before installing.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }
    W ('Civ V: '+$civ) Green

    W ''
    W 'Preflight: verifying frozen core stack...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $PSScriptRoot) 'CoreVerify.ps1') -CivPath $civ -RASMode Auto
    if($LASTEXITCODE -ne 0){ throw 'Frozen LEK Core v1.3 verification failed. Fair Trades was not installed.' }

    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    $leader=Get-LEKLeaderRoot $civ
    $euiTrade=Get-FairEUITradeFiles $civ
    $tradeLogic=if($euiTrade){$euiTrade.TradeLogic}else{$null}
    $diploTrade=if($euiTrade){$euiTrade.Owner}else{$null}
    if(!(Test-LEKPath $inGame)){ throw 'Lekmod InGame.lua not found.' }
    if(!(Test-LEKPath $leader)){ throw 'EUI LeaderHeadRoot.lua not found.' }
    if(!$euiTrade){ throw 'EUI trade context not found. Expected TradeLogic.lua with LeaderMessageHandler and a DiploTrade.lua that registers it.' }
    W ('EUI trade owner: '+$diploTrade) Green

    $old=@()
    foreach($p in @($inGame,$leader,$tradeLogic,$diploTrade)){
        $txt=[IO.File]::ReadAllText($p)
        if($txt -match 'LEK_MP_FAIR_AI_TRADES_'){ $old += ('old marker in '+$p) }
    }
    foreach($f in @(Get-ChildItem -LiteralPath $lekUI -File -ErrorAction SilentlyContinue)){
        if($f.Name -match '^LEKMPFairTrades.*\.(lua|xml)$'){ $old += ('old runtime '+$f.FullName) }
    }
    if($old.Count -gt 0){
        foreach($o in $old){ W ('FOUND  '+$o) Yellow }
        throw 'Old Fair AI Trades remnants detected. Run the cleanup tool first; nothing was changed.'
    }

    $backupRoot=Join-Path $Root 'local\backups\fair'
    [void](Backup-LEKFileOnce $inGame $backupRoot 'InGame.lua')
    [void](Backup-LEKFileOnce $tradeLogic $backupRoot 'TradeLogic.lua')
    [void](Backup-LEKFileOnce $diploTrade $backupRoot 'diplotrade.lua')

    Set-LEKMarkedBlock $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN' '-- LEK_EXT_FAIR_TRADES_LOADER_END' 'ContextPtr:LoadNewContext("LEKFairTrades")'

    # EUI's bugfixes/diplotrade.lua includes TradeLogic and owns the live
    # LeaderMessageHandler registration. Expose one private LuaEvents bridge so
    # Fair Trades can enter AI-offer mode directly in that exact context.
    $offerBridgeBody=@'
MapModData = MapModData or {}
MapModData.LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_READY = true
LuaEvents.LEKFairTradesAIOffer.Add(function(iPlayer, szMessage)
    MapModData.LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_LAST_CALLED_AI = iPlayer
    LeaderMessageHandler(iPlayer, DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER, szMessage, -1, 0)
    MapModData.LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_LAST_HANDLED_AI = iPlayer
    MapModData.LEK_FAIR_TRADES_EUI_OFFER_BRIDGE_LAST_HANDLED_STATE = DiploUIStateTypes.DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER
end)
'@
    Set-LEKMarkedBlock $diploTrade '-- LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_BEGIN' '-- LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_END' $offerBridgeBody
    W ('Installed direct EUI AI-offer bridge in '+$diploTrade+'.') Green

    # Older EUI variants can contain an explicit luxury-offer suppression
    # branch. Keep the existing best-effort message-scoped compatibility patch.
    $bridgeBegin='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_BEGIN'
    $bridgeEnd='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_END'
    $fairMessage='I have a trade proposal that I believe is fair to both of us.'
    $tl=[IO.File]::ReadAllText($tradeLogic)
    $bridgeChanged=$false

    if($tl.Contains($bridgeBegin) -and $tl.Contains($bridgeEnd)){
        W 'EUI Fair Trades luxury bridge already present.' Green
    } elseif(($tl -match 'AIOfferingLux\(\)') -and $tl.Contains($fairMessage)) {
        W 'Existing message-scoped EUI luxury handling detected; leaving it unchanged.' Green
    } else {
        $simplePattern='(?m)^(?<indent>[ \t]*)(?<kw>if|elseif)[ \t]+AIOfferingLux\(\)[ \t]+then(?<trail>[ \t]*(?:--[^\r\n]*)?)$'
        $m=[regex]::Match($tl,$simplePattern)
        if($m.Success){
            $indent=$m.Groups['indent'].Value
            $kw=$m.Groups['kw'].Value
            $trail=$m.Groups['trail'].Value
            $replacement=$indent+$bridgeBegin+"`r`n"+$indent+$kw+' AIOfferingLux() and szLeaderMessage ~= "'+$fairMessage+'" then'+$trail+"`r`n"+$indent+$bridgeEnd
            $tl=[regex]::Replace($tl,$simplePattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($x) $replacement },1)
            Write-LEKUtf8NoBom $tradeLogic $tl
            $bridgeChanged=$true
            W 'Patched compatible EUI AIOfferingLux suppression branch.' Green
        } elseif($tl -notmatch 'AIOfferingLux\(\)') {
            W 'This EUI TradeLogic has no AIOfferingLux suppression branch; no luxury patch is needed.' DarkGray
        } else {
            W 'EUI uses an unfamiliar AIOfferingLux layout. Leaving that optional branch untouched.' Yellow
        }
    }

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'UI\LEKFairTrades.lua') -Destination (Join-Path $lekUI 'LEKFairTrades.lua') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'UI\LEKFairTrades.xml') -Destination (Join-Path $lekUI 'LEKFairTrades.xml') -Force

    W ''
    W 'Running Fair Trades verifier...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Fair Trades files were written, but verification failed.' }

    W ''
    W 'FAIR TRADES v1.1.5 EUI DIRECT OFFER BRIDGE INSTALLED.' Green
    if($bridgeChanged){ W 'Optional EUI luxury-offer compatibility bridge was also installed.' Green }
    W 'Candidate search/value is pre-session; visible offers enter TradeLogic through its own LeaderMessageHandler.' Green
    W 'UI.OnHumanOpenedTradeScreen and spoofed Events.AILeaderMessage are not used by the runtime.' Green
    exit 0
} catch {
    W ''
    W ('INSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
