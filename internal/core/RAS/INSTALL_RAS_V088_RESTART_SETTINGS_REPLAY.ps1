param([string]$CivPath="")
$ErrorActionPreference = "Stop"

$Suffix = ".lek_ras_v088_replay_backup"

function Find-CivV {
    param([string]$Requested)

    $candidates = @(
        $Requested,
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Sid Meier's Civilization V",
        "$env:ProgramFiles\Steam\steamapps\common\Sid Meier's Civilization V",
        "C:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "D:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "F:\SteamLibrary\steamapps\common\Sid Meier's Civilization V"
    )

    foreach($c in ($candidates | Where-Object {$_} | Select-Object -Unique)){
        if(Test-Path (Join-Path $c "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua")){
            return $c
        }
    }

    return $null
}

function Write-NoBom {
    param([string]$Path,[string]$Text)

    [IO.File]::WriteAllText(
        $Path,
        $Text,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Backup-Once {
    param([string]$Path)

    if(!(Test-Path ($Path + $Suffix))){
        Copy-Item $Path ($Path + $Suffix) -Force
    }
}

$civ = Find-CivV $CivPath

if(!$civ){
    $manual = Read-Host "Paste Civilization V install folder"

    if($manual){
        $civ = Find-CivV $manual.Trim('"')
    }
}

if(!$civ){
    throw "Civilization V not found."
}

$mpSetup =
    Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\GameSetup\MPGameSetupScreen.lua"

$euiLoad =
    Join-Path $civ "Assets\DLC\UI_bc1\GameSetup\LoadScreen.lua"

$staging =
    Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua"

$inGameCandidates = @(
    (Join-Path $civ "Assets\UI\InGame\InGame.lua"),
    (Join-Path $civ "Assets\DLC\Expansion\UI\InGame\InGame.lua"),
    (Join-Path $civ "Assets\DLC\Expansion2\UI\InGame\InGame.lua"),
    (Join-Path $civ "Assets\DLC\LEKMOD_V30.7\UI\InGame.lua")
) |
    Where-Object { Test-Path $_ } |
    Select-Object -Unique

if(!(Test-Path $mpSetup)){
    throw "MPGameSetupScreen.lua missing."
}

if(
    !([IO.File]::ReadAllText($mpSetup).Contains(
        "GTAS_MP_V0872_STICKY_REROLL_CONTEXT"
    ))
){
    throw "RAS v0.8.7.2 Sticky Reroll Bypass hotfix not found."
}

if(
    !(Test-Path $euiLoad) -or
    !([IO.File]::ReadAllText($euiLoad).Contains(
        "GTAS_MP_V0872_LOADSCREEN_HEARTBEAT"
    ))
){
    throw "RAS v0.8.7.2 LoadScreen bypass instrumentation not found."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RAS MP BRIDGE v0.8.8" -ForegroundColor Cyan
Write-Host " RESTART SETTINGS REPLAY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$block = @'

-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN
--
-- v0.8.7.2 proved the replacement can reach SequenceGameInitComplete safely
-- while RAS is completely bypassed during rehost + loading.
--
-- This SECOND SequenceGameInitComplete handler is registered after the
-- v0.8.7.2 bypass handler.  Therefore it runs only after the replacement has
-- crossed the proven-safe engine initialization boundary.
--
-- At that point it replays the saved RAS runtime layer:
--   InitMap
--   InitGame
--   InitPlayers
--
-- PreGame / lobby restoration remains owned by Reroll/Rehost v0.21.x.
do
    local replayAttempted = false;

    local function openDB(name,version)
        local ok,db = pcall(function()
            return Modding.OpenUserData(
                name,
                version
            );
        end);

        if ok then
            return db;
        end

        return nil;
    end

    local function dbGet(db,key)
        if db == nil then
            return nil;
        end

        local ok,value = pcall(function()
            return db.GetValue(key);
        end);

        if ok then
            return value;
        end

        return nil;
    end

    local function dbSet(db,key,value)
        if db == nil then
            return false;
        end

        return pcall(function()
            db.SetValue(
                key,
                value
            );
        end);
    end

    local function ReplayRASAfterSafeLoad()
        if replayAttempted then
            return;
        end

        local bridgeDB =
            openDB(
                "GTAS_MP_BRIDGE",
                8
            );

        if bridgeDB == nil then
            return;
        end

        -- This value is written by the v0.8.7.2 handler earlier in the SAME
        -- SequenceGameInitComplete event.  It proves the replacement crossed
        -- loading with RAS bypassed.
        if dbGet(
            bridgeDB,
            "StickyRerollInGame"
        ) ~= 1 then
            return;
        end

        local rerollDB =
            openDB(
                "LEK_MP_REROLL_REHOST",
                21
            );

        local token =
            dbGet(
                bridgeDB,
                "LastCoreOwnedRerollToken"
            );

        if token == nil and rerollDB ~= nil then
            token =
                dbGet(
                    rerollDB,
                    "JoinToken"
                );
        end

        if token == nil then
            dbSet(
                bridgeDB,
                "RerollRuntimeReplayHeartbeat",
                "NO_REROLL_TOKEN"
            );

            return;
        end

        local doneToken =
            dbGet(
                bridgeDB,
                "RerollRuntimeReplayDoneToken"
            );

        if tostring(doneToken) == tostring(token) then
            replayAttempted = true;
            return;
        end

        replayAttempted = true;

        dbSet(
            bridgeDB,
            "RerollRuntimeReplayToken",
            tostring(token)
        );

        dbSet(
            bridgeDB,
            "RerollRuntimeReplayHeartbeat",
            "RUNTIME_RAS_REPLAY_START"
        );

        print(
            "GTAS MP v0.8.8: safe replacement loaded; replaying saved RAS settings token=" ..
            tostring(token)
        );

        local ok,err = pcall(function()
            include(
                "GTAS_MP_DB_Bootstrap"
            );

            include(
                "GTAS_MP_Bridge"
            );

            local dbok,dberr =
                GTAS_MP_BootstrapDatabase();

            if not dbok then
                error(
                    dberr
                );
            end

            -- Every human receives the same v0.21 reroll token, so use it as
            -- the deterministic RAS runtime seed on every machine.
            local seed =
                tonumber(token);

            if seed == nil then
                seed =
                    GTAS_MP_GetSeed();
            end

            GTAS_MP_SetBridgeValue(
                "Seed",
                seed
            );

            -- Loading is already over, so the dangerous early path stays off.
            GTAS_MP_SetBridgeValue(
                "SkipEarlyMapOnce",
                1
            );

            -- We are NOW at the safe replay boundary.
            GTAS_MP_SetBridgeValue(
                "SkipRuntimeRASOnce",
                0
            );

            GTAS_MP_SetBridgeValue(
                "BypassRASReroll",
                0
            );

            include(
                "GTAS_StartGame"
            );

            if (
                type(
                    GTAS_MP_ApplyAdvancedSetup
                ) ~=
                "function"
            ) then
                error(
                    "GTAS_MP_ApplyAdvancedSetup is missing"
                );
            end

            GTAS_MP_ApplyAdvancedSetup();
        end);

        if ok then
            dbSet(
                bridgeDB,
                "RerollRuntimeReplayDoneToken",
                tostring(token)
            );

            dbSet(
                bridgeDB,
                "RerollRuntimeReplayHeartbeat",
                "RUNTIME_RAS_REPLAY_OK"
            );

            dbSet(
                bridgeDB,
                "StickyRerollInGame",
                0
            );

            dbSet(
                bridgeDB,
                "StickyRerollContext",
                0
            );

            if rerollDB ~= nil then
                dbSet(
                    rerollDB,
                    "RASReplayHeartbeat",
                    "RUNTIME_RAS_REPLAY_OK"
                );

                dbSet(
                    rerollDB,
                    "RASReplayToken",
                    tostring(token)
                );
            end

            print(
                "GTAS MP v0.8.8: saved RAS restart settings replay COMPLETE"
            );
        else
            dbSet(
                bridgeDB,
                "RerollRuntimeReplayHeartbeat",
                "RUNTIME_RAS_REPLAY_ERROR:" ..
                tostring(err)
            );

            if rerollDB ~= nil then
                dbSet(
                    rerollDB,
                    "RASReplayHeartbeat",
                    "RUNTIME_RAS_REPLAY_ERROR"
                );
            end

            print(
                "GTAS MP v0.8.8 RUNTIME REPLAY ERROR: " ..
                tostring(err)
            );
        end
    end

    Events.SequenceGameInitComplete.Add(
        ReplayRASAfterSafeLoad
    );

    print(
        "GTAS MP v0.8.8: post-safe-load RAS replay handler registered"
    );
end
-- GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_END
'@

$patched = 0

foreach($p in $inGameCandidates){
    $t =
        [IO.File]::ReadAllText($p)

    if(
        $t.Contains(
            "GTAS_MP_V0872_INGAME_HEARTBEAT"
        )
    ){
        if(
            !$t.Contains(
                "GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN"
            )
        ){
            Backup-Once $p

            $t +=
                "`r`n" +
                $block

            Write-NoBom $p $t
        }

        $patched++
    }
}

if($patched -lt 1){
    throw "Could not find the v0.8.7.2 InGame safe-load handler."
}

Write-Host "PASS  found $patched active InGame RAS hook file(s)" -ForegroundColor Green

$good = $true

foreach($p in $inGameCandidates){
    $t =
        [IO.File]::ReadAllText($p)

    if(
        $t.Contains(
            "GTAS_MP_V0872_INGAME_HEARTBEAT"
        )
    ){
        if(
            $t.Contains(
                "GTAS_MP_BRIDGE_V088_REROLL_RUNTIME_REPLAY_BEGIN"
            ) -and
            $t.Contains(
                "RUNTIME_RAS_REPLAY_OK"
            ) -and
            $t.Contains(
                "GTAS_MP_ApplyAdvancedSetup();"
            )
        ){
            Write-Host "PASS  restart RAS replay: $p" -ForegroundColor Green
        }
        else {
            Write-Host "FAIL  replay patch incomplete: $p" -ForegroundColor Red
            $good = $false
        }
    }
}

if(
    (Test-Path $staging) -and
    ([IO.File]::ReadAllText($staging).Contains(
        "LEK_REROLL_V0212_PRELAUNCH_GUARD_BEGIN"
    ))
){
    Write-Host "PASS  Reroll v0.21.2 launch guard retained" -ForegroundColor Green
}
else {
    Write-Host "WARN  v0.21.2 launch guard marker not detected" -ForegroundColor Yellow
}

if(!$good){
    throw "v0.8.8 RAS restart replay installation incomplete."
}

Write-Host ""
Write-Host "RAS MP BRIDGE v0.8.8 RESTART SETTINGS REPLAY INSTALLED." -ForegroundColor Green
