# Project State

> **Current operational handoff:** read `AI_HANDOFF.md` first. It is intentionally kept more current and more concise than this historical project summary.

## Known-good baseline

- LEK Core v1.3: working and frozen.
- Development workspace and `T` one-click cycle are the canonical deployment/test path.
- Old Fair AI Trades experimental remnants were cleaned before the new extension baseline.
- Fair Trades current test target: **v1.1.3 SAFE ONE-SESSION NATIVE**.
- RAS v0.8.9 targeted wonder-graphics hotfix remains isolated from the frozen core.

## Fair Trades current direction

The earlier native-value candidate engines proved that the turn-ready retry and direct native trade-offer UI handoff can work, but recreating Civ V pricing in Lua created unnecessary complexity and debugging cost.

Important diagnostic history:

- Early v1.0.x builds established the dedicated runtime/context and eventually proved the event-driven busy-queue retry.
- A native trade offer was successfully displayed in an earlier implementation.
- v1.1.0 used native helper calls while probing multiple AIs. Testing exposed three regressions: an AI could offer its final luxury copy, scratch-deal state could mismatch resources, and closing one offer could reveal queued empty AI trade windows.
- v1.1.1 removed helper probing and enforced spare-luxury safety with one-session presentation.
- v1.1.2 added silent Gold/GPT pre-session valuation, but diagnostics showed `CURRENCY_UNIT_NOT_POSSIBLE` even when an AI visibly had Gold/GPT. The probe was therefore testing the currency API in an invalid context.
- v1.1.3 removes that pre-session currency probe. It selects one AI without opening diplomacy, opens exactly one trade session, seeds a safe spare luxury, and uses Civ V native helper behavior only inside that selected session.

v1.1.3 goals:

- Luxury <-> Luxury, Luxury -> flat Gold, and Luxury -> GPT in both directions.
- Proactive luxury seller retains at least one copy.
- Luxury / Gold / GPT only; no strategics or unrelated treaty items.
- At most one AI trade session per scan / turn.
- No cross-AI scratch-deal snapshot/rebuild.
- No progressive turn slowdown from broad helper/value loops.
- Preserve the proven transient turn-start busy-queue retry and direct `DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER` handoff.

v1.1.3 is a **test target, not yet a known-good Fair Trades release**.

## AI collaboration workflow

GitHub `main` is the shared source of truth.

- ChatGPT currently has repository write access and integrates/pushes testable changes.
- Claude Desktop can independently review the public repository and return findings or a patch.
- `AI_HANDOFF.md` contains the live state, regression guards, and review format.
- `internal/docs/CLAUDE_REVIEW_PROMPT.md` contains a reusable prompt for Claude Desktop.

The preferred loop is:

1. Current code/state lives on GitHub `main`.
2. Claude independently reviews current GitHub source when useful.
3. User brings Claude findings/patch back to ChatGPT.
4. ChatGPT re-checks current source, integrates the smallest safe change, and pushes it.
5. User presses `T`, tests in Civ V, and captures diagnostics if behavior fails.

## Deployment workflow

On the test machine, launch `LEK_DEV_TOOL.bat` and press **T**. The cycle performs:

1. `git pull --ff-only`
2. Frozen Core v1.3 verification
3. Fair Trades install/update
4. Fair Trades verification
5. RAS wonder hotfix install/update
6. RAS wonder hotfix verification

If runtime behavior fails, use Dev Tool option 7 once and upload the diagnostic ZIP.

## Development rule

Prefer the simplest implementation that produces the desired in-game behavior. Keep component-scoped edits small. Diagnose from captured runtime state before redesigning architecture. The frozen core stays untouched unless the issue genuinely belongs to a core component.
