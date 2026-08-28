param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }
function Write-NoBom([string]$Path,[string]$Text){ [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false))) }

$EarlyBegin='-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN'
$EarlyEnd='-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_END'
$LateBegin='-- GTAS_MP_V089_SKIP_LATE_WONDERS_BEGIN'
$LateEnd='-- GTAS_MP_V089_SKIP_LATE_WONDERS_END'

$EarlyBlock=@'
-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN
-- Reroll-only, graphics-critical subset of RAS InitMap.
-- v0.8.8 intentionally bypasses all RAS code during replacement loading and
-- later replays InitMap after SequenceGameInitComplete. That is safe for game
-- state but too late for Civ V's natural-wonder world-art construction.
-- This block restores only RAS bonus-wonder placement at the old proven early
-- InGame timing. Terrain/features/resources remain on the safe v0.8.8 path.
do
    MapModData = MapModData or {};

    if not MapModData.GTAS_MP_V089_EARLY_WONDERS_DONE then
        local bridgeDB = nil;
        local bypass = false;
        local token = nil;

        local dbok, db = pcall(function()
            return Modding.OpenUserData("GTAS_MP_BRIDGE", 8);
        end);

        if dbok and db ~= nil then
            bridgeDB = db;
            pcall(function()
                bypass = db.GetValue("BypassRASReroll") == 1;
                token = db.GetValue("RerollBypassToken");
            end);
        end

        -- Normal/manual games keep the existing v0.8.7.1 path unchanged.
        if bypass then
            if bridgeDB ~= nil then
                pcall(function()
                    bridgeDB.SetValue("EarlyWonderGraphicsHeartbeat", "EARLY_WONDER_PHASE_START");
                    bridgeDB.SetValue("EarlyWonderGraphicsToken", tostring(token or ""));
                end);
            end

            local ok, err = pcall(function()
                -- Match the bridge's deterministic reroll seed warm-up.
                local seed = tonumber(token) or 1357911;
                math.randomseed(seed);
                math.random(); math.random(); math.random(); math.random();

                include("GTAS_Constants");
                include("GTAS_Utilities");
                include("GTAS_DataManager");
                include("GTAS_PlotPlacement");
                include("GTAS_PlaceWonders");

                if type(PlaceWonders) ~= "function" then
                    error("PlaceWonders is missing");
                end

                PlaceWonders();
                MapModData.GTAS_MP_V089_EARLY_WONDERS_DONE = true;

                if bridgeDB ~= nil then
                    bridgeDB.SetValue("EarlyWonderGraphicsHeartbeat", "EARLY_WONDERS_PLACED");
                end

                print("GTAS MP v0.8.9: early RAS bonus wonders placed for world graphics");
            end);

            if not ok then
                if bridgeDB ~= nil then
                    pcall(function()
                        bridgeDB.SetValue("EarlyWonderGraphicsHeartbeat", "EARLY_WONDER_PHASE_ERROR");
                        bridgeDB.SetValue("EarlyWonderGraphicsError", tostring(err));
                    end);
                end
                print("GTAS MP v0.8.9 EARLY WONDER ERROR: " .. tostring(err));
            end
        end
    end
end
-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_END
'@

$LateBlock=@'
-- GTAS_MP_V089_SKIP_LATE_WONDERS_BEGIN
-- If the reroll-only early phase already placed RAS bonus wonders, suppress only
-- the duplicate PlaceWonders call inside the safe v0.8.8 full replay. All other
-- RAS InitMap/InitGame/InitPlayers work remains unchanged.
local v089EarlyWondersDone =
    MapModData and
    MapModData.GTAS_MP_V089_EARLY_WONDERS_DONE;

local v089SavedPlaceWonders = nil;
if v089EarlyWondersDone and type(PlaceWonders) == "function" then
    v089SavedPlaceWonders = PlaceWonders;
    PlaceWonders = function()
        print("GTAS MP v0.8.9: duplicate late PlaceWonders suppressed");
    end;
end

local v089ApplyOK, v089ApplyErr = pcall(GTAS_MP_ApplyAdvancedSetup);

if v089SavedPlaceWonders ~= nil then
    PlaceWonders = v089SavedPlaceWonders;
end

if not v089ApplyOK then
    error(v089ApplyErr);
