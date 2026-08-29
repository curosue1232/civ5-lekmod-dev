RAS MP BRIDGE v0.8.9 - TARGETED WONDER GRAPHICS HOTFIX
=======================================================

FOUNDATION
----------
This is an isolated hotfix on top of the frozen LEK Core v1.3 stack (specifically
RAS MP Bridge v0.8.8 Restart Settings Replay). It requires v0.8.8 to already be
installed and verified; Install.ps1 runs internal/CoreVerify.ps1 as a preflight
and refuses to proceed if the v0.8.8 runtime markers are missing.

INSTALL
-------
1. Keep Civilization V closed.
2. Run internal/ras-wonder/Install.ps1 (or use internal/InstallAll.ps1 to install
   everything in the correct order).
3. Run internal/ras-wonder/Verify.ps1 to re-check it later.

PROBLEM IT FIXES
----------------
On a reroll, EUI's LoadScreen can place natural wonders during the Dawn-of-Man
pre-render window before the safe v0.8.8 full map replay runs later. Without this
hotfix, wonders could be placed twice (once early, once by the v0.8.8 replay),
producing duplicate/incorrect wonder graphics.

WHAT IT TOUCHES
----------------
Existing game files touched by install, both in-place marked-block patches (no new
runtime files are shipped):
  Assets\DLC\LEKMOD_V30.7\UI\InGame.lua
    - removes a superseded experimental v0.8.9 block if present (cleanup only)
  Assets\UI\FrontEnd\Multiplayer\GTAS_StartGame.lua
    - GTAS_MP_V089_WONDER_RUNTIME_BEGIN/END: wraps PlaceWonders/DisableOtherWonders
      so the same reroll seed's wonders are never placed/disabled twice
  Assets\DLC\UI_bc1\GameSetup\LoadScreen.lua
    - GTAS_MP_V089_REROLL_WONDER_LOADSCREEN_BEGIN/END: on a detected reroll bypass,
      places only natural wonders during the Dawn-of-Man pre-render phase

BEHAVIOR
--------
- Fresh/manual games: unchanged. They keep the existing v0.8.7.1 early full map
  phase; this hotfix adds no new mutation path for them.
- Rerolled games: natural wonders are placed once during Dawn-of-Man pre-render;
  the full v0.8.8 replay later skips re-placing/re-disabling wonders for the same
  seed, using MapModData.GTAS_MP_V089_WONDERS_DONE_SEED as the guard.

DIAGNOSTICS
-----------
CAPTURE_DEV_STATE.bat (internal/CaptureState.ps1) captures the touched files.
COLLECT_RAS_V088_RESTART_REPLAY_DIAGNOSTIC.ps1 (under internal/core/RAS/) remains
the canonical RAS-level diagnostic if the base v0.8.8 layer itself is in question.

UNINSTALL
---------
internal/ras-wonder/Uninstall.ps1 removes only this hotfix's marked blocks. It
does not touch or uninstall the underlying RAS v0.8.8 base.
