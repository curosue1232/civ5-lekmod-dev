param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES v1.0.3 - CLEAN EXTENSION INSTALLER' Cyan
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
    if(!(Test-LEKPath $inGame)){ throw 'Lekmod InGame.lua not found.' }
    if(!(Test-LEKPath $leader)){ throw 'EUI LeaderHeadRoot.lua not found.' }

    $old=@()
    foreach($p in @($inGame,$leader)){
        $t=[IO.File]::ReadAllText($p)
        if($t -match 'LEK_MP_FAIR_AI_TRADES_'){ $old += ('old marker in '+$p) }
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

    $begin='-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN'
    $end='-- LEK_EXT_FAIR_TRADES_LOADER_END'
    Set-LEKMarkedBlock $inGame $begin $end 'ContextPtr:LoadNewContext("LEKFairTrades")'

    $installedLua=Join-Path $lekUI 'LEKFairTrades.lua'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'UI\LEKFairTrades.lua') -Destination $installedLua -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'UI\LEKFairTrades.xml') -Destination (Join-Path $lekUI 'LEKFairTrades.xml') -Force

    # v1.0.3 keeps the empty Fair Trades context active so the short bounded
    # turn-start queue retry actually receives update ticks. It contains no UI
    # controls and therefore creates no visible popup/window.
    $hotfix=Join-Path $PSScriptRoot 'ApplyRuntimeHotfix.ps1'
    if(!(Test-Path -LiteralPath $hotfix -PathType Leaf)){ throw 'Fair Trades v1.0.3 runtime hotfix script is missing.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hotfix -RuntimePath $installedLua
    if($LASTEXITCODE -ne 0){ throw 'Fair Trades v1.0.3 runtime hotfix failed.' }

    W ''
    W 'Running Fair Trades verifier...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Fair Trades files were written, but verification failed.' }

    W ''
    W 'FAIR TRADES v1.0.3 INSTALLED.' Green
    W 'Active empty context + bounded turn-start queue retry are enabled.' Green
    W 'No EUI LeaderHeadRoot.lua patch was required.' Green
    exit 0
} catch {
    W ''
    W ('INSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