end

if v089EarlyWondersDone and type(GTAS_MP_SetBridgeValue) == "function" then
    GTAS_MP_SetBridgeValue(
        "EarlyWonderGraphicsHeartbeat",
        "LATE_REPLAY_SKIPPED_DUPLICATE_WONDERS"
    );
end
-- GTAS_MP_V089_SKIP_LATE_WONDERS_END
'@

function Remove-MarkedBlock([string]$Text,[string]$Begin,[string]$End){
    $pattern='(?s)\r?\n?'+[regex]::Escape($Begin)+'.*?'+[regex]::Escape($End)+'\r?\n?'
    return [regex]::Replace($Text,$pattern,"`r`n",1)
}

function Patch-InGame([string]$Path,[string]$BackupName){
    $text=[IO.File]::ReadAllText($Path)
    if(!$text.Contains('-- GTAS_MP_BRIDGE_V0871_INGAME_BEGIN')){ throw "RAS v0.8.7.1 InGame marker missing: $Path" }
    $v88='-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN'
    if(!$text.Contains($v88)){ throw "RAS v0.8.8 replay marker missing: $Path" }

    [void](Backup-LEKFileOnce $Path (Join-Path $Root 'local\backups\ras_wonder') $BackupName)

    $text=Remove-MarkedBlock $text $EarlyBegin $EarlyEnd
    $text=Remove-MarkedBlock $text $LateBegin $LateEnd

    $anchor='-- GTAS_MP_BRIDGE_V0871_INGAME_BEGIN'
    $pos=$text.IndexOf($anchor,[StringComparison]::Ordinal)
    if($pos -lt 0){ throw "Early wonder insertion anchor missing: $Path" }
    $text=$text.Substring(0,$pos)+$EarlyBlock+"`r`n"+$text.Substring($pos)

    $v88pos=$text.IndexOf($v88,[StringComparison]::Ordinal)
    if($v88pos -lt 0){ throw "v0.8.8 replay block missing after early insertion: $Path" }
    $apply='            GTAS_MP_ApplyAdvancedSetup();'
    $applyPos=$text.IndexOf($apply,$v88pos,[StringComparison]::Ordinal)
    if($applyPos -lt 0){ throw "v0.8.8 replay ApplyAdvancedSetup call missing: $Path" }
    $nextApply=$text.IndexOf($apply,$applyPos+$apply.Length,[StringComparison]::Ordinal)
    if($nextApply -ge 0 -and $nextApply -lt $text.IndexOf('-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_END',$v88pos,[StringComparison]::Ordinal)){
        throw "Unexpected duplicate v0.8.8 replay ApplyAdvancedSetup call: $Path"
    }
    $indented=($LateBlock -replace '(?m)^','            ').TrimEnd()
    $text=$text.Substring(0,$applyPos)+$indented+$text.Substring($applyPos+$apply.Length)

    Write-NoBom $Path $text
}

try {
    W '============================================================' Cyan
    W ' RAS MP BRIDGE v0.8.9 - TARGETED WONDER GRAPHICS HOTFIX' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before installing.' }
    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }
    W ('Civ V: '+$civ) Green

    W 'Preflight: verifying current v0.8.8 core before hotfix...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $PSScriptRoot) 'CoreVerify.ps1') -CivPath $civ -RASMode Auto
    if($LASTEXITCODE -ne 0){ throw 'Frozen core verification failed before RAS wonder hotfix.' }

    $candidates=@(
        (Join-Path $civ 'Assets\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\Expansion\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\Expansion2\UI\InGame\InGame.lua'),
        (Join-Path $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique

    if($candidates.Count -lt 1){ throw 'No InGame.lua targets found.' }
    $n=0
    foreach($p in $candidates){
        $n++
        Patch-InGame $p ('InGame_'+$n+'.lua')
        W ('PATCHED  '+$p) Green
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'RAS wonder hotfix was written, but verification failed.' }

    W ''
    W 'RAS WONDER GRAPHICS HOTFIX v0.8.9 INSTALLED.' Green
    W 'Only bonus-wonder placement moves early on rerolls; the rest of v0.8.8 stays at the safe replay boundary.' Cyan
    exit 0
} catch {
    W ''
    W ('INSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
