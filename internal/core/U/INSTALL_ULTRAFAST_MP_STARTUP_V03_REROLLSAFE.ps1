param([string]$CivPath="")
$ErrorActionPreference="Stop"

$V03Suffix=".lek_ultrafast_mp_startup_v03_backup"
$V02Disabled=".lek_ultrafast_mp_startup_v02_disabled"
$V03Disabled=".lek_ultrafast_mp_startup_v03_disabled"

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
        if(Test-Path (Join-Path $c "Assets\UI\FrontEnd\MainMenu.lua")){
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

    $b="$Path$V03Suffix"
    if(!(Test-Path $b)){
        Copy-Item $Path $b -Force
    }
}

function Remove-Block {
    param(
        [string]$Text,
        [string]$BeginMarker,
        [string]$EndMarker
    )

    $begin=$Text.IndexOf($BeginMarker)
    if($begin -lt 0){ return $Text }

    $end=$Text.IndexOf($EndMarker,$begin)
    if($end -lt 0){ return $Text }

    $end += $EndMarker.Length

    while($end -lt $Text.Length -and ($Text[$end] -eq "`r" -or $Text[$end] -eq "`n")){
        $end++
    }

    return $Text.Remove($begin,$end-$begin)
}

function Upgrade-Lua {
    param(
        [string]$Path,
        [string]$V02Begin,
        [string]$V02End,
        [string]$V03Begin,
        [string]$Block
    )

    if(!(Test-Path $Path)){
        throw "Required frontend file missing: $Path"
    }

    $txt=[IO.File]::ReadAllText($Path)

    # Capture exact currently-working stack before changing UltraFast.
    Backup-Once $Path

    # Remove ONLY the old UltraFast v0.2 block. This preserves reroll v0.21,
    # Host Instant Start, EUI, Lekmod, etc.
    $txt=Remove-Block $txt $V02Begin $V02End

    if(!$txt.Contains($V03Begin)){
        $txt += "`r`n" + $Block
    }

    Write-NoBom $Path $txt

    if(!([IO.File]::ReadAllText($Path).Contains($V03Begin))){
        throw "v0.3 write verification failed: $Path"
    }

    Write-Host "VERIFIED  $Path" -ForegroundColor Green
}

$civ=Find-CivV $CivPath

if(!$civ){
    $manual=Read-Host "Paste Civilization V install folder"

    if($manual){
        $manual=$manual.Trim('"')
        $civ=Find-CivV $manual
    }
}

if(!$civ){
    throw "Civilization V not found."
}

$mainLua   = Join-Path $civ "Assets\UI\FrontEnd\MainMenu.lua"
$selectLua = Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\MultiplayerSelect.lua"
$lobbyLua  = Join-Path $civ "Assets\UI\FrontEnd\Multiplayer\Lobby.lua"
$frontEndLua = Join-Path $civ "Assets\UI\FrontEnd\FrontEnd.lua"
$rerollLua = Join-Path $civ "Assets\UI\InGame\Menus\GameMenu.lua"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LEKMOD 30.7 ULTRA-FAST MP STARTUP v0.3.1" -ForegroundColor Cyan
Write-Host " REROLL-SAFE BUILD - FIXED VERIFIER" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if((Test-Path $rerollLua) -and ([IO.File]::ReadAllText($rerollLua).Contains("LEK_REROLL_V021_GAME_BEGIN"))){
    Write-Host "FOUND  Reroll/Rehost v0.21" -ForegroundColor Green
}
else {
    Write-Host "WARN   Reroll/Rehost v0.21 marker not detected." -ForegroundColor Yellow
}

# ----------------------------------------------------------------------
# STARTUP LOGOS / OPENING MOVIES
# ----------------------------------------------------------------------
$movieDirs=@(
    $civ,
    (Join-Path $civ "Assets\DLC\Expansion"),
    (Join-Path $civ "Assets\DLC\Expansion2")
)

Write-Host ""
Write-Host "Disabling opening-logo media..." -ForegroundColor Cyan

foreach($dir in $movieDirs){
    if(!(Test-Path $dir)){ continue }

    $movies=Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^Civ5.*Opening_Movie.*\.(wmv|wma)$' -or
            $_.Name -match '^Opening_Movie.*\.(wmv|wma)$'
        }

    foreach($m in $movies){
        $disabled=$m.FullName+$V03Disabled

        if(!(Test-Path $disabled)){
            Move-Item $m.FullName $disabled -Force
            Write-Host "DISABLED  $($m.Name)" -ForegroundColor Green
        }
    }
}

