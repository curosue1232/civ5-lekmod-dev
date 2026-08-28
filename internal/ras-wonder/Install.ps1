param([string]$CivPath='')
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'LekTools.ps1')
function W([string]$s,[ConsoleColor]$c=[ConsoleColor]::Gray){ Write-Host $s -ForegroundColor $c }

try {
    W '============================================================' Cyan
    W ' RAS MP BRIDGE v0.8.9 - TARGETED WONDER GRAPHICS HOTFIX' Cyan
    W '============================================================' Cyan
    if(Test-LEKCivRunning){ throw 'Civilization V appears to be running. Close it before installing.' }

    $civ=Find-LEKCivV $CivPath
    if(!$civ){ $m=Read-Host 'Paste Civilization V install folder'; if($m){$civ=Find-LEKCivV $m} }
    if(!$civ){ throw 'Civilization V was not found.' }
    W ('Civ V: '+$civ) Green

    W ''
    W 'Preflight: verifying frozen Core v1.3 / RAS v0.8.8...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $PSScriptRoot) 'CoreVerify.ps1') -CivPath $civ -RASMode Auto
    if($LASTEXITCODE -ne 0){ throw 'Frozen LEK Core v1.3 verification failed. Wonder hotfix was not installed.' }

    $inGame=Join-LEKPath $civ 'Assets\DLC\LEKMOD_V30.7\UI\InGame.lua'
    $startGame=Join-LEKPath $civ 'Assets\UI\FrontEnd\Multiplayer\GTAS_StartGame.lua'
    if(!(Test-LEKPath $inGame)){ throw 'Lekmod InGame.lua not found.' }
    if(!(Test-LEKPath $startGame)){ throw 'GTAS_StartGame.lua not found. RAS MP Bridge runtime is incomplete.' }

    $igt=[IO.File]::ReadAllText($inGame)
    if(-not $igt.Contains('-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN')){
        throw 'RAS MP Bridge v0.8.8 runtime replay marker not found. This hotfix only targets the known v0.8.8 stack.'
    }
    $sgt=[IO.File]::ReadAllText($startGame)
    if(-not $sgt.Contains('function GTAS_MP_ApplyMapPhase()')){
        throw 'GTAS_MP_ApplyMapPhase() not found in GTAS_StartGame.lua.'
    }

    $backupRoot=Join-Path $Root 'local\backups\ras-wonder'
    [void](Backup-LEKFileOnce $inGame $backupRoot 'InGame.lua')
    [void](Backup-LEKFileOnce $startGame $backupRoot 'GTAS_StartGame.lua')

    $runtimeBody=@'
-- Runtime-only wrapper: normal launches use the proven early full map phase.
-- Reroll replacements keep terrain/features/resources at the safe late boundary,
-- but place ONLY natural wonders early enough for Civ V to construct their 3D art.
MapModData = MapModData or {}

if type(GTAS_MP_V089_BasePlaceWonders) ~= "function"
    or PlaceWonders ~= GTAS_MP_V089_WrappedPlaceWonders then
    GTAS_MP_V089_BasePlaceWonders = PlaceWonders
end
if type(GTAS_MP_V089_BaseDisableOtherWonders) ~= "function"
    or DisableOtherWonders ~= GTAS_MP_V089_WrappedDisableOtherWonders then
    GTAS_MP_V089_BaseDisableOtherWonders = DisableOtherWonders
end

local function GTAS_MP_V089_CurrentSeed()
    return tonumber(GTAS_MP_GetSeed()) or 0
end

local function GTAS_MP_V089_DBSet(key,value)
    pcall(function()
        local db=Modding.OpenUserData("GTAS_MP_BRIDGE",8)
        db.SetValue(key,value)
    end)
end

function GTAS_MP_V089_WrappedDisableOtherWonders()
    local seed=GTAS_MP_V089_CurrentSeed()
    if tonumber(MapModData.GTAS_MP_V089_WONDERS_DONE_SEED) == seed then
        print("GTAS MP v0.8.9: skipping duplicate DisableOtherWonders seed="..tostring(seed))
        return
    end
    if type(GTAS_MP_V089_BaseDisableOtherWonders) ~= "function" then
        error("GTAS MP v0.8.9: base DisableOtherWonders missing")
    end
    return GTAS_MP_V089_BaseDisableOtherWonders()
end
DisableOtherWonders=GTAS_MP_V089_WrappedDisableOtherWonders

function GTAS_MP_V089_WrappedPlaceWonders()
    local seed=GTAS_MP_V089_CurrentSeed()
    if tonumber(MapModData.GTAS_MP_V089_WONDERS_DONE_SEED) == seed then
        print("GTAS MP v0.8.9: skipping duplicate PlaceWonders seed="..tostring(seed))
        return
    end
    if type(GTAS_MP_V089_BasePlaceWonders) ~= "function" then
        error("GTAS MP v0.8.9: base PlaceWonders missing")
    end
    local result=GTAS_MP_V089_BasePlaceWonders()
    MapModData.GTAS_MP_V089_WONDERS_DONE_SEED=seed
    GTAS_MP_V089_DBSet("WonderGraphicsPlacedSeed",seed)
    GTAS_MP_V089_DBSet("WonderGraphicsRuntimeHeartbeat","WONDERS_PLACED")
    return result
end
PlaceWonders=GTAS_MP_V089_WrappedPlaceWonders

function GTAS_MP_ApplyWonderGraphicsPhase()
    if not GTAS_MP_IsEnabled() then return true end
    local seed=GTAS_MP_V089_CurrentSeed()
    if tonumber(MapModData.GTAS_MP_V089_WONDERS_DONE_SEED) == seed then
        GTAS_MP_V089_DBSet("WonderGraphicsRuntimeHeartbeat","ALREADY_DONE")
        return true
    end

    GTAS_MP_V089_DBSet("WonderGraphicsRuntimeHeartbeat","WONDER_ONLY_START")
    GTAS_MP_SeedMathRandom(seed)

    -- Preserve RAS remove/disable-wonders semantics before placing bonus wonders.
    DisableOtherWonders()
    PlaceWonders()

    GTAS_MP_V089_DBSet("WonderGraphicsRuntimeHeartbeat","WONDER_ONLY_OK")
    return true
end
'@

    Set-LEKMarkedBlock $startGame '-- GTAS_MP_V089_WONDER_RUNTIME_BEGIN' '-- GTAS_MP_V089_WONDER_RUNTIME_END' $runtimeBody

    $inGameBody=@'
do
    local function V089Set(key,value)
        pcall(function()
            local db=Modding.OpenUserData("GTAS_MP_BRIDGE",8)
            db.SetValue(key,value)
        end)
    end

    local ok,err=pcall(function()
        include("GTAS_MP_DB_Bootstrap")
        include("GTAS_MP_Bridge")
        if not GTAS_MP_IsEnabled() then
            V089Set("WonderGraphicsHeartbeat","RAS_DISABLED")
            return
        end

        local dbok,dberr=GTAS_MP_BootstrapDatabase()
        if not dbok then error(dberr) end
        include("GTAS_StartGame")

        local seed=tonumber(GTAS_MP_GetSeed()) or 0
        V089Set("WonderGraphicsSeed",seed)
        V089Set("WonderGraphicsHeartbeat","EARLY_PHASE_START")

        if GTAS_MP_GetBridgeValue("SkipEarlyMapOnce") == 1 then
            -- Reroll/rehost: keep the crash-sensitive full map replay late, but
            -- place natural wonders now so their world art is constructed.
            V089Set("WonderGraphicsMode","REROLL_WONDER_ONLY")
            if type(GTAS_MP_ApplyWonderGraphicsPhase) ~= "function" then
                error("GTAS_MP_ApplyWonderGraphicsPhase missing")
            end
            GTAS_MP_ApplyWonderGraphicsPhase()
        else
            -- Fresh/manual launch: restore the v0.8.4 timing that was known to
            -- render bonus natural wonders correctly. Existing seed guards make
            -- the later DawnOfMan map callback a no-op.
            V089Set("WonderGraphicsMode","NORMAL_EARLY_FULL_MAP")
            if type(GTAS_MP_ApplyMapPhase) ~= "function" then
                error("GTAS_MP_ApplyMapPhase missing")
            end
            GTAS_MP_ApplyMapPhase()
        end

        V089Set("WonderGraphicsHeartbeat","EARLY_PHASE_OK")
    end)

    if not ok then
        V089Set("WonderGraphicsHeartbeat","EARLY_PHASE_ERROR:"..tostring(err))
        print("GTAS MP v0.8.9 wonder graphics error: "..tostring(err))
    end
end
'@

    Set-LEKMarkedBlock $inGame '-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN' '-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_END' $inGameBody

    W ''
    W 'Running RAS v0.8.9 wonder verifier...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Wonder graphics files were written, but verification failed.' }

    W ''
    W 'RAS v0.8.9 TARGETED WONDER GRAPHICS HOTFIX INSTALLED.' Green
    W 'Fresh games: full RAS map phase is restored to early graphics-safe timing.' Green
    W 'Rerolls: only natural-wonder placement moves early; full RAS replay remains late.' Green
    exit 0
} catch {
    W ''
    W ('RAS WONDER INSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
