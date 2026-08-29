param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
$Begin='-- LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN'
$End='-- LEK_EXT_THUMB_NEXT_ACTION_V01_END'

try {
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before installing.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ throw 'Civilization V install folder not found.' }
    $target=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\WorldView\ActionInfoPanel.lua'
    if(!(Test-LEKPath $target)){ throw 'Brave New World ActionInfoPanel.lua was not found.' }
    $text=[IO.File]::ReadAllText($target)
    if(!$text.Contains('function OnEndTurnClicked()') -or !$text.Contains('Controls.EndTurnButton:RegisterCallback( Mouse.eLClick, OnEndTurnClicked );')){
        throw 'The installed ActionInfoPanel does not contain the expected native End Turn handler.'
    }
    $backupRoot=Join-Path (Split-Path $Root -Parent) 'local\backups\thumb-action'
    Backup-LEKFileOnce $target $backupRoot 'ActionInfoPanel.lua' | Out-Null
    $body=@'
local function LEKThumbNextActionInput(uiMsg, wParam)
    if uiMsg == MouseEvents.XButtonUp and wParam == 1 then
        OnEndTurnClicked()
        return true
    end
    return false
end
ContextPtr:SetInputHandler(LEKThumbNextActionInput)
'@
    Set-LEKMarkedBlock $target $Begin $End $body.Trim()
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Thumb Next Action was written, but verification failed.' }
    W 'THUMB NEXT ACTION v0.1 INSTALLED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