# Existing v0.2-disabled media remains disabled and is intentionally left alone.

# Civ V's own skip-intro setting.
$docs=[Environment]::GetFolderPath("MyDocuments")
$userSettings=Join-Path $docs "My Games\Sid Meier's Civilization 5\UserSettings.ini"
$userBackup="$userSettings$V03Suffix"

if(Test-Path $userSettings){
    if(!(Test-Path $userBackup)){
        Copy-Item $userSettings $userBackup -Force
    }

    $u=[IO.File]::ReadAllText($userSettings)

    if($u -match '(?m)^\s*SkipIntroVideo\s*='){
        $u=[regex]::Replace(
            $u,
            '(?m)^\s*SkipIntroVideo\s*=\s*\d+\s*$',
            'SkipIntroVideo = 1'
        )
    }
    else {
        $u += "`r`nSkipIntroVideo = 1`r`n"
    }

    Write-NoBom $userSettings $u
    Write-Host "SET       SkipIntroVideo = 1" -ForegroundColor Green
}

# Disable stock legal popup when present, without touching any existing v0.2 edit.
if(Test-Path $frontEndLua){
    $f=[IO.File]::ReadAllText($frontEndLua)

    if(!$f.Contains("LEK_ULTRAFAST_V02_LEGAL_SKIP") -and
       !$f.Contains("LEK_ULTRAFAST_V03_LEGAL_SKIP")){

        $pattern='(?m)^(\s*)UIManager:QueuePopup\(\s*Controls\.LegalScreen\s*,\s*PopupPriority\.LegalScreen\s*\);\s*$'
        $m=[regex]::Match($f,$pattern)

        if($m.Success){
            Backup-Once $frontEndLua

            $replacement=$m.Groups[1].Value+
                "-- LEK_ULTRAFAST_V03_LEGAL_SKIP: startup LegalScreen disabled`r`n"+
                $m.Groups[1].Value+
                "-- "+$m.Value.Trim()

            $f=[regex]::Replace($f,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{param($x) $replacement},1)
            Write-NoBom $frontEndLua $f
            Write-Host "DISABLED  stock LegalScreen startup popup" -ForegroundColor Green
        }
    }
}

# ----------------------------------------------------------------------
# MAIN MENU
#
# CRITICAL v0.3 CHANGE:
# NO ContextPtr:SetUpdate().
#
# We wait for Civ V's stock RestoreUI event, which happens after
# Modding.ActivateDLC() / PreGame.LoadPreGameSettings().
#
# During a reroll, v0.21 Pending/ClientPending takes priority and this code
# does absolutely nothing.
# ----------------------------------------------------------------------
$mainBlock=@'

-- LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_BEGIN
do
    local FASTDB=Modding.OpenUserData("LEK_ULTRAFAST_MP_STARTUP",3);
    local fired=false;

    local function RerollPending()
        local ok,db=pcall(function()
            return Modding.OpenUserData("LEK_MP_REROLL_REHOST",21);
        end);

        if not ok or not db then
            return false;
        end

        local function get(k)
            local ok2,v=pcall(function() return db.GetValue(k); end);
            if ok2 then return v; end
            return nil;
        end

        return get("Pending")==1 or get("ClientPending")==1;
    end

    local function Go()
        if fired or RerollPending() then
            return;
        end

        fired=true;

        FASTDB.SetValue("AutoInternet",1);
        FASTDB.SetValue("AutoFriendJoin",0);
        FASTDB.SetValue("Heartbeat","MAINMENU_READY");

        print("LEK ULTRAFAST v0.3: MainMenu -> MultiplayerSelect");

        UIManager:QueuePopup(
            Controls.MultiplayerSelectScreen,
            PopupPriority.MultiplayerSelectScreen
        );
    end

    -- Do not replace MainMenu's SetUpdate handler.
    -- Reroll/Rehost v0.21 owns it.
    Events.SystemUpdateUI.Add(function(kind,tag)
        if kind==SystemUpdateUIType.RestoreUI and tag=="MainMenu" then
            Go();
        end
    end);
end
-- LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_END
'@

