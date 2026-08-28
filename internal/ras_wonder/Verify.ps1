param([string]$CivPath='')
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' RAS MP BRIDGE v0.8.9 WONDER GRAPHICS VERIFY' Cyan
    W '============================================================' Cyan
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }

    $candidates=@(
        (Join-Path $civ 'Assets\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique

    $good=$true
    foreach($p in $candidates){
        $t=[IO.File]::ReadAllText($p)
        $checks=@(
            @('v0.8.8 replay still present', $t.Contains('-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN')),
            @('v0.8.7.2 bypass still present', $t.Contains('GTAS_MP_V0872_INGAME_HEARTBEAT')),
            @('early wonder begin', $t.Contains('-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN')),
            @('early wonder end', $t.Contains('-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_END')),
            @('reroll-only bypass gate', $t.Contains('bypass = db.GetValue("BypassRASReroll") == 1')),
            @('early PlaceWonders call', $t.Contains('PlaceWonders();')),
            @('early wonder done guard', $t.Contains('GTAS_MP_V089_EARLY_WONDERS_DONE')),
            @('late suppression begin', $t.Contains('-- GTAS_MP_V089_SKIP_LATE_WONDERS_BEGIN')),
            @('late suppression end', $t.Contains('-- GTAS_MP_V089_SKIP_LATE_WONDERS_END')),
            @('late full RAS replay retained', $t.Contains('local v089ApplyOK, v089ApplyErr = pcall(GTAS_MP_ApplyAdvancedSetup);')),
            @('late PlaceWonders restore', $t.Contains('PlaceWonders = v089SavedPlaceWonders;')),
            @('no full InitMap moved early', -not $t.Contains('GTAS_MP_V089_EARLY_FULL_INITMAP'))
        )
        foreach($c in $checks){
            if($c[1]){ W ('PASS  '+$c[0]+' :: '+$p) Green }
            else{ W ('FAIL  '+$c[0]+' :: '+$p) Red; $good=$false }
        }

        if(([regex]::Matches($t,[regex]::Escape('-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN'))).Count -ne 1){ W ('FAIL  duplicate/missing early block :: '+$p) Red; $good=$false }
        if(([regex]::Matches($t,[regex]::Escape('-- GTAS_MP_V089_SKIP_LATE_WONDERS_BEGIN'))).Count -ne 1){ W ('FAIL  duplicate/missing late block :: '+$p) Red; $good=$false }
    }

    W ''
    if($good){ W 'RAS WONDER GRAPHICS v0.8.9 VERIFIED.' Green; exit 0 }
    W 'VERIFY FOUND A PROBLEM.' Red; exit 1
} catch {
    W ('VERIFY ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
