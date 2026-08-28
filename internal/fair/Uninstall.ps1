param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' LEK FAIR TRADES - CLEAN EXTENSION UNINSTALL' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before uninstalling.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }
    $lekUI=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI'
    $inGame=Join-LEKPath $lekUI 'InGame.lua'
    if(Test-LEKPath $inGame){
        $t=[IO.File]::ReadAllText($inGame)
        $t=Remove-LEKMarkedBlock $t '-- LEK_EXT_FAIR_TRADES_LOADER_BEGIN' '-- LEK_EXT_FAIR_TRADES_LOADER_END'
        Write-LEKUtf8NoBom $inGame $t
    }
    foreach($name in @('LEKFairTrades.lua','LEKFairTrades.xml')){
        $p=Join-LEKPath $lekUI $name
        if(Test-LEKPath $p){ Remove-Item -LiteralPath $p -Force }
    }

    # Remove the direct AI-offer bridge Fair Trades owns in EUI diplotrade.
    $diploTrade=Join-LEKPath $civ 'Assets\DLC\UI_bc1\bugfixes\diplotrade.lua'
    if(Test-LEKPath $diploTrade){
        $dt=[IO.File]::ReadAllText($diploTrade)
        if($dt.Contains('-- LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_BEGIN')){
            $dt=Remove-LEKMarkedBlock $dt '-- LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_BEGIN' '-- LEK_EXT_FAIR_TRADES_AI_OFFER_BRIDGE_END'
            Write-LEKUtf8NoBom $diploTrade $dt
        }
    }

    # Restore only the optional EUI luxury conditional Fair Trades owns.
    $tradeLogic=Join-LEKPath $civ 'Assets\DLC\UI_bc1\LeaderHead\TradeLogic.lua'
    if(Test-LEKPath $tradeLogic){
        $tl=[IO.File]::ReadAllText($tradeLogic)
        if($tl.Contains('-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_BEGIN')){
            $pattern='(?ms)^(?<indent>[ \t]*)-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_BEGIN\r?\n(?<line>.*?)\r?\n[ \t]*-- LEK_EXT_FAIR_TRADES_EUI_LUX_BRIDGE_END[ \t]*$'
            $m=[regex]::Match($tl,$pattern)
            if($m.Success){
                $indent=$m.Groups['indent'].Value
                $line=$m.Groups['line'].Value
                $line=$line -replace ' and szLeaderMessage ~= "I have a trade proposal that I believe is fair to both of us\."',''
                $tl=[regex]::Replace($tl,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($x) $indent+$line.TrimStart() },1)
                Write-LEKUtf8NoBom $tradeLogic $tl
            }
        }
    }

    $leader=Get-LEKLeaderRoot $civ
    if(Test-LEKPath $leader){
        $lt=[IO.File]::ReadAllText($leader)
        if($lt.Contains('-- LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_BEGIN')){
            $lt=Remove-LEKMarkedBlock $lt '-- LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_BEGIN' '-- LEK_EXT_FAIR_TRADES_NATIVE_BRIDGE_END'
            Write-LEKUtf8NoBom $leader $lt
        }
    }
    W ''
    W 'FAIR TRADES EXTENSION REMOVED.' Green
    W 'Frozen core stack was not uninstalled or restored from backups.' Green
    exit 0
} catch {
    W ('UNINSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
