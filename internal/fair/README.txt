LEKMOD 30.7 FAIR TRADES v1.0 - CLEAN DEVELOPMENT BUILD
=========================================================

FOUNDATION
----------
This package is the LEK Stable Development Base v1.1 plus one isolated Fair
Trades extension. The frozen LEK Core v1.3 files are copied unchanged.

INSTALL
-------
1. Keep Civilization V closed.
2. Extract the ZIP to a short path.
3. Run INSTALL_FAIR_TRADES.bat.
4. Run VERIFY_FAIR_TRADES.bat if you want to re-check it later.

Do NOT rerun INSTALL_ALL_CORE_MODS.bat unless the core verifier says the frozen
core stack itself is broken. Fair Trades updates are independent of core.

V1.0 ARCHITECTURE
-----------------
Existing game files touched by install: ONE
  Assets\DLC\LEKMOD_V30.7\UI\InGame.lua

Stable loader block:
  -- LEK_EXT_FAIR_TRADES_LOADER_BEGIN
  ContextPtr:LoadNewContext("LEKFairTrades")
  -- LEK_EXT_FAIR_TRADES_LOADER_END

Owned files:
  LEKFairTrades.lua
  LEKFairTrades.xml

EUI LeaderHeadRoot.lua is NOT patched in v1.0. The existing Events.AILeaderMessage
path is used as the bridge into the normal EUI trade screen.

DEAL ENGINE
-----------
This is deliberately different from v0.3.5.

v0.3.5 repeatedly tested many Gold/GPT amounts and exhausted its 80-evaluation
budget. v1.0 does not search prices. It seeds one spare luxury and asks Civ V's
native deal AI either:
  UI.DoWhatWillAIGive()
or
  UI.DoWhatDoesAIWant()

The native result is then filtered. v1.0 accepts only:
  - luxury resources
  - flat Gold
  - Gold per turn

Strategic resources, cities, third-party items, votes, and other complicated
items are rejected in v1.0. This keeps the first clean pipeline easy to prove.

FAIRNESS
--------
The AI's native helper builds the counter-price, so its normal deal AI/relationship
valuation is used instead of our old guessed price search.

On top of that, a simple human-facing gate values:
  luxury = 240
  flat Gold = face value
  GPT = GPT * duration
and only shows an offer when AI-gives value >= human-gives value.

Neither side is seeded with its last copy of a luxury, and any returned deal that
would trade a last luxury is rejected.

RELATIONSHIPS
-------------
Relationship modifies proactive offer FREQUENCY, not price:
  Friendly / Afraid : roughly every 2 turns when a legal deal exists
  Neutral           : roughly every 3 turns
  Guarded           : roughly every 5 turns
  Hostile/Deceptive/War: no generated proactive offer

The per-AI offsets are staggered, and only one generated offer can be shown to the
local human in a turn.

PERFORMANCE
-----------
Hard maximum: 8 native helper calls for the entire human turn.
There is:
  - no ContextPtr:SetUpdate scanner
  - no SerialEventGameDataDirty scanner
  - no exhaustive Gold/GPT amount loop
  - no background failure retry loop

MULTIPLAYER / ALL HUMANS
------------------------
The runtime acts for Game.GetActivePlayer() only. Therefore every human receives
AI offers on their own client/turn when this package is installed on every human
player's Civ V installation, matching the rest of the MP core stack deployment.

DIAGNOSTICS
-----------
CAPTURE_DEV_STATE.bat remains the canonical diagnostic. In this package it also
copies the stable LEK_FAIR_TRADES-1.db state database when found. Upload that one
ZIP if an offer does not appear or if the UI does not open correctly.

UNINSTALL
---------
UNINSTALL_FAIR_TRADES.bat removes only the stable Fair Trades loader/runtime.
It never restores an old whole-file backup and does not uninstall the core stack.


V1.0.1 VERIFIER FIX
-------------------
No runtime behavior changed from v1.0. The verifier now distinguishes executable
ContextPtr:SetUpdate / GameDataDirty registrations from documentation comments.
If v1.0 already wrote the files, running VERIFY_FAIR_TRADES.bat from v1.0.1 is enough.
