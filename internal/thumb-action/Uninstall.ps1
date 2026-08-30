param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
try {
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before uninstalling.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ throw 'Civilization V install folder not found.' }
    $target=Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\WorldView\ActionInfoPanel.lua'
    if(Test-LEKPath $target){
        $t=[IO.File]::ReadAllText($target)
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_THUMB_NEXT_ACTION_V01_BEGIN' '-- LEK_EXT_THUMB_NEXT_ACTION_V01_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V02_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V02_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V03_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V03_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V04_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V04_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V05_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V05_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V06_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V06_END'
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_NEXT_ACTION_V07_BEGIN' '-- LEK_EXT_SPACE_NEXT_ACTION_V07_END'
        Write-LEKUtf8NoBom $target $t
    }
    $tradeTarget=Join-LEKPath $civ 'Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua'
    if(Test-LEKPath $tradeTarget){
        $t=[IO.File]::ReadAllText($tradeTarget)
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_BEGIN' '-- LEK_EXT_SPACE_ACCEPT_TRADE_V03_END'
        Write-LEKUtf8NoBom $tradeTarget $t
    }
    $confirmPaths=@(
        (Join-LEKPath $civ 'Assets\DLC\UI_bc1\Improvements\ConfirmCommandPopup.lua'),
        (Join-LEKPath $civ 'Assets\UI\InGame\PopupsGeneric\ConfirmCommandPopup.lua')
    )
    foreach($confirmPath in $confirmPaths){
        if(Test-LEKPath $confirmPath){
            $t=[IO.File]::ReadAllText($confirmPath)
            $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_CONFIRM_COMMAND_V01_BEGIN' '-- LEK_EXT_SPACE_CONFIRM_COMMAND_V01_END'
            Write-LEKUtf8NoBom $confirmPath $t
        }
    }
    $menuXmls=@(
        (Join-LEKPath $civ 'Assets\UI\InGame\Menus\GameMenu.xml'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion\UI\InGame\Menus\GameMenu.xml'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\Menus\GameMenu.xml')
    )
    foreach($menuXml in $menuXmls){
        if(Test-LEKPath $menuXml){
            $t=[IO.File]::ReadAllText($menuXml)
            $t=Remove-LEKMarkedBlock $t '<!-- LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_BEGIN -->' '<!-- LEK_EXT_SPACE_AUTOMATE_BUTTON_V01_END -->'
            Write-LEKUtf8NoBom $menuXml $t
        }
    }
    $menuLua=Join-LEKPath $civ 'Assets\UI\InGame\Menus\GameMenu.lua'
    if(Test-LEKPath $menuLua){
        $t=[IO.File]::ReadAllText($menuLua)
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_AUTOMATE_MENU_V01_BEGIN' '-- LEK_EXT_SPACE_AUTOMATE_MENU_V01_END'
        Write-LEKUtf8NoBom $menuLua $t
    }
    $inGames=@(
        (Join-LEKPath $civ 'Assets\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'),
        (Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua')
    )
    foreach($inGame in $inGames){
        if(Test-LEKPath $inGame){
            $t=[IO.File]::ReadAllText($inGame)
            $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_SPACE_AUTOMATE_DRIVER_V02_BEGIN' '-- LEK_EXT_SPACE_AUTOMATE_DRIVER_V02_END'
            Write-LEKUtf8NoBom $inGame $t
        }
    }
    W 'SPACE/THUMB NEXT ACTION REMOVED.' Green
    exit 0
} catch { W ('ERROR: '+$_.Exception.Message) Red; exit 1 }
