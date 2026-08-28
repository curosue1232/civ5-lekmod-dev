param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.0.8 EUI BRIDGE INSTALLER' Cyan
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
    $tradeLogic=Join-LEKPath $civ 'Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua'
    if(!(Test-LEKPath $inGame)){ throw 'Lekmod InGame.lua not found.' }
    if(!(Test-LEKPath $leader)){ throw 'EUI LeaderHeadRoot.lua not found.' }
    if(!(Test-LEKPath $tradeLogic)){ throw 'EUI TradeLogic.lua not found at Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua.' }

    $old=@()
    foreach($p in @($inGame,$leader,$tradeLogic)){
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

    Set-LEKMarkedBlock $inGame '-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN' '-- LEK_EXT_FAIR_TRADES_LOADER_END' 'ContextPtr:LoadNewContext("LEKFairTrades")'

    # EUI normally discards AI luxury offers. Keep that behavior for ordinary AI
    # messages, but allow the one Fair Trades offer identified by its unique message.
    $bridgeBegin='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_BEGIN'
    $bridgeEnd='-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_END'
    $tl=[IO.File]::ReadAllText($tradeLogic)
    if(!$tl.Contains($bridgeBegin)){
        $pattern='(?m)^(?<indent>[ \t]*)if[ \t]+AIOfferingLux\(\)[ \t]+then[ \t]*$'
        $m=[regex]::Match($tl,$pattern)
        if(!$m.Success){ throw 'Expected EUI AIOfferingLux suppression branch was not found. TradeLogic was not patched.' }
        $indent=$m.Groups['indent'].Value
        $replacement=$indent+$bridgeBegin+"`r`n"+$indent+'if AIOfferingLux() and szLeaderMessage ~= "I have a trade proposal that I believe is fair to both of us." then'+"`r`n"+$indent+$bridgeEnd
        $tl=[regex]::Replace($tl,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($x) $replacement },1)
        Write-LEKUtf8NoBom $tradeLogic $tl
    }

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'UI\LEKFairTrades.lua') -Destination (Join-Path $lekUI 'LEKFairTrades.lua') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'UI\LEKFairTrades.xml') -Destination (Join-Path $lekUI 'LEKFairTrades.xml') -Force

    W ''
    W 'Running Fair Trades verifier...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Fair Trades files were written, but verification failed.' }

    W ''
    W 'FAIR TRADES v1.0.8 EUI BRIDGE INSTALLED.' Green
    W 'Validated Fair Trades luxury offers bypass EUI suppression; ordinary AI luxury chatter remains suppressed.' Green
    exit 0
} catch {
    W ''
    W ('INSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
