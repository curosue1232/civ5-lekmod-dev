# Project State

## Known-good baseline

- LEK Core v1.3: working and frozen.
- Stable development baseline v1.1: passed on the target machine. Workspace layout cleaned in v1.2; Git first-run connector hardened in v1.2.1; core/runtime behavior unchanged.
- Old Fair AI Trades experimental remnants: cleaned before the new extension baseline.
- Fair Trades clean runtime: v1.0.1 installed/verifiable architecture.

## Fair Trades architecture

- Dedicated `LEKFairTrades.lua` runtime.
- Dedicated `LEKFairTrades.xml` context.
- One stable marked loader in LEKMOD `InGame.lua`.
- No EUI `LeaderHeadRoot.lua` patch in v1.0.x.
- No executable `ContextPtr:SetUpdate` scanner.
- No `GameDataDirty` scanner.
- Native Civ V deal helpers replace the old broad Gold/GPT search loops.
- Hard native-helper work budget.

## RAS issue being investigated

The RAS option that adds bonus natural wonders can produce valid natural-wonder plot/gameplay data while the tile still renders ordinary terrain.

Relevant history:

- RAS MP Bridge v0.8.4 was explicitly an `EarlyMapPhase_WonderGraphics` build.
- RAS v0.8.8 deliberately replays saved RAS runtime state only after the safe post-load boundary to prevent reroll/rehost crashes.
- That late replay is safe for gameplay state but can be too late for Civ V's natural-wonder 3D layout construction.

Preferred fix direction: isolate the minimal graphics-critical natural-wonder phase or a safe layout rebuild instead of moving all RAS initialization earlier again.

## Development rule

Future changes should be committed as small component-scoped edits. The frozen core stays untouched unless the issue genuinely belongs to a core component.
