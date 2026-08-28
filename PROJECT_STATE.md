# Project State

## Known-good baseline

- LEK Core v1.3: working and frozen.
- Development workspace and `T` one-click cycle are the canonical deployment/test path.
- Old Fair AI Trades experimental remnants were cleaned before the new extension baseline.
- Fair Trades current test target: **v1.1.0 SIMPLE NATIVE**.
- RAS v0.8.9 targeted wonder-graphics hotfix remains isolated from the frozen core.

## Fair Trades current direction

The earlier native-value candidate engine proved that the turn-ready retry and direct native trade-offer UI handoff work, but recreating Civ V pricing in Lua added unnecessary complexity and debugging cost.

v1.1.0 deliberately simplifies the engine:

- Pick an eligible AI based on the existing relationship schedule.
- Seed a useful luxury trade.
- Use Civ V native trade helpers (`UI.DoWhatWillAIGive`, `UI.DoWhatDoesAIWant`, with `UI.DoEqualizeDealWithHuman` as fallback) to build the price.
- Apply only a small final safety filter: luxury resources + Gold/GPT only, no third-party/unsupported items, both sides must give something, and the human never gives away the last copy of a luxury.
- Maximum four native build attempts per local human turn.
- No custom `GetDealMyValue` / `GetDealTheyreValue` pricing loops.
- Preserve the proven turn-start busy-queue retry and direct `DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER` handoff.
- Preserve the message-scoped EUI luxury-offer bridge.

## Deployment workflow

GitHub `main` is the source of truth. On the test machine, launch `LEK_DEV_TOOL.bat` and press **T**. The cycle performs:

1. `git pull --ff-only`
2. Frozen Core v1.3 verification
3. Fair Trades install/update
4. Fair Trades verification
5. RAS wonder hotfix install/update
6. RAS wonder hotfix verification

If runtime behavior fails, use Dev Tool option 7 once and upload the diagnostic ZIP.

## Development rule

Prefer the simplest implementation that produces the desired in-game behavior. Keep component-scoped edits small. The frozen core stays untouched unless the issue genuinely belongs to a core component.
