param([Parameter(Mandatory=$true)][string]$RuntimePath)
$ErrorActionPreference='Stop'

if(!(Test-Path -LiteralPath $RuntimePath -PathType Leaf)){
    throw "Fair Trades runtime not found: $RuntimePath"
}

$t=[IO.File]::ReadAllText($RuntimePath)
$t=$t -replace "`r`n","`n"

if($t.Contains('-- LEK_FAIR_TRADES_QUEUE_RETRY_V102_BEGIN')){
    exit 0
}

function Replace-ExactlyOnce([string]$text,[string]$old,[string]$new,[string]$label){
    $first=$text.IndexOf($old,[StringComparison]::Ordinal)
    if($first -lt 0){ throw "Hotfix anchor not found: $label" }
    $second=$text.IndexOf($old,$first+$old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){ throw "Hotfix anchor is not unique: $label" }
    return $text.Substring(0,$first)+$new+$text.Substring($first+$old.Length)
}

$t=Replace-ExactlyOnce $t 'print("LEK Fair Trades v1.0: loading")' 'print("LEK Fair Trades v1.0.2: loading")' 'loading version'
$t=Replace-ExactlyOnce $t 'local RUNTIME_VERSION = 100' 'local RUNTIME_VERSION = 102' 'runtime version'

$oldVars=@'
local g_pendingOffer = nil
local g_nativeCalls = 0
'@
$newVars=@'
local g_pendingOffer = nil
local g_nativeCalls = 0
local g_retryArmed = false
local g_retrySeconds = 0
'@
$t=Replace-ExactlyOnce $t $oldVars $newVars 'retry state variables'

$oldBusy=@'
    if Game.IsProcessingMessages ~= nil and Game.IsProcessingMessages() then
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_BUSY")
        return
    end
'@
$newBusy=@'
    if Game.IsProcessingMessages ~= nil and Game.IsProcessingMessages() then
        -- ActivePlayerTurnStart fires while Civ V is still draining its turn-start
        -- message queue in network games. v1.0 returned here permanently, so no AI
        -- was ever evaluated. Arm a short, bounded UI retry instead.
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_BUSY_RETRY_ARMED")
        g_retryArmed = true
        g_retrySeconds = 0
        return
    end
'@
$t=Replace-ExactlyOnce $t $oldBusy $newBusy 'turn-start busy guard'

$oldEvent=@'
if Events.ActivePlayerTurnStart ~= nil then
    Events.ActivePlayerTurnStart.Add(ScanForOffer)
end
'@
$newEvent=@'
-- LEK_FAIR_TRADES_QUEUE_RETRY_V102_BEGIN
-- This is not a continuous trade scanner. It exists only while the turn-start
-- network/message queue is busy, does no deal work per frame, and self-removes
-- as soon as the queue clears (or after a hard 10-second timeout).
local function RetryBusyTurnStart(fDTime)
    if not g_retryArmed then
        ContextPtr:ClearUpdate()
        return
    end

    g_retrySeconds = g_retrySeconds + (tonumber(fDTime) or 0.016)
    if g_retrySeconds >= 10 then
        g_retryArmed = false
        ContextPtr:ClearUpdate()
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_RETRY_TIMEOUT")
        StateSet("OfferRetrySeconds", g_retrySeconds)
        return
    end

    if Game.IsProcessingMessages == nil or not Game.IsProcessingMessages() then
        g_retryArmed = false
        ContextPtr:ClearUpdate()
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_CLEARED_RETRY")
        StateSet("OfferRetrySeconds", g_retrySeconds)
        ScanForOffer()
    end
end

local function OnTurnStart()
    g_retryArmed = false
    g_retrySeconds = 0
    ScanForOffer()
    if g_retryArmed then
        ContextPtr:SetUpdate(RetryBusyTurnStart)
    else
        ContextPtr:ClearUpdate()
    end
end

if Events.ActivePlayerTurnStart ~= nil then
    Events.ActivePlayerTurnStart.Add(OnTurnStart)
end
-- LEK_FAIR_TRADES_QUEUE_RETRY_V102_END
'@
$t=Replace-ExactlyOnce $t $oldEvent $newEvent 'turn-start event hook'

$t=Replace-ExactlyOnce $t 'StateSet("PerformanceModel", "ONE_TURN_SCAN_MAX_8_NATIVE_HELPERS_NO_UPDATE_LOOP")' 'StateSet("PerformanceModel", "ONE_TURN_SCAN_MAX_8_NATIVE_HELPERS_BOUNDED_QUEUE_RETRY")' 'performance model state'
$t=Replace-ExactlyOnce $t 'print("LEK Fair Trades v1.0: ready - native seed engine, max 8 helper calls/turn")' 'print("LEK Fair Trades v1.0.2: ready - native seed engine, bounded queue retry, max 8 helper calls/turn")' 'ready version'

$utf8=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($RuntimePath,$t,$utf8)
