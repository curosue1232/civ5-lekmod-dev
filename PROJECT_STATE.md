# Project State

## Known-good baseline

- LEK Core v1.3: working and frozen.
- Stable development baseline v1.1: passed on the target machine. Workspace layout cleaned in v1.2; Git first-run connector hardened in v1.2.1; core behavior unchanged.
- Old Fair AI Trades experimental remnants: cleaned before the new extension baseline.
- Fair Trades clean runtime is under active validation; current test target is v1.0.4.
- RAS v0.8.9 targeted wonder-graphics hotfix is isolated from the frozen core and is available through Dev Tool options 9-11.

## Fair Trades architecture

- Dedicated `LEKFairTrades.lua` runtime.
- Dedicated `LEKFairTrades.xml` context.
- One stable marked loader in LEKMOD `InGame.lua`.
- No EUI `LeaderHeadRoot.lua` patch in v1.0.x.
- No executable `ContextPtr:SetUpdate` in v1.0.4.
- `SerialEventGameDataDirty` is not a deal scanner: v1.0.4 subscribes only transiently after a busy `ActivePlayerTurnStart`, performs no deal work while the queue is busy, and removes the callback immediately when the queue clears or the turn ends.
- Native Civ V deal helpers replace the old broad Gold/GPT search loops.
- Hard native-helper work budget: maximum 8 helper calls per local human turn.

## Fair Trades diagnostic history

- v1.0/v1.0.1 loaded successfully but stopped at `TURN_START_MESSAGE_QUEUE_BUSY` and never evaluated AIs.
- v1.0.2 added a bounded `SetUpdate` queue retry. Diagnostic proved it reached `TURN_START_MESSAGE_QUEUE_BUSY_RETRY_ARMED`, but the retry never ticked.
- v1.0.3 made the empty context active, but the next diagnostic again ended at `TURN_START_MESSAGE_QUEUE_BUSY_RETRY_ARMED` with no retry heartbeat, eligible-AI count, luxury count, or helper calls. The child context still did not receive update ticks on the target MP setup.
- v1.0.4 removes `SetUpdate` entirely and uses a transient event-driven turn-ready signal. The actual runtime is now canonical source in GitHub; the obsolete install-time runtime patcher was removed.

## RAS natural-wonder graphics diagnosis

The RAS option that adds bonus natural wonders can produce valid natural-wonder plot/gameplay data while the tile still renders ordinary terrain.

Latest capture confirms the failing case is a reroll replacement:

- RAS bonus-wonder SlotData is present for the human player.
- v0.8.7.2 replacement loading bypass is active during LoadScreen.
- v0.8.8 reports `RUNTIME_RAS_REPLAY_OK` later, after the safe post-load boundary.
- The old v0.8.4 early wonder-graphics phase is absent from the installed InGame files.

This matches the documented v0.8.8 graphics trade-off: feature/gameplay state can be correct while natural-wonder 3D world art is stale because placement happens after world graphics construction.

## RAS v0.8.9 targeted hotfix

- Fresh/manual launches restore the proven early full RAS map phase.
- Reroll/rehost replacements keep the crash-sensitive full RAS replay at the v0.8.8 safe late boundary.
- On rerolls, only `DisableOtherWonders()` + `PlaceWonders()` run during the early graphics-critical phase.
- Seed guards wrap the later calls so the v0.8.8 full replay does not duplicate/remove the already placed wonders.
- Diagnostics record `WonderGraphicsHeartbeat`, `WonderGraphicsMode`, and seed state.
- This is a placement-timing fix; an already loaded map cannot be expected to retroactively rebuild missing natural-wonder world art. Validate with a new game/reroll after installation.

## Development rule

Future changes should be committed as small component-scoped edits. The frozen core stays untouched unless the issue genuinely belongs to a core component.
