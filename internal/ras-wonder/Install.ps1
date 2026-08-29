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
    $loadScreen=Join-LEKPath $civ 'Assets\DLC\UI_bc1\GameSetup\LoadScreen.lua'
    $startGame=Join-LEKPath $civ 'Assets\UI\FrontEnd\Multiplayer\GTAS_StartGame.lua'
    if(!(Test-LEKPath $inGame)){ throw 'Lekmod InGame.lua not found.' }
    if(!(Test-LEKPath $loadScreen)){
        W ''
        W 'EUI LoadScreen.lua not found. This hotfix only patches an existing EUI install' Yellow
        W 'and never bundles it. LEKMOD requires EUI v1.28 or earlier -- v1.29+ is not' Yellow
        W 'supported.' Yellow
        Open-LEKPrereqLink 'the official EUI download (get a v1.28 or earlier release)' 'https://forums.civfanatics.com/resources/civ5-enhanced-user-interface.24303/'
        throw 'EUI LoadScreen.lua not found.'
    }
    if(!(Test-LEKPath $startGame)){ throw 'GTAS_StartGame.lua not found. RAS MP Bridge runtime is incomplete.' }

    $igt=[IO.File]::ReadAllText($inGame)
    if(-not $igt.Contains('-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN')){
        throw 'RAS MP Bridge v0.8.8 runtime replay marker not found. This hotfix only targets the known v0.8.8 stack.'
    }
    $lst=[IO.File]::ReadAllText($loadScreen)
    if(-not $lst.Contains('-- GTAS_MP_BRIDGE_V0871_LOADSCREEN_BEGIN') -or -not $lst.Contains('BypassRASReroll')){
        throw 'RAS v0.8.7.1/v0.8.8 LoadScreen reroll logic not found.'
    }
    $sgt=[IO.File]::ReadAllText($startGame)
    if(-not $sgt.Contains('function GTAS_MP_ApplyMapPhase()')){
        throw 'GTAS_MP_ApplyMapPhase() not found in GTAS_StartGame.lua.'
    }

    $backupRoot=Join-Path $Root 'local\backups\ras-wonder'
    [void](Backup-LEKFileOnce $loadScreen $backupRoot 'LoadScreen.lua')
    [void](Backup-LEKFileOnce $startGame $backupRoot 'GTAS_StartGame.lua')

    # Remove the superseded experimental v0.8.9 InGame block if present.
    $igt=Remove-LEKMarkedBlock $igt '-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_BEGIN' '-- GTAS_MP_V089_EARLY_WONDER_GRAPHICS_END'
    Write-LEKUtf8NoBom $inGame $igt

    $runtimeBody=@'
-- v0.8.9 late-replay guard. On a reroll, LoadScreen may already have placed
-- natural wonders in the Dawn-of-Man pre-render window. The safe v0.8.8 full
-- replay must still run, but its duplicate natural-wonder removal/placement is
-- skipped for the same reroll token. Terrain/features/resources remain late.
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
        GTAS_MP_V089_DBSet("WonderGraphicsLateReplay","SKIP_DISABLE_DUPLICATE")
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
        GTAS_MP_V089_DBSet("WonderGraphicsLateReplay","SKIP_PLACE_DUPLICATE")
        return
    end
    if type(GTAS_MP_V089_BasePlaceWonders) ~= "function" then
        error("GTAS MP v0.8.9: base PlaceWonders missing")
    end
    local result=GTAS_MP_V089_BasePlaceWonders()
    MapModData.GTAS_MP_V089_WONDERS_DONE_SEED=seed
    GTAS_MP_V089_DBSet("WonderGraphicsPlacedSeed",seed)
    GTAS_MP_V089_DBSet("WonderGraphicsRuntimeHeartbeat","WONDERS_PLACED_BY_NORMAL_PHASE")
    return result
end
PlaceWonders=GTAS_MP_V089_WrappedPlaceWonders
'@
    Set-LEKMarkedBlock $startGame '-- GTAS_MP_V089_WONDER_RUNTIME_BEGIN' '-- GTAS_MP_V089_WONDER_RUNTIME_END' $runtimeBody

    $loadBody=@'
