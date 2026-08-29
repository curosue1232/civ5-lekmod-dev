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
        if(Test-Path (Join-Path $c "Assets\UI\InGame\Menus\GameMenu.lua")){
            return $c
        }
    }
    return $null
}

function Restore-Previous {
    param([string]$Root)

    foreach($ver in @("020","019")){
        $suffix=".lek_reroll_v${ver}_backup"
        $backs=Get-ChildItem $Root -Filter "*$suffix" -Recurse -File -ErrorAction SilentlyContinue

        foreach($b in $backs){
            $target=$b.FullName.Substring(0,$b.FullName.Length-$suffix.Length)
            Copy-Item $b.FullName $target -Force
            Remove-Item $b.FullName -Force
            Write-Host "Restored previous reroll backup:" -ForegroundColor Yellow
            Write-Host "  $target"
        }
    }
}

function Backup-Once {
    param([string]$Path)

    $b="$Path.lek_reroll_v021_backup"
    if(!(Test-Path $b)){
        Copy-Item $Path $b -Force
    }
}

function Write-NoBom {
    param([string]$Path,[string]$Text)

    [IO.File]::WriteAllText(
        $Path,
        $Text,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Append-Verified {
    param(
        [string]$Path,
        [string]$Marker,
        [string]$Block
    )

    if(!(Test-Path $Path)){
        throw "Required file missing: $Path"
    }

    $txt=[IO.File]::ReadAllText($Path)

    if($txt.Contains($Marker)){
        Write-Host "Already patched: $Marker" -ForegroundColor Yellow
        return
    }

    Backup-Once $Path
    $txt += "`r`n" + $Block
    Write-NoBom $Path $txt

    if(!([IO.File]::ReadAllText($Path).Contains($Marker))){
        throw "Write verification failed: $Path"
    }

    Write-Host "VERIFIED: $Path" -ForegroundColor Green
}

$civ=Find-CivV $CivPath

if(!$civ){
    $manual=Read-Host "Paste Civilization V install folder"
    if($manual){
        $manual=$manual.Trim('"')
        if(Test-Path (Join-Path $manual "Assets\UI\InGame\Menus\GameMenu.lua")){
            $civ=$manual
        }
    }
}

if(!$civ){
    throw "Civilization V not found."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LEKMOD 30.7 MP REROLL / REHOST v0.21 AUTO-JOIN" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Undo v0.20/v0.19 cleanly before installing v0.21.
Restore-Previous $civ

$gameLua    = Join-Path $civ "Assets\UI\InGame\Menus\GameMenu.lua"
$mainLua    = Join-Path $civ "Assets\UI\FrontEnd\MainMenu.lua"
$selectLua  = Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\MultiplayerSelect.lua"
$lobbyLua   = Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\Lobby.lua"
$setupLua   = Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\GameSetup\MPGameSetupScreen.lua"
$stagingLua = Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\StagingRoom.lua"

$gameXmls=@(
    (Join-Path $civ "Assets\UI\InGame\Menus\GameMenu.xml"),
    (Join-Path $civ "Assets\DLC\Expansion\UI\InGame\Menus\GameMenu.xml"),
    (Join-Path $civ "Assets\DLC\Expansion2\UI\InGame\Menus\GameMenu.xml")
) | Where-Object {Test-Path $_}

foreach($p in @($gameLua,$mainLua,$selectLua,$lobbyLua,$setupLua,$stagingLua)){
    if(!(Test-Path $p)){
        throw "Required Civ V frontend file missing: $p"
    }
}

# Discover the game's own function that contains Matchmaking.JoinMultiplayerGame(serverID).
# Calling the stock wrapper is safer than guessing what UI it needs to queue.
$lobbyOriginal=[IO.File]::ReadAllText($lobbyLua)
$joinMatch=[regex]::Match(
    $lobbyOriginal,
    'function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*serverID(?:\s*,[^)]*)?\)[\s\S]{0,900}?Matchmaking\.JoinMultiplayerGame\s*\(\s*serverID\s*\)',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)

$stockJoinFn=""
if($joinMatch.Success){
    $stockJoinFn=$joinMatch.Groups[1].Value
    Write-Host "Detected stock lobby join function: $stockJoinFn" -ForegroundColor Green
}
else {
    Write-Host "Could not discover the stock join wrapper automatically." -ForegroundColor Yellow
    Write-Host "v0.21 will use Matchmaking.JoinMultiplayerGame(serverID) directly." -ForegroundColor Yellow
}

# Fresh v0.21 persistence DB on each computer.
$modUserData=Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Sid Meier's Civilization 5\ModUserData"
$v21db=Join-Path $modUserData "LEK_MP_REROLL_REHOST-21.db"

if(Test-Path $v21db){
    Remove-Item $v21db -Force
    Write-Host "Removed stale v0.21 user-data DB." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# BUTTON XML
# ---------------------------------------------------------------------
$button=@'
        <!-- LEK_REROLL_V021_BUTTON_BEGIN -->
        <GridButton Anchor="C,T" ID="LekRerollButton" Size="320,45" Style="ZoomButton" String="REROLL MAP / REHOST">
          <ShowOnMouseOver>
            <AlphaAnim Anchor="L,T" Size="320,48" Pause="0" Cycle="Bounce" Speed="1" AlphaStart="1.5" AlphaEnd="1">
              <Grid Size="320,48" Offset="0,-2" Padding="0,0" Style="Grid9FrameTurnsHL" />
            </AlphaAnim>
          </ShowOnMouseOver>
          <Image Anchor="C,B" AnchorSide="I.O" Offset="0,0" Texture="bar300x2.dds" Size="300.1" />
        </GridButton>
        <!-- LEK_REROLL_V021_BUTTON_END -->

'@

foreach($xml in $gameXmls){
    $txt=[IO.File]::ReadAllText($xml)

    if(!$txt.Contains("LEK_REROLL_V021_BUTTON_BEGIN")){
        $anchor='<GridButton Anchor="C,T" ID="RestartGameButton"'
        $idx=$txt.IndexOf($anchor)

        if($idx -ge 0){
            Backup-Once $xml
            $txt=$txt.Insert($idx,$button)
            Write-NoBom $xml $txt

            if(!([IO.File]::ReadAllText($xml).Contains("LEK_REROLL_V021_BUTTON_BEGIN"))){
                throw "Button verification failed: $xml"
            }

            Write-Host "VERIFIED BUTTON: $xml" -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------------
# IN-GAME
# Host generates a unique token and sends it to every client.
# Clients persist the token locally BEFORE they exit.
# ---------------------------------------------------------------------
$gameBlock=@'

-- LEK_REROLL_V021_GAME_BEGIN
do
    local RDB=Modding.OpenUserData("LEK_MP_REROLL_REHOST",21);
    local PREFIX="[[LEK_REROLL_V021:";
    local leavePending=false;
    local leaveTimer=0;

    local function put(k,v)
        local ok,err=pcall(function() return RDB.SetValue(k,v); end);
        if not ok then
            print("LEK REROLL v0.21 WRITE ERROR "..tostring(k)..": "..tostring(err));
        end
        return ok;
    end

    local function safeGet(fn,...)
        if type(fn)~="function" then return nil,false; end
        local args={...};
        local ok,v=pcall(function() return fn(unpack(args)); end);
        return v,ok;
    end

    local function MakeToken()
        local n=nil;

        if Map and Map.Rand then
            local ok,v=pcall(function()
                return Map.Rand(900000,"LEK MP reroll lobby token") + 100000;
            end);
            if ok then n=v; end
        end

        if not n then
            local ok,v=pcall(function()
                return math.random(100000,999999);
            end);
            if ok then n=v; end
        end

        if not n then
            n=(Game.GetGameTurn()+1)*1000 + Game.GetActivePlayer();
        end

        return tostring(n);
    end

    local function SaveHostSetup(token,targetName)
        put("Role","HOST");
        put("Pending",1);
        put("Stage",0);
        put("JoinToken",token);
        put("TargetGameName",targetName);
        put("Heartbeat","HOST_INGAME_SAVE_OK");

        local v,ok;

        v,ok=safeGet(PreGame.IsInternetGame);
        if ok then put("Internet",v and 1 or 0); else put("Internet",1); end

        v,ok=safeGet(PreGame.IsPrivateGame);
        if ok then put("OriginalPrivate",v and 1 or 0); end

        v,ok=safeGet(Matchmaking.GetCurrentGameName);
        if ok and v then put("OriginalGameName",v); end

        -- The replacement Internet lobby must be visible in the browser long enough
        -- for old clients to find it automatically.
        put("Private",0);

        v,ok=safeGet(PreGame.GetMapScript);
        if ok then put("MapScript",v or ""); end

        v,ok=safeGet(PreGame.GetWorldSize);
        if ok then put("WorldSize",v); end

        v,ok=safeGet(PreGame.GetGameSpeed);
        if ok then put("GameSpeed",v); end

        v,ok=safeGet(PreGame.GetEra);
        if ok then put("Era",v); end

        v,ok=safeGet(PreGame.GetMaxTurns);
        if ok then put("MaxTurns",v); end

        v,ok=safeGet(PreGame.GetNumMinorCivs);
        if ok then put("MinorCivs",v); end

        v,ok=safeGet(PreGame.IsRandomWorldSize);
        if ok then put("RandomWorldSize",v and 1 or 0); end

        v,ok=safeGet(Game.GetActivePlayer);
        if ok then put("OldHostPlayerID",v); end

        for i=0,GameDefines.MAX_MAJOR_CIVS-1 do
            v,ok=safeGet(PreGame.GetSlotStatus,i);
            if ok then put("SlotStatus_"..i,v); end

            v,ok=safeGet(PreGame.GetCivilization,i);
            if ok then put("Civ_"..i,v); end

            v,ok=safeGet(PreGame.GetTeam,i);
            if ok then put("Team_"..i,v); end

            v,ok=safeGet(PreGame.GetHandicap,i);
            if ok then put("Handicap_"..i,v); end
        end

        pcall(function()
            for row in GameInfo.GameOptions() do
                local x,got=safeGet(PreGame.GetGameOption,row.Type);
                if got and x~=nil then put("GO_"..row.Type,x); end
            end
        end);

        pcall(function()
            for row in GameInfo.Victories() do
                local x,got=safeGet(PreGame.IsVictory,row.ID);
                if got then put("Victory_"..row.ID,x and 1 or 0); end
            end
        end);

        pcall(function()
            local script=PreGame.GetMapScript();
            if script and script~="" and DB and DB.Query then
                for row in DB.Query(
                    "select OptionID from MapScriptOptions where FileName = ?",
                    script
                ) do
                    local x,got=safeGet(PreGame.GetMapOption,row.OptionID);
                    if got and x~=nil then put("MO_"..row.OptionID,x); end
                end
            end
        end);

        print("LEK REROLL v0.21 HOST STAGE 0: setup saved; token="..token);
    end

    local function SaveClientHandoff(token)
        put("Role","CLIENT");
        put("ClientPending",1);
        put("ClientStage",0);
        put("JoinToken",token);
        put("TargetGameName","LEK-REROLL-"..token);
        put("Heartbeat","CLIENT_INGAME_MARKER_OK");

        local oldID,ok=safeGet(Game.GetActivePlayer);
        if ok then put("ClientOldPlayerID",oldID); end

        local internet,ok2=safeGet(PreGame.IsInternetGame);
        if ok2 then put("ClientInternet",internet and 1 or 0); else put("ClientInternet",1); end

        print("LEK REROLL v0.21 CLIENT: handoff saved; token="..token);
    end

    local function ExitGame()
        m_ExitToMain=true;

        if OnYes then
            local ok=pcall(OnYes);
            if ok then return; end
        end

        if OnLeave then pcall(OnLeave); end
        Events.ExitToMainMenu();
    end

    Events.GameMessageChat.Add(function(fromPlayer,toPlayer,text,eTargetType)
        if Matchmaking.IsHost and Matchmaking.IsHost() then return; end
        if type(text)~="string" then return; end

        local token=string.match(text,"%[%[LEK_REROLL_V021:(%d+)%]%]");

        if token then
            SaveClientHandoff(token);
            ExitGame();
        end
    end);

    local function Click()
        if not Game or not Game:IsNetworkMultiPlayer() then return; end
        if not Matchmaking.IsHost() then return; end

        local token=MakeToken();
        local targetName="LEK-REROLL-"..token;

        Controls.LekRerollButton:SetText("SAVING...");
        SaveHostSetup(token,targetName);

        Controls.LekRerollButton:SetText("REHOSTING...");
        pcall(function()
            Network.SendChat(PREFIX..token.."]]",-1,-1);
        end);

        leavePending=true;
        leaveTimer=.50;
    end

    Controls.LekRerollButton:RegisterCallback(Mouse.eLClick,Click);

    ContextPtr:SetUpdate(function(dt)
        if leavePending then
            leaveTimer=leaveTimer-dt;

            if leaveTimer<=0 then
                leavePending=false;
                ExitGame();
            end
        end
    end);

    local oldShow=OnShowHide;

    function OnShowHide(hide,init)
        if oldShow then oldShow(hide,init); end

        if not hide then
            local mp=Game and Game:IsNetworkMultiPlayer();
            Controls.LekRerollButton:SetHide(not mp);

            if mp then
                Controls.LekRerollButton:SetDisabled(false);
                Controls.LekRerollButton:SetText(
                    Matchmaking.IsHost() and "REROLL MAP / REHOST"
                    or "REROLL MAP / REHOST (HOST ONLY)"
                );
            end
        end
    end

    ContextPtr:SetShowHideHandler(OnShowHide);
end
-- LEK_REROLL_V021_GAME_END
'@
Append-Verified $gameLua "LEK_REROLL_V021_GAME_BEGIN" $gameBlock

# ---------------------------------------------------------------------
# MAIN MENU
# Host and clients both continue automatically from their local DB.
# ---------------------------------------------------------------------
$mainBlock=@'

-- LEK_REROLL_V021_MAIN_BEGIN
do
    local RDB=Modding.OpenUserData("LEK_MP_REROLL_REHOST",21);
    local waiting=false;
    local timer=0;
    local fired=false;

    local function gv(k)
        local ok,v=pcall(function() return RDB.GetValue(k); end);
        if ok then return v; end
        return nil;
    end

    local function HostPending()
        return gv("Pending")==1 and gv("Stage")==0;
    end

    local function ClientPending()
        return gv("ClientPending")==1 and gv("ClientStage")==0;
    end

    local function Continue()
        if fired then return; end

        if HostPending() then
            fired=true;
            RDB.SetValue("Heartbeat","HOST_MAINMENU_OK");
            RDB.SetValue("Stage",1);

            print("LEK REROLL v0.21 HOST: MainMenu -> MultiplayerSelect");

            UIManager:QueuePopup(
                Controls.MultiplayerSelectScreen,
                PopupPriority.MultiplayerSelectScreen
            );

        elseif ClientPending() then
            fired=true;
            RDB.SetValue("Heartbeat","CLIENT_MAINMENU_OK");
            RDB.SetValue("ClientStage",1);

            print("LEK REROLL v0.21 CLIENT: MainMenu -> MultiplayerSelect");

            UIManager:QueuePopup(
                Controls.MultiplayerSelectScreen,
                PopupPriority.MultiplayerSelectScreen
            );
        end
    end

    local oldShow=ShowHideHandler;

    function ShowHideHandler(hide,init)
        local result;
        if oldShow then result=oldShow(hide,init); end

        if not hide and (HostPending() or ClientPending()) then
            waiting=true;
            timer=.50;
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);

    Events.SystemUpdateUI.Add(function(kind,tag)
        if kind==SystemUpdateUIType.RestoreUI and tag=="MainMenu" then
            if HostPending() or ClientPending() then
                waiting=true;
                timer=.15;
            end
        end
    end);

    ContextPtr:SetUpdate(function(dt)
        if waiting then
            timer=timer-dt;
            if timer<=0 then
                waiting=false;
                Continue();
            end
        end
    end);
end
-- LEK_REROLL_V021_MAIN_END
'@
Append-Verified $mainLua "LEK_REROLL_V021_MAIN_BEGIN" $mainBlock

# ---------------------------------------------------------------------
# MULTIPLAYER SELECT
# Host: same v0.20 flow.
# Client: automatically selects Internet/LAN and enters server browser.
# ---------------------------------------------------------------------
$selectBlock=@'

-- LEK_REROLL_V021_SELECT_BEGIN
do
    local RDB=Modding.OpenUserData("LEK_MP_REROLL_REHOST",21);
    local waiting=false;
    local timer=0;
    local mode=nil;

    local function gv(k)
        local ok,v=pcall(function() return RDB.GetValue(k); end);
        if ok then return v; end
        return nil;
    end

    local oldShow=ShowHideHandler;

    function ShowHideHandler(hide,init)
        local result;
        if oldShow then result=oldShow(hide,init); end

        if not hide then
            if gv("Pending")==1 and gv("Stage")==1 then
                mode="HOST";
                waiting=true;
                timer=.20;

            elseif gv("ClientPending")==1 and gv("ClientStage")==1 then
                mode="CLIENT";
                waiting=true;
                timer=.20;
            end
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);

    ContextPtr:SetUpdate(function(dt)
        if not waiting then return; end

        timer=timer-dt;
        if timer>0 then return; end

        waiting=false;

        if StandardButtonClick then
            pcall(StandardButtonClick);
        end

        if mode=="HOST" and gv("Pending")==1 and gv("Stage")==1 then
            RDB.SetValue("Heartbeat","HOST_MULTIPLAYER_SELECT_OK");
            RDB.SetValue("Stage",2);

            if gv("Internet")~=0 then
                print("LEK REROLL v0.21 HOST: Internet -> Lobby");
                InternetButtonClick();
            else
                print("LEK REROLL v0.21 HOST: LAN -> Lobby");
                LANButtonClick();
            end

        elseif mode=="CLIENT" and gv("ClientPending")==1 and gv("ClientStage")==1 then
            RDB.SetValue("Heartbeat","CLIENT_MULTIPLAYER_SELECT_OK");
            RDB.SetValue("ClientStage",2);

            if gv("ClientInternet")~=0 then
                print("LEK REROLL v0.21 CLIENT: Internet -> Lobby browser");
                InternetButtonClick();
            else
                print("LEK REROLL v0.21 CLIENT: LAN -> Lobby browser");
                LANButtonClick();
            end
        end
    end);
end
-- LEK_REROLL_V021_SELECT_END
'@
Append-Verified $selectLua "LEK_REROLL_V021_SELECT_BEGIN" $selectBlock

# ---------------------------------------------------------------------
# LOBBY
# Host opens host setup.
# Client refreshes repeatedly and joins the uniquely named replacement lobby.
# ---------------------------------------------------------------------
$lobbyBlock=@'

-- LEK_REROLL_V021_LOBBY_BEGIN
do
    local RDB=Modding.OpenUserData("LEK_MP_REROLL_REHOST",21);

    local hostWaiting=false;
    local hostTimer=0;

    local clientSearching=false;
    local refreshTimer=0;
    local elapsed=0;
    local joinStarted=false;

    local function gv(k)
        local ok,v=pcall(function() return RDB.GetValue(k); end);
        if ok then return v; end
        return nil;
    end

    local function ContainsTarget(value,target,depth)
        if depth>4 or value==nil then return false; end

        local t=type(value);

        if t=="string" then
            return string.find(value,target,1,true)~=nil;
        end

        if t=="table" then
            for k,v in pairs(value) do
                if ContainsTarget(k,target,depth+1) or ContainsTarget(v,target,depth+1) then
                    return true;
                end
            end
        end

        return false;
    end

    local function StartJoin(serverID)
        if joinStarted or not serverID then return; end

        joinStarted=true;

        RDB.SetValue("Heartbeat","CLIENT_FOUND_TARGET_SERVER");
        RDB.SetValue("ClientStage",3);
        RDB.SetValue("FoundServerID",tostring(serverID));

        print("LEK REROLL v0.21 CLIENT: target lobby found; serverID="..tostring(serverID));

        local ok,err=pcall(function()
            __LEK_STOCK_JOIN__
        end);

        if not ok then
            print("LEK REROLL v0.21 CLIENT stock join error: "..tostring(err));

            local ok2,err2=pcall(function()
                Matchmaking.JoinMultiplayerGame(serverID);
            end);

            if not ok2 then
                RDB.SetValue("Heartbeat","CLIENT_JOIN_CALL_ERROR:"..tostring(err2));
                RDB.SetValue("ClientStage",-3);
                joinStarted=false;
            end
        end
    end

    local function TryEntry(entry,fallbackID)
        if joinStarted or not entry then return false; end

        local target=gv("TargetGameName");
        if not target or target=="" then return false; end

        if ContainsTarget(entry,target,0) then
            local sid=nil;

            if type(entry)=="table" then
                sid=entry.serverID or entry.ServerID or entry.idLobby or entry.lobbyID or entry.ID or entry.id;
            end

            sid=sid or fallbackID;

            if sid then
                StartJoin(sid);
                return true;
            end
        end

        return false;
    end

    local function TryLobbyID(idLobby)
        if joinStarted or not idLobby then return false; end

        local ok,entry=pcall(function()
            return Matchmaking.GetMultiplayerServerEntry(idLobby);
        end);

        if ok and entry then
            return TryEntry(entry,idLobby);
        end

        return false;
    end

    local function ScanAll()
        if joinStarted then return; end

        local ok,games=pcall(function()
            return Matchmaking.GetMultiplayerGameList();
        end);

        if not ok or type(games)~="table" then return; end

        for k,v in pairs(games) do
            if joinStarted then return; end

            if type(v)=="table" then
                TryEntry(v,k);
            else
                TryLobbyID(v);
                TryLobbyID(k);
            end
        end
    end

    local function Refresh()
        if joinStarted then return; end

        if gv("ClientInternet")~=0 then
            pcall(function() Matchmaking.RefreshInternetGameList(); end);
        else
            pcall(function() Matchmaking.RefreshLANGameList(); end);
        end

        ScanAll();
    end

    Events.MultiplayerGameListUpdated.Add(function(eAction,idLobby,eLobbyType,eSearchType)
        if clientSearching and not joinStarted then
            TryLobbyID(idLobby);
        end
    end);

    Events.MultiplayerGameListComplete.Add(function()
        if clientSearching and not joinStarted then
            ScanAll();
        end
    end);

    local oldShow=ShowHideHandler;

    function ShowHideHandler(hide,init)
        local result;
        if oldShow then result=oldShow(hide,init); end

        if not hide then
            if gv("Pending")==1 and gv("Stage")==2 then
                hostWaiting=true;
                hostTimer=.25;

            elseif gv("ClientPending")==1 and gv("ClientStage")==2 then
                clientSearching=true;
                refreshTimer=.10;
                elapsed=0;

                RDB.SetValue("Heartbeat","CLIENT_LOBBY_BROWSER_OK");

                print(
                    "LEK REROLL v0.21 CLIENT: searching for "..
                    tostring(gv("TargetGameName"))
                );
            end
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);

    ContextPtr:SetUpdate(function(dt)
        if hostWaiting then
            hostTimer=hostTimer-dt;

            if hostTimer<=0 then
                hostWaiting=false;

                if gv("Pending")==1 and gv("Stage")==2 then
                    RDB.SetValue("Heartbeat","HOST_LOBBY_OK");
                    RDB.SetValue("Stage",3);

                    print("LEK REROLL v0.21 HOST: Lobby -> Host Setup");
                    HostButtonClick();
                end
            end
        end

        if clientSearching and not joinStarted then
            elapsed=elapsed+dt;
            refreshTimer=refreshTimer-dt;

            if refreshTimer<=0 then
                refreshTimer=1.00;
                Refresh();
            end

            if elapsed>=45 then
                clientSearching=false;
                RDB.SetValue("Heartbeat","CLIENT_TARGET_NOT_FOUND_45S");
                RDB.SetValue("ClientStage",-2);

                print("LEK REROLL v0.21 CLIENT: target lobby not found after 45 seconds");
            end
        end
    end);
end
-- LEK_REROLL_V021_LOBBY_END
'@

if($stockJoinFn){
    $stockCall="$stockJoinFn(serverID);"
}
else {
    $stockCall="Matchmaking.JoinMultiplayerGame(serverID);"
}

$lobbyBlock=$lobbyBlock.Replace("__LEK_STOCK_JOIN__",$stockCall)
Append-Verified $lobbyLua "LEK_REROLL_V021_LOBBY_BEGIN" $lobbyBlock

# ---------------------------------------------------------------------
# HOST SETUP
# Same proven v0.20 host route, except replacement name is unique and
# the replacement Internet lobby is public so clients can discover it.
# ---------------------------------------------------------------------
$setupBlock=@'

-- LEK_REROLL_V021_SETUP_BEGIN
do
    local RDB=Modding.OpenUserData("LEK_MP_REROLL_REHOST",21);
    local waiting=false;
    local timer=0;

    local function gv(k)
        local ok,v=pcall(function() return RDB.GetValue(k); end);
        if ok then return v; end
        return nil;
    end

    local function call(fn,...)
        if type(fn)~="function" then return; end
        local args={...};
        pcall(function() fn(unpack(args)); end);
    end

    local function Restore()
        call(PreGame.SetPersistSettings,false);
        call(PreGame.SetLoadFileName,"");
        call(PreGame.SetLoadWBScenario,false);

        -- Browser-based client auto-join requires a discoverable replacement lobby.
        call(PreGame.SetPrivateGame,false);

        local v;

        v=gv("MapScript");
        if v and v~="" then call(PreGame.SetMapScript,v); end

        if PreGame.SetRandomMapScript then
            call(PreGame.SetRandomMapScript,false);
        end

        v=gv("WorldSize");
        if v~=nil then call(PreGame.SetWorldSize,v); end

        v=gv("RandomWorldSize");
        if v~=nil then call(PreGame.SetRandomWorldSize,v==1); end

        v=gv("GameSpeed");
        if v~=nil then call(PreGame.SetGameSpeed,v); end

        v=gv("Era");
        if v~=nil then call(PreGame.SetEra,v); end

        v=gv("MaxTurns");
        if v~=nil then call(PreGame.SetMaxTurns,v); end

        v=gv("MinorCivs");
        if v~=nil then call(PreGame.SetNumMinorCivs,v); end

        pcall(function()
            for row in GameInfo.GameOptions() do
                local x=gv("GO_"..row.Type);
                if x~=nil then call(PreGame.SetGameOption,row.Type,x); end
            end
        end);

        pcall(function()
            for row in GameInfo.Victories() do
                local x=gv("Victory_"..row.ID);
                if x~=nil then call(PreGame.SetVictory,row.ID,x==1); end
            end
        end);

        pcall(function()
            local script=PreGame.GetMapScript();

            if script and script~="" and DB and DB.Query then
                for row in DB.Query(
                    "select OptionID from MapScriptOptions where FileName = ?",
                    script
                ) do
                    local x=gv("MO_"..row.OptionID);

                    if x~=nil then
                        call(PreGame.SetMapOption,row.OptionID,x);
                    end
                end
            end
        end);

        local gameName=gv("TargetGameName");
        if not gameName or gameName=="" then
            gameName="LEK-REROLL";
        end

        if Controls.NameBox then
            pcall(function() Controls.NameBox:SetText(gameName); end);
        elseif Controls.GameNameBox then
            pcall(function() Controls.GameNameBox:SetText(gameName); end);
        end

        if UpdateDisplay then pcall(UpdateDisplay); end

        RDB.SetValue("Heartbeat","HOST_MP_SETUP_RESTORED");
    end

    local oldShow=ShowHideHandler;

    function ShowHideHandler(hide,init)
        local result;
        if oldShow then result=oldShow(hide,init); end

        if not hide and gv("Pending")==1 and gv("Stage")==3 then
            RDB.SetValue("Stage",4);
            pcall(Restore);

            waiting=true;
            timer=.25;

            print("LEK REROLL v0.21 HOST STAGE 4: MP setup ready");
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);

    ContextPtr:SetUpdate(function(dt)
        if waiting then
            timer=timer-dt;

            if timer<=0 then
                waiting=false;

                if gv("Pending")==1 and gv("Stage")==4 then
                    print("LEK REROLL v0.21 HOST: invoking stock OnStart");

                    local ok,err=pcall(OnStart);

                    if not ok then
                        RDB.SetValue("Heartbeat","HOST_ONSTART_ERROR:"..tostring(err));
                        RDB.SetValue("Stage",-4);
                    end
                end
            end
        end
    end);
end
-- LEK_REROLL_V021_SETUP_END
'@
Append-Verified $setupLua "LEK_REROLL_V021_SETUP_BEGIN" $setupBlock

# ---------------------------------------------------------------------
# STAGING
# Host restores old slot layout.
# Client clears auto-join state once it reaches the replacement staging room.
# ---------------------------------------------------------------------
$stagingBlock=@'

-- LEK_REROLL_V021_STAGING_BEGIN
do
    local RDB=Modding.OpenUserData("LEK_MP_REROLL_REHOST",21);
    local hostDone=false;
    local clientDone=false;

    local function gv(k)
        local ok,v=pcall(function() return RDB.GetValue(k); end);
        if ok then return v; end
        return nil;
    end

    local function call(fn,...)
        if type(fn)~="function" then return; end
        local args={...};
        pcall(function() fn(unpack(args)); end);
    end

    local function RestoreHostSlots()
        if hostDone then return; end
        if gv("Pending")~=1 or gv("Stage")~=4 then return; end
        if not Matchmaking.IsHost() then return; end

        local localID=Matchmaking.GetLocalID();
        local oldHost=gv("OldHostPlayerID");

        if oldHost==nil then oldHost=0; end

        local v=gv("Civ_"..oldHost);
        if v~=nil then call(PreGame.SetCivilization,localID,v); end

        v=gv("Team_"..oldHost);
        if v~=nil then call(PreGame.SetTeam,localID,v); end

        v=gv("Handicap_"..oldHost);
        if v~=nil then call(PreGame.SetHandicap,localID,v); end

        for i=0,GameDefines.MAX_MAJOR_CIVS-1 do
            if i~=localID then
                local s=gv("SlotStatus_"..i);

                if s~=nil then
                    if s==SlotStatus.SS_TAKEN then
                        call(PreGame.SetSlotStatus,i,SlotStatus.SS_OPEN);
                    else
                        call(PreGame.SetSlotStatus,i,s);
                    end
                end

                v=gv("Civ_"..i);
                if v~=nil then call(PreGame.SetCivilization,i,v); end

                v=gv("Team_"..i);
                if v~=nil then call(PreGame.SetTeam,i,v); end

                v=gv("Handicap_"..i);
                if v~=nil then call(PreGame.SetHandicap,i,v); end
            end
        end

        call(Network.BroadcastPlayerInfo);

        if UpdateDisplay then
            pcall(UpdateDisplay);
        end

        hostDone=true;
        RDB.SetValue("Heartbeat","HOST_STAGING_COMPLETE");
        RDB.SetValue("Stage",5);
        RDB.SetValue("Pending",0);

        print("LEK REROLL v0.21 HOST COMPLETE: replacement lobby ready");
    end

    local function FinishClientJoin()
        if clientDone then return; end
        if gv("ClientPending")~=1 then return; end
        if Matchmaking.IsHost() then return; end

        clientDone=true;

        RDB.SetValue("Heartbeat","CLIENT_STAGING_COMPLETE");
        RDB.SetValue("ClientStage",5);
        RDB.SetValue("ClientPending",0);

        print(
            "LEK REROLL v0.21 CLIENT COMPLETE: joined replacement lobby; local slot="..
            tostring(Matchmaking.GetLocalID())
        );
    end

    local oldShow=ShowHideHandler;

    function ShowHideHandler(hide,init)
        local result;
        if oldShow then result=oldShow(hide,init); end

        if not hide then
            pcall(RestoreHostSlots);
            pcall(FinishClientJoin);
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);
end
-- LEK_REROLL_V021_STAGING_END
'@
Append-Verified $stagingLua "LEK_REROLL_V021_STAGING_BEGIN" $stagingBlock

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " v0.21 POST-INSTALL VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================================"

$checks=@(
    @($gameLua,"LEK_REROLL_V021_GAME_BEGIN"),
    @($mainLua,"LEK_REROLL_V021_MAIN_BEGIN"),
    @($selectLua,"LEK_REROLL_V021_SELECT_BEGIN"),
    @($lobbyLua,"LEK_REROLL_V021_LOBBY_BEGIN"),
    @($setupLua,"LEK_REROLL_V021_SETUP_BEGIN"),
    @($stagingLua,"LEK_REROLL_V021_STAGING_BEGIN")
)

$good=$true

foreach($c in $checks){
    $p=$c[0]
    $m=$c[1]

    if((Test-Path $p) -and ([IO.File]::ReadAllText($p).Contains($m))){
        Write-Host "PASS  $m" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL  $m" -ForegroundColor Red
        $good=$false
    }
}

if(!$good){
    throw "v0.21 verification failed. Do not test in game."
}

Write-Host ""
Write-Host "V0.21 VERIFIED INSTALL SUCCESSFUL." -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT: install v0.21 on EVERY human player's PC." -ForegroundColor Cyan
Write-Host "Replacement Internet lobbies are made public so clients can discover the unique token." -ForegroundColor Cyan