Upgrade-Lua `
    $mainLua `
    "-- LEK_ULTRAFAST_MP_STARTUP_V02_MAIN_BEGIN" `
    "-- LEK_ULTRAFAST_MP_STARTUP_V02_MAIN_END" `
    "LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_BEGIN" `
    $mainBlock

# ----------------------------------------------------------------------
# MULTIPLAYER SELECT
#
# NO SetUpdate. After stock ShowHide completes, immediately follow the
# stock Standard -> Internet path.
#
# On reroll v0.21, AutoInternet is not set, so this wrapper simply passes
# through to v0.21's own ShowHide/update logic.
# ----------------------------------------------------------------------
$selectBlock=@'

-- LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_BEGIN
do
    local FASTDB=Modding.OpenUserData("LEK_ULTRAFAST_MP_STARTUP",3);

    local function get(k)
        local ok,v=pcall(function() return FASTDB.GetValue(k); end);
        if ok then return v; end
        return nil;
    end

    local oldShow=ShowHideHandler;

    function ShowHideHandler(hide,init)
        local result;

        if oldShow then
            result=oldShow(hide,init);
        end

        if not hide and get("AutoInternet")==1 then
            -- Clear first so Back never loops straight into Internet again.
            FASTDB.SetValue("AutoInternet",0);
            FASTDB.SetValue("AutoFriendJoin",1);
            FASTDB.SetValue("Heartbeat","MULTIPLAYER_SELECT_READY");

            print("LEK ULTRAFAST v0.3: direct Standard Internet");

            if StandardButtonClick then
                pcall(StandardButtonClick);
            end

            InternetButtonClick();
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);

    -- Intentionally NO ContextPtr:SetUpdate here.
end
-- LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_END
'@

Upgrade-Lua `
    $selectLua `
    "-- LEK_ULTRAFAST_MP_STARTUP_V02_SELECT_BEGIN" `
    "-- LEK_ULTRAFAST_MP_STARTUP_V02_SELECT_END" `
    "LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_BEGIN" `
    $selectBlock

# ----------------------------------------------------------------------
# LOBBY / FRIEND AUTOJOIN
#
# NO SetUpdate.
# One refresh is issued immediately.
# MultiplayerGameListUpdated / Complete events perform discovery.
# If no friend lobby is found when the refresh completes, startup simply
# leaves you in the normal Internet browser.
# ----------------------------------------------------------------------

