param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
function Write-NoBom([string]$Path,[string]$Text){ [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false))) }

$EarlyBegin='-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN'
$EarlyEnd='-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_END'
$LateBegin='-- GTAS_MP_V089_SKIP_LATE_WONDERS_BEGIN'
$LateEnd='-- GTAS_MP_V089_SKIP_LATE_WONDERS_END'

function Remove-MarkedBlock([string]$Text,[string]$Begin,[string]$End){
    $pattern='(?s)\r?\n?'+[regex]::Escape($Begin)+'.*?'+[regex]::Escape($End)+'\r?\n?'
    return [regex]::Replace($Text,$pattern,"`r`n",1)
}

try {
    W '============================================================' Cyan
    W ' REMOVE RAS v0.8.9 WONDER GRAPHICS HOTFIX' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before uninstalling.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $candidates=@(
        (Join-Path $civ 'Assets\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique

    foreach($p in $candidates){
        $t=[IO.File]::ReadAllText($p)
        $t=Remove-MarkedBlock $t $EarlyBegin $EarlyEnd

        $pattern='(?s)[ \t]*'+[regex]::Escape($LateBegin)+'.*?'+[regex]::Escape($LateEnd)
        if([regex]::IsMatch($t,$pattern)){
            $t=[regex]::Replace($t,$pattern,'            GTAS_MP_ApplyAdvancedSetup();',1)
        }
        Write-NoBom $p $t
        W ('CLEANED  '+$p) Green
    }

    W 'RAS v0.8.9 wonder graphics hotfix removed; v0.8.8 replay remains.' Green
    exit 0
} catch {
    W ('UNINSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
