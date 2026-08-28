# Project State

## Known-good baseline

- LEK Core v1.3: working and frozen.
- Stable development baseline v1.1: passed on the target machine. Workspace layout cleaned in v1.2; Git first-run connector hardened in v1.2.1; core behavior unchanged.
- Old Fair AI Trades experimental remnants: cleaned before the new extension baseline.
- Fair Trades clean runtime is under active validation; current test target is v1.0.3.

## Fair Trades architecture

- Dedicated `LEKFairTrades.lua` runtime.
- Dedicated `LEKFairTrades.xml` context.
- One stable marked loader in LEKMOD `InGame.lua`.
- No EUI `LeaderHeadRoot.lua` patch in v1.0.x.
- No `GameDataDirty` scanner.
- Native Civ V deal helpers replace the old broad Gold/GPT search loops.
- Hard native-helper work budget.
- A single bounded `ContextPtr:SetUpdate` is allowed only while the MP turn-start message queue is busy; it self-removes on queue clear or a hard 10-second timeout.

## Fair Trades diagnostic history

- v1.0/v1.0.1 loaded successfully but stopped at `TURN_START_MESSAGE_QUEUE_BUSY` and never evaluated AIs.
- v1.0.2 added a bounded queue retry. Diagnostic proved it reached `TURN_START_MESSAGE_QUEUE_BUSY_RETRY_ARMED`, but the retry never ticked.
- Root cause for v1.0.2: `LEKFairTrades` was hidden both in Lua and XML. On the target MP setup, the hidden context did not receive update ticks.
- v1.0.3 makes the context active but empty (no visual controls), keeps the bounded retry, and records `OfferRetryHeartbeat` so the next capture proves whether the update handler ticks and the queue clears.

## RAS issue being investigated

The RAS option that adds bonus natural wonders can produce valid natural-wonder plot/gameplay data while the tile still renders ordinary terrain.

Relevant history:

- RAS MP Bridge v0.8.4 was explicitly an `EarlyMapPhase_WonderGraphics` build.
- RAS v0.8.8 deliberately replays saved RAS runtime state only after the safe post-load boundary to prevent reroll/rehost crashes.
- That late replay is safe for gameplay state but can be too late for Civ V's natural-wonder 3D layout construction.

Preferred fix direction: isolate the minimal graphics-critical natural-wonder phase or a safe layout rebuild instead of moving all RAS initialization earlier again.

## Development rule

Future changes should be committed as small component-scoped edits. The frozen core stays untouched unless the issue genuinely belongs to a core component.
