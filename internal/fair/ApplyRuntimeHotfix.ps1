param([Parameter(Mandatory=$true)][string]$RuntimePath)
$ErrorActionPreference='Stop'

if(!(Test-Path -LiteralPath $RuntimePath -PathType Leaf)){
    throw "Fair Trades runtime not found: $RuntimePath"
}

$t=[IO.File]::ReadAllText($RuntimePath)
$t=$t -replace "`r`n","`n"

function Normalize-LF([string]$s){
    if($null -eq $s){ return $s }
    return ($s -replace "`r`n","`n")
}

function Replace-ExactlyOnce([string]$text,[string]$old,[string]$new,[string]$label){
    $old=Normalize-LF $old
    $new=Normalize-LF $new
    $first=$text.IndexOf($old,[StringComparison]::Ordinal)
    if($first -lt 0){ throw "Hotfix anchor not found: $label" }
    $second=$text.IndexOf($old,$first+$old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){ throw "Hotfix anchor is not unique: $label" }
    return $text.Substring(0,$first)+$new+$text.Substring($first+$old.Length)
}

# Installer always copies the clean v1.0 source immediately before this patch,
# so this transform intentionally has one known input and one deterministic output.
$t=Replace-ExactlyOnce $t 'print("LEK Fair Trades v1.0: loading")' 'print("LEK Fair Trades v1.0.3: loading")' 'loading version'
$t=Replace-ExactlyOnce $t 'ContextPtr:SetHide(true)' @'
-- LEK_FAIR_TRADES_ACTIVE_RETRY_CONTEXT_V103
-- This Context contains no controls. It must remain active so Civ V calls the
-- short SetUpdate retry handler after ActivePlayerTurnStart. A hidden Context
-- never ticked on the target MP setup, leaving v1.0.2 permanently retry-armed.
ContextPtr:SetHide(false)
'@ 'active empty retry context'
$t=Replace-ExactlyOnce $t 'local RUNTIME_VERSION = 100' 'local RUNTIME_VERSION = 103' 'runtime version'

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
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_BUSY_RETRY_ARMED")
        StateSet("OfferRetryHeartbeat", "ARMED")
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
-- LEK_FAIR_TRADES_QUEUE_RETRY_V103_BEGIN
-- Not a continuous trade scanner: active only while the turn-start message queue
-- is busy, performs no deal search per frame, and self-removes after clear/timeout.
local function RetryBusyTurnStart(fDTime)
    if not g_retryArmed then
        ContextPtr:ClearUpdate()
        return
    end

    if StateSet ~= nil and g_retrySeconds == 0 then
        StateSet("OfferRetryHeartbeat", "UPDATE_TICKED")
    end
    g_retrySeconds = g_retrySeconds + (tonumber(fDTime) or 0.016)

    if g_retrySeconds >= 10 then
        g_retryArmed = false
        ContextPtr:ClearUpdate()
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_RETRY_TIMEOUT")
        StateSet("OfferRetryHeartbeat", "TIMEOUT")
        StateSet("OfferRetrySeconds", g_retrySeconds)
        return
    end

    if Game.IsProcessingMessages == nil or not Game.IsProcessingMessages() then
        g_retryArmed = false
        ContextPtr:ClearUpdate()
        StateSet("OfferScanReason", "TURN_START_MESSAGE_QUEUE_CLEARED_RETRY")
        StateSet("OfferRetryHeartbeat", "QUEUE_CLEARED")
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
-- LEK_FAIR_TRADES_QUEUE_RETRY_V103_END
'@
$t=Replace-ExactlyOnce $t $oldEvent $newEvent 'turn-start event hook'

$t=Replace-ExactlyOnce $t 'StateSet("PerformanceModel", "ONE_TURN_SCAN_MAX_8_NATIVE_HELPERS_NO_UPDATE_LOOP")' 'StateSet("PerformanceModel", "ONE_TURN_SCAN_MAX_8_NATIVE_HELPERS_ACTIVE_BOUNDED_QUEUE_RETRY")' 'performance model state'
$t=Replace-ExactlyOnce $t 'StateSet("StartupPopupHidden", 1)' @'
StateSet("StartupPopupHidden", 1)
StateSet("RetryContext", "ACTIVE_EMPTY_CONTEXT_V103")
'@ 'retry context state'
$t=Replace-ExactlyOnce $t 'print("LEK Fair Trades v1.0: ready - native seed engine, max 8 helper calls/turn")' 'print("LEK Fair Trades v1.0.3: ready - active bounded queue retry, max 8 helper calls/turn")' 'ready version'

$utf8=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($RuntimePath,$t,$utf8)
