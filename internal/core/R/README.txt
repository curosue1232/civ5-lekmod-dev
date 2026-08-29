LEKMOD 30.7 MP REROLL / REHOST v0.21
AUTO-JOIN CLIENT TEST

WHAT IS ALREADY PROVEN
======================
v0.20 successfully makes the HOST:
  running game -> automatic rehost -> new staging lobby

v0.21 keeps that host route and adds automatic client rejoining.

HOW AUTO-JOIN WORKS
===================
1. Host presses REROLL MAP / REHOST.
2. Host generates a six-digit reroll token.
3. Host sends the token to every old client through Civ V's existing in-game chat network.
4. Each client saves the token locally BEFORE leaving the old game.
5. Host automatically creates the replacement lobby with a unique name:
       LEK-REROLL-123456
6. Each client automatically goes:
       Main Menu
       -> Multiplayer
       -> Internet/LAN
       -> Lobby browser
7. The client refreshes the browser repeatedly.
8. It examines Civ V's server entries until it finds the exact unique token.
9. It calls Civ V's STOCK multiplayer join function using serverEntry.serverID.
10. On success the client should enter the same replacement Staging Room as the host.

WHY THE UNIQUE NAME IS USED
===========================
The exposed Civ V Lua API gives us:
  Matchmaking.GetMultiplayerGameList()
  Matchmaking.GetMultiplayerServerEntry(idLobby)
  Matchmaking.JoinMultiplayerGame(serverID)

A unique reroll token avoids joining the wrong public lobby.

IMPORTANT PRIVATE-GAME NOTE
===========================
For this v0.21 test, the replacement Internet lobby is made PUBLIC.
A private lobby may not appear in the browser, which would make automatic discovery
impossible through the exposed server-list API.

INSTALL
=======
Install v0.21 on EVERY human player's computer.

1. Close Civ V.
2. Run INSTALL_V021.bat.
   It automatically restores v0.20/v0.19 backups first.
3. Run VERIFY_V021.bat.
4. It must say:
       ALL v0.21 PATCHES PRESENT.
5. Start the game normally and test.

EXPECTED CLIENT FLOW
====================
Old running game
 -> Main Menu flashes
 -> Multiplayer Select flashes
 -> Internet Lobby browser
 -> searches for LEK-REROLL-XXXXXX
 -> automatically joins
 -> replacement Staging Room

The client search retries for 45 seconds because the host's new Steam lobby may take
a few seconds to become visible.

IF A CLIENT FAILS
=================
On the CLIENT computer run:
    FIND_V021_DATABASE.bat

Upload:
    LEK_MP_REROLL_REHOST-21.db

Useful Heartbeat values include:
  CLIENT_INGAME_MARKER_OK
  CLIENT_MAINMENU_OK
  CLIENT_MULTIPLAYER_SELECT_OK
  CLIENT_LOBBY_BROWSER_OK
  CLIENT_FOUND_TARGET_SERVER
  CLIENT_STAGING_COMPLETE

This tells exactly whether failure is:
  receiving the reroll token,
  routing to the browser,
  finding the replacement server,
  calling the join API,
  or reaching staging.

SLOT NOTE
=========
This version focuses on automatic joining the correct replacement lobby.
If multiple returning players auto-join successfully but Civ V assigns one of them to
the wrong old civilization slot, report that separately; the old player ID is already
saved so a slot-restoration pass can be added without changing the rehost/join system.
