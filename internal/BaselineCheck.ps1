param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'LekTools.ps1')

function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK STABLE DEVELOPMENT BASELINE CHECK v1.2' Cyan
    W '============================================================' Cyan
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }
    W ('Civ V: '+$civ) Green
    W ''
    W '1) Verifying frozen LEK Core v1.3...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'CoreVerify.ps1') -CivPath $civ -RASMode Auto
    if($LASTEXITCODE -ne 0){ throw 'Core v1.3 verification failed.' }

    W ''
    W '2) Checking that old Fair AI Trades experiments are absent...' Cyan
    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    $leader=Get-LEKLeaderRoot $civ
    if(!(Test-LEKPath $inGame)){ throw 'Lekmod InGame.lua not found.' }
    if(!(Test-LEKPath $leader)){ throw 'EUI LeaderHeadRoot.lua not found.' }

    $remnants=@()
    foreach($p in @($inGame,$leader)){
        $txt=[IO.File]::ReadAllText($p)
        if($txt -match 'LEK_MP_FAIR_AI_TRADES_'){ $remnants += ('old marker in '+$p) }
    }
    try {
        foreach($f in @(Get-ChildItem -LiteralPath $lekUI -File -ErrorAction SilentlyContinue)){
            if($f.Name -match '^LEKMPFairTrades.*\.(lua|xml)$'){ $remnants += ('old runtime file '+$f.FullName) }
        }
    } catch {}

    if($remnants.Count -gt 0){
        foreach($r in $remnants){ W ('FOUND  '+$r) Yellow }
        throw 'Old Fair AI Trades remnants are still present. Run the cleanup tool before establishing the baseline.'
    }
    W 'PASS  no known old Fair AI Trades markers/runtime files' Green

    W ''
    W '3) Recording the two extension touchpoints...' Cyan
    W ('InGame.lua SHA256:       '+(Get-LEKSha256 $inGame)) Gray
    W ('LeaderHeadRoot SHA256:   '+(Get-LEKSha256 $leader)) Gray
    W ''
    W 'BASELINE READY FOR CLEAN EXTENSIONS.' Green
    W 'Core v1.3 remains the frozen foundation.' Green
    exit 0
} catch {
    W ''
    W ('BASELINE ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