$lobbyOriginal=[IO.File]::ReadAllText($lobbyLua)
$joinMatch=[regex]::Match(
    $lobbyOriginal,
    'function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*serverID(?:\s*,[^)]*)?\)[\s\S]{0,1200}?Matchmaking\.JoinMultiplayerGame\s*\(\s*serverID\s*\)',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if($joinMatch.Success){
    $stockJoinFn=$joinMatch.Groups[1].Value
    $stockJoinCall="$stockJoinFn(serverID);"
    Write-Host "FOUND     stock lobby join wrapper: $stockJoinFn" -ForegroundColor Green
}
else {
    $stockJoinCall="Matchmaking.JoinMultiplayerGame(serverID);"
    Write-Host "WARN      using direct Matchmaking.JoinMultiplayerGame()" -ForegroundColor Yellow
}

$lobbyBlock=@'

-- LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_BEGIN
do
    local FASTDB=Modding.OpenUserData("LEK_ULTRAFAST_MP_STARTUP",3);
    local searching=false;
    local joinStarted=false;

    local function get(k)
        local ok,v=pcall(function() return FASTDB.GetValue(k); end);
        if ok then return v; end
        return nil;
    end

    local function norm(v)
        if v==nil then return nil; end

        local s=string.lower(tostring(v));
        s=string.gsub(s,"^%s+","");
        s=string.gsub(s,"%s+$","");

        if s=="" then return nil; end
        return s;
    end

    local ignored={
        ["online"]=true,
        ["offline"]=true,
        ["ingame"]=true,
        ["in-game"]=true,
        ["in game"]=true,
        ["away"]=true,
        ["busy"]=true,
        ["true"]=true,
        ["false"]=true
    };

    local friendFields={
        "name","Name",
        "playerName","PlayerName",
        "friendName","FriendName",
        "personaName","PersonaName",
        "steamName","SteamName",
        "steamID","SteamID",
        "friendID","FriendID"
    };

    local lobbyFields={
        "serverID","ServerID",
        "lobbyID","LobbyID",
        "idLobby","IDLobby"
    };

    local function AddToken(tokens,v)
        local s=norm(v);
        if not s then return; end
        if string.len(s)<3 then return; end
        if ignored[s] then return; end

        local n=tonumber(s);
        if n and n<1000000 then return; end

        tokens[s]=true;
    end

    local function GetFriends()
        local ok,list=pcall(function()
            return Matchmaking.GetFriendList();
        end);

        if ok and type(list)=="table" then
            return list;
        end

        return {};
    end

    local function BuildFriendTokens(friends)
        local tokens={};

        for _,friend in pairs(friends) do
            if type(friend)=="table" then
                local preferred=false;

                for _,field in ipairs(friendFields) do
                    if friend[field]~=nil then
                        AddToken(tokens,friend[field]);
                        preferred=true;
                    end
                end

                if not preferred then
                    for _,v in pairs(friend) do
                        if type(v)=="string" or type(v)=="number" then
                            AddToken(tokens,v);
                        end
                    end
                end
            elseif type(friend)=="string" or type(friend)=="number" then
                AddToken(tokens,friend);
            end
        end

        return tokens;
    end

    local function DirectFriendLobby(friends)
        for _,friend in pairs(friends) do
            if type(friend)=="table" then
                for _,field in ipairs(lobbyFields) do
                    local id=friend[field];

                    if id~=nil and tostring(id)~="" and tostring(id)~="0" then
                        return id;
                    end
                end
            end
        end

        return nil;
    end

    local function EntryContainsFriend(entry,tokens,depth)
        if depth>5 or entry==nil then return false; end

        local t=type(entry);

        if t=="string" or t=="number" then
            local s=norm(entry);
            if not s then return false; end

            if tokens[s] then return true; end

            if not tonumber(s) and string.len(s)>=4 then
                for token,_ in pairs(tokens) do
                    if not tonumber(token) and string.len(token)>=4 then
                        if string.find(s,token,1,true) then
                            return true;
                        end
                    end
                end
            end

            return false;
        end

        if t=="table" then
            local hostFields={
                "hostName","HostName",
                "host","Host",
                "ownerName","OwnerName",
                "owner","Owner",
                "hostSteamID","HostSteamID",
                "ownerSteamID","OwnerSteamID"
            };

            local hadHost=false;

            for _,field in ipairs(hostFields) do
                if entry[field]~=nil then
                    hadHost=true;

                    if EntryContainsFriend(entry[field],tokens,depth+1) then
                        return true;
                    end
                end
            end

            if hadHost then return false; end

            for k,v in pairs(entry) do
                if EntryContainsFriend(k,tokens,depth+1)
                    or EntryContainsFriend(v,tokens,depth+1) then
                    return true;
                end
            end
        end

        return false;
    end

    local function ExtractServerID(entry,fallback)
        if type(entry)=="table" then
            return entry.serverID
                or entry.ServerID
                or entry.idLobby
                or entry.IDLobby
                or entry.lobbyID
                or entry.LobbyID
                or entry.ID
                or entry.id
                or fallback;
        end

        return fallback;
    end

    local function Join(serverID,reason)
        if joinStarted or serverID==nil then return; end

        joinStarted=true;
        searching=false;

        FASTDB.SetValue("AutoFriendJoin",0);
        FASTDB.SetValue("Heartbeat","FRIEND_LOBBY_FOUND");
        FASTDB.SetValue("FriendServerID",tostring(serverID));

        print(
            "LEK ULTRAFAST v0.3: autojoining friend lobby via "..
            tostring(reason)..
            " serverID="..
            tostring(serverID)
        );

        local ok,err=pcall(function()
            __LEK_STOCK_JOIN__
        end);

        if not ok then
            print("LEK ULTRAFAST v0.3 stock join error: "..tostring(err));

            local ok2,err2=pcall(function()
                Matchmaking.JoinMultiplayerGame(serverID);
            end);

            if not ok2 then
                FASTDB.SetValue("Heartbeat","FRIEND_JOIN_ERROR:"..tostring(err2));
                joinStarted=false;
            end
        end
    end

    local function TryEntry(entry,fallbackID)
        if joinStarted or type(entry)~="table" then return false; end

        local friends=GetFriends();
        local tokens=BuildFriendTokens(friends);

        if next(tokens)==nil then return false; end

        if EntryContainsFriend(entry,tokens,0) then
            local serverID=ExtractServerID(entry,fallbackID);

            if serverID~=nil then
                Join(serverID,"server-list host match");
                return true;
            end
        end

        return false;
    end

    local function TryLobbyID(idLobby)
        if joinStarted or idLobby==nil then return false; end

        local ok,entry=pcall(function()
            return Matchmaking.GetMultiplayerServerEntry(idLobby);
        end);

        if ok and type(entry)=="table" then
            return TryEntry(entry,idLobby);
        end

        return false;
    end

    local function ScanList()
        if joinStarted then return true; end

        local friends=GetFriends();

        local direct=DirectFriendLobby(friends);
        if direct then
            Join(direct,"friend-record");
            return true;
        end

        local ok,games=pcall(function()
            return Matchmaking.GetMultiplayerGameList();
        end);

        if not ok or type(games)~="table" then
            return false;
        end

        for k,v in pairs(games) do
            if joinStarted then return true; end

            if type(v)=="table" then
                TryEntry(v,k);
            else
                TryLobbyID(v);
                TryLobbyID(k);
            end
        end

        return joinStarted;
    end

    Events.MultiplayerGameListUpdated.Add(function(eAction,idLobby,eLobbyType,eSearchType)
        if searching and not joinStarted then
            TryLobbyID(idLobby);
        end
    end);

    Events.MultiplayerGameListComplete.Add(function()
        if searching and not joinStarted then
            ScanList();

            if not joinStarted then
                searching=false;
                FASTDB.SetValue("AutoFriendJoin",0);
                FASTDB.SetValue("Heartbeat","NO_FRIEND_HOST_FOUND_BROWSER_READY");
                print("LEK ULTRAFAST v0.3: no friend host found; staying in browser");
            end
        end
    end);

    local oldShow=ShowHideHandler;

    function ShowHideHandler(hide,init)
        local result;

        if oldShow then
            result=oldShow(hide,init);
        end

        if not hide and get("AutoFriendJoin")==1 then
            searching=true;
            FASTDB.SetValue("Heartbeat","INTERNET_LOBBY_BROWSER_READY");

            print("LEK ULTRAFAST v0.3: checking for friend-hosted lobby");

            if not ScanList() then
                pcall(function()
                    Matchmaking.RefreshInternetGameList();
                end);
            end
        end

        return result;
    end

    ContextPtr:SetShowHideHandler(ShowHideHandler);

    -- Intentionally NO ContextPtr:SetUpdate here.
end
-- LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_END
'@

$lobbyBlock=$lobbyBlock.Replace("__LEK_STOCK_JOIN__",$stockJoinCall)

Upgrade-Lua `
    $lobbyLua `
    "-- LEK_ULTRAFAST_MP_STARTUP_V02_LOBBY_BEGIN" `
    "-- LEK_ULTRAFAST_MP_STARTUP_V02_LOBBY_END" `
    "LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_BEGIN" `
    $lobbyBlock

# Final hard check: v0.3 blocks themselves must not own SetUpdate.
foreach($pair in @(
    @($mainLua,"LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_BEGIN","LEK_ULTRAFAST_MP_STARTUP_V03_MAIN_END"),
    @($selectLua,"LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_BEGIN","LEK_ULTRAFAST_MP_STARTUP_V03_SELECT_END"),
    @($lobbyLua,"LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_BEGIN","LEK_ULTRAFAST_MP_STARTUP_V03_LOBBY_END")
)){
    $txt=[IO.File]::ReadAllText($pair[0])
    $a=$txt.IndexOf($pair[1])
    $b=$txt.IndexOf($pair[2],$a)

    if($a -lt 0 -or $b -lt 0){
        throw "Could not verify v0.3 block in $($pair[0])"
    }

    $block=$txt.Substring($a,$b-$a)

    # Match only an executable Lua call at the beginning of a line.
    # Comments such as "-- Intentionally NO ContextPtr:SetUpdate here."
    # must NOT trigger this safety check.
    if([regex]::IsMatch($block,'(?m)^[ \t]*ContextPtr:SetUpdate[ \t]*\(')){
        throw "SAFETY CHECK FAILED: v0.3 owns an executable SetUpdate call in $($pair[0])"
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " v0.3.1 INSTALL VERIFIED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ultra-Fast v0.2 Lua routing was removed." -ForegroundColor Green
Write-Host "Ultra-Fast v0.3 does NOT overwrite reroll SetUpdate handlers." -ForegroundColor Green
Write-Host ""
Write-Host "Expected reroll path:" -ForegroundColor Cyan
Write-Host "  game -> Main Menu flash -> Multiplayer -> Lobby -> rehost staging" -ForegroundColor Cyan
