param([string]$CivPath="")
$ErrorActionPreference="Stop"

function Find-CivV {
    param([string]$Requested)

    $candidates=@(
        $Requested,
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Sid Meier's Civilization V",
        "$env:ProgramFiles\Steam\steamapps\common\Sid Meier's Civilization V",
        "C:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "D:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "E:\SteamLibrary\steamapps\common\Sid Meier's Civilization V",
        "F:\SteamLibrary\steamapps\common\Sid Meier's Civilization V"
    )

    foreach($c in ($candidates | Where-Object {$_} | Select-Object -Unique)){
        $p=Join-Path $c "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua"
        if(Test-Path $p){ return $c }
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

$civ=Find-CivV $CivPath

if(!$civ){
    $manual=Read-Host "Paste Civilization V install folder"

    if($manual){
        $manual=$manual.Trim('"')

        if(Test-Path (Join-Path $manual "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua")){
            $civ=$manual
        }
    }
}

if(!$civ){
    throw "Civilization V not found."
}

$target=Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua"
$backup="$target.lek_host_instant_start_v01_backup"
$marker="LEK_HOST_INSTANT_START_V01_BEGIN"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LEKMOD 30.7 HOST INSTANT START v0.1" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Target:"
Write-Host "  $target"
Write-Host ""

$txt=[IO.File]::ReadAllText($target)

if($txt.Contains($marker)){
    Write-Host "Already installed." -ForegroundColor Yellow
    exit
}

# This is intentionally compatible with the reroll/rehost patch.
if($txt.Contains("LEK_REROLL_V021_STAGING_BEGIN")){
    Write-Host "Detected MP Reroll/Rehost v0.21: compatible." -ForegroundColor Green
}
elseif($txt.Contains("LEK_REROLL_V020_STAGING_BEGIN")){
    Write-Host "Detected MP Reroll/Rehost v0.20: compatible." -ForegroundColor Green
}
else {
    Write-Host "No reroll staging marker detected. Installing on current StagingRoom.lua." -ForegroundColor Yellow
}

# Verify the stock functions we depend on actually exist.
foreach($needle in @(
    "function LaunchGame()",
    "function CheckGameAutoStart()",
    "function UpdateDisplay()",
    "Controls.LaunchButton:RegisterCallback"
)){
    if(!$txt.Contains($needle)){
        throw "Expected Civ V staging-room code not found: $needle"
    }
}

if(!(Test-Path $backup)){
    Copy-Item $target $backup -Force
    Write-Host "Backup created:" -ForegroundColor Green
    Write-Host "  $backup"
}

$patch=@'

-- LEK_HOST_INSTANT_START_V01_BEGIN
--
-- Host-controlled instant launch for network multiplayer.
--
-- Behavior:
--   * New-game staging rooms show the host Launch button.
--   * Other human players do NOT need to click Ready.
--   * Civ V's normal ready-up countdown is disabled.
--   * Host click launches immediately through Matchmaking.LaunchMultiplayerGame().
--   * Everyone must still actually be connected.
--   * Existing map-size/team validity checks are preserved.
--
do
    local LEK_InstantStart_OriginalUpdateDisplay = UpdateDisplay;
    local LEK_InstantStart_OriginalShowHide = ShowHideHandler;

    local function LEK_InstantStart_PlayerCountValid()
        local totalPlayers = 0;

        for i = 0, GameDefines.MAX_MAJOR_CIVS do
            local status = PreGame.GetSlotStatus(i);

            if status == SlotStatus.SS_COMPUTER or status == SlotStatus.SS_TAKEN then
                if PreGame.GetSlotClaim(i) == SlotClaim.SLOTCLAIM_ASSIGNED then
                    totalPlayers = totalPlayers + 1;
                end
            end
        end

        local maxPlayers = GetMaxPlayersForCurrentMap();

        if maxPlayers == nil then
            return true;
        end

        return totalPlayers <= maxPlayers;
    end

    local function LEK_InstantStart_CanLaunch()
        if not Matchmaking.IsHost() then
            return false;
        end

        if PreGame.GameStarted() then
            return false;
        end

        -- Do not launch while an old player is still auto-rejoining / connecting.
        if not Network.IsEveryoneConnected() then
            return false;
        end

        -- Refresh the same team-validity state the stock auto-start code uses.
        if DoCheckTeams then
            DoCheckTeams();
        end

        if not m_bTeamsValid then
            return false;
        end

        if not LEK_InstantStart_PlayerCountValid() then
            return false;
        end

        return true;
    end

    local function LEK_InstantStart_RefreshButton()
        if not Controls or not Controls.LaunchButton then
            return;
        end

        local show = Matchmaking.IsHost()
            and not PreGame.GameStarted()
            and not IsInGameScreen();

        Controls.LaunchButton:SetHide(not show);

        if show then
            local canLaunch = LEK_InstantStart_CanLaunch();

            Controls.LaunchButton:SetDisabled(not canLaunch);
            Controls.LaunchButton:SetText("START GAME NOW");

            if not Network.IsEveryoneConnected() then
                Controls.LaunchButton:SetToolTipString(
                    "Waiting for all players to finish connecting. Ready-up is not required."
                );
            elseif not m_bTeamsValid then
                Controls.LaunchButton:SetToolTipString(
                    "The current team/player setup is not valid for launch."
                );
            elseif not LEK_InstantStart_PlayerCountValid() then
                Controls.LaunchButton:SetToolTipString(
                    "Too many active players for the selected map."
                );
            else
                Controls.LaunchButton:SetToolTipString(
                    "Host starts immediately. Other players do not need to Ready."
                );
            end
        end
    end

    function LEK_InstantStart_Launch()
        if not Matchmaking.IsHost() then
            return;
        end

        if not LEK_InstantStart_CanLaunch() then
            LEK_InstantStart_RefreshButton();
            return;
        end

        -- Guarantee the stock ready-up countdown is gone.
        if g_fCountdownTimer ~= nil and g_fCountdownTimer ~= -1 then
            StopCountdown();
        else
            Controls.CountdownButton:SetHide(true);
        end

        print("LEK HOST INSTANT START v0.1: host launching immediately");

        -- This is the same network launch call used by stock LaunchGame().
        Matchmaking.LaunchMultiplayerGame();
    end

    -- Replace the Launch button callback. No Ready-state check and no timer.
    Controls.LaunchButton:RegisterCallback(
        Mouse.eLClick,
        LEK_InstantStart_Launch
    );

    -- Disable stock "everyone ready -> countdown" behavior.
    function CheckGameAutoStart()
        if g_fCountdownTimer ~= nil and g_fCountdownTimer ~= -1 then
            StopCountdown();
        end

        if Controls and Controls.CountdownButton then
            Controls.CountdownButton:SetHide(true);
        end

        LEK_InstantStart_RefreshButton();
    end

    -- Stock UpdateDisplay normally only exposes manual Launch for loaded games.
    -- Re-expose it for the host in every normal pregame lobby.
    function UpdateDisplay()
        if LEK_InstantStart_OriginalUpdateDisplay then
            LEK_InstantStart_OriginalUpdateDisplay();
        end

        LEK_InstantStart_RefreshButton();
    end

    -- Ensure the button state is correct immediately when staging opens.
    function ShowHideHandler(hide,init)
        local result;

        if LEK_InstantStart_OriginalShowHide then
            result=LEK_InstantStart_OriginalShowHide(hide,init);
        end

        if not hide then
            LEK_InstantStart_RefreshButton();
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);

    print("LEK HOST INSTANT START v0.1 loaded");
end
-- LEK_HOST_INSTANT_START_V01_END
'@

$txt += "`r`n" + $patch
Write-NoBom $target $txt

$verify=[IO.File]::ReadAllText($target)

if(!$verify.Contains($marker)){
    throw "INSTALL VERIFICATION FAILED."
}

if(!$verify.Contains("LEK_InstantStart_Launch")){
    throw "INSTALL VERIFICATION FAILED: launch handler missing."
}

Write-Host ""
Write-Host "INSTALL VERIFIED." -ForegroundColor Green
Write-Host ""
Write-Host "The HOST will now get a START GAME NOW button." -ForegroundColor Cyan
Write-Host "Players do not need to Ready." -ForegroundColor Cyan
Write-Host "There is no start countdown." -ForegroundColor Cyan
Write-Host "All players must still be connected before Start Game Now activates." -ForegroundColor Cyan