do
    local bridgeDB=nil
    pcall(function() bridgeDB=Modding.OpenUserData("GTAS_MP_BRIDGE",8) end)

    local function DBGet(db,key)
        if db == nil then return nil end
        local ok,v=pcall(function() return db.GetValue(key) end)
        if ok then return v end
        return nil
    end

    local function DBSet(key,value)
        if bridgeDB == nil then return end
        pcall(function() bridgeDB.SetValue(key,value) end)
    end

    if DBGet(bridgeDB,"BypassRASReroll") == 1 then
        local ran=false
        local function RunRerollWonderPreRender(civID)
            if ran then return end
            ran=true
            Events.SerialEventDawnOfManShow.Remove(RunRerollWonderPreRender)

            local ok,err=pcall(function()
                DBSet("WonderGraphicsHeartbeat","REROLL_PRERENDER_START")

                local seed=tonumber(DBGet(bridgeDB,"RerollBypassToken")) or 0
                math.randomseed(seed)
                math.random(); math.random(); math.random(); math.random()

                -- Minimal map module only. GTAS_InitMap loads the saved RAS map
                -- data and exposes DisableOtherWonders/PlaceWonders. We do NOT
                -- call InitMap, InitGame, InitPlayers or ApplyAdvancedSetup here.
                include("GTAS_InitMap")
                MapModData = MapModData or {}

                if tonumber(MapModData.GTAS_MP_V089_WONDERS_DONE_SEED) ~= seed then
                    DisableOtherWonders()
                    PlaceWonders()
                    MapModData.GTAS_MP_V089_WONDERS_DONE_SEED=seed
                end

                DBSet("WonderGraphicsSeed",seed)
                DBSet("WonderGraphicsMode","REROLL_DAWN_OF_MAN_WONDER_ONLY")
                DBSet("WonderGraphicsPlacedSeed",seed)
                DBSet("WonderGraphicsHeartbeat","REROLL_PRERENDER_OK")
            end)

            if not ok then
                DBSet("WonderGraphicsHeartbeat","REROLL_PRERENDER_ERROR:"..tostring(err))
                print("GTAS MP v0.8.9 reroll wonder pre-render error: "..tostring(err))
            end
        end

        Events.SerialEventDawnOfManShow.Add(RunRerollWonderPreRender)
        DBSet("WonderGraphicsHeartbeat","REROLL_PRERENDER_REGISTERED")
        print("GTAS MP v0.8.9: reroll natural-wonder pre-render phase registered")
    else
        -- Fresh/manual games already use v0.8.7.1's known-good early full map
        -- phase on this event. Do not add another map mutation path.
        DBSet("WonderGraphicsHeartbeat","NORMAL_EXISTING_EARLY_PHASE_UNCHANGED")
    end
end
'@
    Set-LEKMarkedBlock $loadScreen '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_BEGIN' '-- GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_END' $loadBody

    W ''
    W 'Running RAS v0.8.9 wonder verifier...' Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify.ps1') -CivPath $civ
    if($LASTEXITCODE -ne 0){ throw 'Wonder graphics files were written, but verification failed.' }

    W ''
    W 'RAS v0.8.9 TARGETED WONDER GRAPHICS HOTFIX INSTALLED.' Green
    W 'Fresh games keep the existing v0.8.7.1 early map phase unchanged.' Green
    W 'Rerolls place only natural wonders during Dawn-of-Man pre-render.' Green
    W 'Full v0.8.8 reroll replay remains at the safe late boundary.' Green
    exit 0
} catch {
    W ''
    W ('RAS WONDER INSTALL ERROR: '+$_.Exception.Message) Red
    if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){ W $_.InvocationInfo.PositionMessage DarkGray }
    if($_.ScriptStackTrace){ W ('STACK: '+$_.ScriptStackTrace) DarkGray }
    exit 1
}
