RAS MP BRIDGE v0.8.8
RESTART SETTINGS REPLAY

WHAT THE v0.8.7.2 DIAGNOSTIC PROVED
===================================
The crash fix is now working all the way through the replacement load:

  StickyRerollHeartbeat
    = MPSETUP_BYPASS_LATCHED

  StickyRerollLoadHeartbeat
    = LOADSCREEN_BYPASS_ACTIVE

  StickyRerollInGameHeartbeat
    = SEQUENCE_INIT_BYPASS_ACTIVE

So RAS remained bypassed through:
  rehost
  staging
  LoadScreen
  engine game initialization

and the replacement reached SequenceGameInitComplete successfully.

WHY THE RAS SETTINGS WERE MISSING
=================================
That stable bypass deliberately prevented the saved RAS runtime layer from executing.

Reroll/Rehost v0.21 already preserves the normal PreGame layer, including:
  map script
  world size
  game speed
  era
  max turns
  minor civ count
  victories
  GameOptions (GO_...)
  map-script options (MO_...)
  civilizations / teams / AI slots

What it cannot preserve by itself are RAS changes performed AFTER map generation:

  extra starting units
  start visibility
  RAS terrain placement
  RAS feature placement
  Natural Wonder placement
  RAS resource placement
  game-level RAS runtime changes such as Disable Nukes
  other InitPlayers / InitMap bonuses

v0.8.8 DESIGN
=============
The crash-safe pipeline remains unchanged:

  REROLL
  -> RAS BYPASS ON
  -> v0.21 owns PreGame/rehost
  -> replacement lobby
  -> LoadScreen with ZERO RAS
  -> Civ V finishes engine initialization
  -> SequenceGameInitComplete

ONLY AFTER THAT proven-safe boundary, v0.8.8 runs the saved RAS runtime layer:

  InitMap()
  InitGame()
  InitPlayers()

This is the same late runtime phase used by the working manual RAS game.

DETERMINISTIC RESTART SEED
==========================
Every machine already receives the same six-digit v0.21 JoinToken.

v0.8.8 uses that token as the RAS runtime seed for the replacement.

That means:
  host and clients replay the same saved RAS configuration
  every reroll gets a new RAS placement seed
  no RAS data packet needs to be sent during the dangerous rehost phase

INSTALL
=======
Keep the current working stack installed:

  RAS v0.8.7.1
  RAS v0.8.7.2 Sticky Reroll Bypass
  Reroll v0.21.1
  Reroll v0.21.2

Close Civ V.

Run:
  INSTALL_RAS_V088_RESTART_SETTINGS_REPLAY.bat

Then:
  VERIFY_RAS_V088_RESTART_SETTINGS_REPLAY.bat

TEST
====
Use an obvious RAS configuration, such as:
  extra Worker
  extra Scout
  starting visibility
  a resource/terrain bonus
  a Natural Wonder bonus

Start the original game and confirm the settings.

Reroll.

The replacement should:
  1. load without the old crash
  2. keep the normal map/game/lobby settings
  3. replay the RAS starting bonuses after safe load
  4. keep the AI layout
  5. use a new deterministic RAS seed

NOTE ON NATURAL WONDER GRAPHICS
===============================
Natural Wonder GAMEPLAY placement will be replayed.

The model/art can still appear as ordinary terrain because v0.8.8 intentionally
applies InitMap at the late, crash-safe phase. Moving it back into the early LoadScreen
phase is what previously destabilized loading.

If the game loads but a particular RAS bonus is still missing, run:
  COLLECT_RAS_V088_RESTART_REPLAY_DIAGNOSTIC.bat
