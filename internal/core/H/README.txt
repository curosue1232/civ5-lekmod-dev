LEKMOD 30.7 - HOST INSTANT START v0.1

PURPOSE
=======
Lets the multiplayer HOST start a game immediately from the Staging Room.

NORMAL CIV V:
  Everyone clicks Ready
  -> Civ V detects everyone ready
  -> countdown begins
  -> game launches

WITH THIS PATCH:
  Nobody else needs to Ready
  -> host clicks START GAME NOW
  -> game launches immediately

NO COUNTDOWN.

SAFETY CHECKS KEPT
==================
The Start Game Now button remains disabled until:
  - every current player has actually finished connecting
  - team setup is valid
  - the map supports the current number of active players

READY STATUS IS NOT CHECKED.

This is intentional for use with the MP Reroll/Rehost auto-join system:
returning clients can enter the replacement lobby and the host can launch as soon
as their connections finish, without waiting for each person to manually ready.

COMPATIBILITY
=============
Compatible with:
  Lekmod 30.7
  EUI
  MP Reroll/Rehost v0.21

Install this AFTER the reroll/rehost package.

Only the HOST needs this patch.
It is harmless if every player installs it because the button is host-only.

INSTALL
=======
1. Close Civ V.
2. If using Reroll/Rehost v0.21, install/verify v0.21 FIRST.
3. Run INSTALL_HOST_INSTANT_START_V01.bat
4. Run VERIFY_HOST_INSTANT_START_V01.bat
5. Start Civ V.

In a hosted staging lobby the host should see:

    START GAME NOW

Other players can remain unready.

Clicking START GAME NOW directly uses Civ V's normal:
    Matchmaking.LaunchMultiplayerGame()

No countdown is started.

UNINSTALL ORDER
===============
If using both packages:

1. Uninstall HOST INSTANT START first.
2. Then uninstall/change Reroll/Rehost.

That preserves the correct nested backups.
