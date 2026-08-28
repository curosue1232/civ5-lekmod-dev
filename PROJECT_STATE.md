# Project State

This file is the **standalone current operational handoff** for the Civ V LEKMOD development project. If an external reviewer can read only one file from the repository, this is the file to use. Do not require `AI_HANDOFF.md` or any other newly-added file to understand the current state.

## Collaboration roles

- **User / tester:** runs the local `T` one-click update, launches Civilization V, tests behavior, and captures diagnostics with Dev Tool option 7 when needed.
- **ChatGPT:** has GitHub write access for this repository. It integrates fixes, keeps runtime / installer / verifier in sync, reviews diagnostics, and commits testable changes to `main`.
- **Claude Desktop:** currently has public read access only. It should independently review the current GitHub source, identify bugs / simpler approaches / regression risks, and return precise findings or a patch for ChatGPT to review and integrate.

GitHub `main` is the shared source of truth for anything the user should test with `T`.

## Known-good baseline

- LEK Core v1.3 is working and frozen.
- Development workspace and `T` one-click cycle are the canonical deployment/test path.
- Old Fair AI Trades experimental remnants were cleaned before the new extension baseline.
- RAS v0.8.9 targeted wonder-graphics hotfix remains isolated from the frozen core.
- Fair Trades dedicated loader/context architecture works.
- The transient turn-start ready-signal approach works better than the abandoned `ContextPtr:SetUpdate` retry approach on the target multiplayer setup.
- A previous Fair Trades implementation successfully displayed a native Civ V AI trade offer.
- Direct trade-window presentation is possible without opening the default greeting state.

## Current Fair Trades test target

**Fair Trades v1.1.3 — SAFE ONE-SESSION NATIVE**

Primary runtime:

`internal/fair/UI/LEKFairTrades.lua`

Deployment / verification:

- `internal/fair/Install.ps1`
- `internal/fair/Verify.ps1`
- `internal/DevTool.ps1`

v1.1.3 is the **current test target, not yet proven good**.

## Important diagnostic history

- Early v1.0.x builds established the dedicated runtime/context and eventually proved the event-driven busy-queue retry.
- A native trade offer was successfully displayed in an earlier implementation.
- v1.1.0 used native helper calls while probing multiple AIs. Testing exposed three regressions:
  1. an AI could offer its final luxury copy,
  2. scratch-deal state could mismatch resources,
  3. closing one offer could reveal queued empty AI trade windows.
- v1.1.1 removed helper probing and enforced spare-luxury safety with one-session presentation.
- v1.1.2 added silent Gold/GPT pre-session valuation, but diagnostics showed `CURRENCY_UNIT_NOT_POSSIBLE` even when an AI visibly had Gold/GPT. The currency probe was therefore testing the trade API in an invalid context.
- v1.1.3 removes that pre-session currency probe. It now:
  1. selects one eligible AI without opening diplomacy,
  2. opens at most one trade session for that AI,
  3. seeds one safe spare luxury inside the selected AI session,
  4. uses Civ V native trade helper behavior only inside that one session,
  5. rejects the result unless it is restricted to Luxury / flat Gold / GPT and preserves each civilization's final luxury copy,
  6. displays the exact native scratch deal in place rather than snapshotting/rebuilding it.

## Desired Fair Trades behavior

The eventual feature should proactively offer deals that resemble deals the AI would normally accept / propose in manual diplomacy, with relationship affecting frequency somewhat but not making decent trades excessively rare.

Currently desired deal families:

- spare Luxury <-> spare Luxury
- human spare Luxury -> AI flat Gold
- human spare Luxury -> AI GPT
- AI spare Luxury -> human flat Gold
- AI spare Luxury -> human GPT

For proactive luxury offers, the seller should retain at least one copy after the trade.

## Known regressions that must not return

1. **No final-copy luxury offers.** A proactive offer must never give away the human's or AI's last available copy of a luxury.
2. **No queued empty AI windows.** Candidate search must not open trade sessions for multiple AIs. One selected AI session maximum per scan / turn.
3. **No stale scratch-deal mismatch.** A displayed item must not transform into another resource when clicked. Avoid cross-AI scratch state and unnecessary snapshot/rebuild behavior.
4. **No progressive turn slowdown.** Avoid broad loops, repeated visible helper calls, or unbounded valuation work.
5. **No strategic resources.** Current Fair Trades scope is luxury resources plus flat Gold / GPT only.
6. **No default greeting interruption.** Offers should use the normal trade-offer UI rather than a generic leader greeting.
7. **Do not modify frozen Core v1.3** for isolated Fair Trades problems.

## Current debugging priority

Test whether **v1.1.3** actually produces valid proactive luxury / Gold / GPT offers without reintroducing the v1.1.0 UI-session bugs.

If it does not, diagnose the smallest failing Civ V API assumption before introducing another large valuation engine.

## Deployment workflow

On the test machine, launch `LEK_DEV_TOOL.bat` and press **T**. The cycle performs:

1. `git pull --ff-only`
2. Frozen Core v1.3 verification
3. Fair Trades install/update
4. Fair Trades verification
5. RAS wonder hotfix install/update
6. RAS wonder hotfix verification

If runtime behavior fails, use Dev Tool option 7 once and upload the diagnostic ZIP.

## External AI reviewer instructions

If you are Claude Desktop or another external reviewer, start with this file and then read the latest `main` versions of:

- `internal/fair/UI/LEKFairTrades.lua`
- `internal/fair/Install.ps1`
- `internal/fair/Verify.ps1`

Do not assume code from an older chat message is still current if GitHub differs.

Act as an independent reviewer, not as a wholesale rewriter. Look specifically for:

- Civilization V Lua API mistakes or incorrect parameter/order assumptions,
- scratch-deal lifecycle problems,
- native trade-helper side effects,
- multiplayer event/timing problems,
- any code path that could open/queue multiple diplomacy windows,
- final-copy luxury safety failures,
- unnecessary complexity or a simpler native-game solution,
- performance problems that could worsen turn time,
- verifier assumptions that do not match the runtime.

Respect every item under `Known regressions that must not return`.

Return the review in these sections:

### Findings
List concrete issues in severity order. For each one include the exact function or code location, why it is wrong/risky, and the smallest safe fix.

### Recommended minimal change
Describe the smallest coherent change you recommend. Do not propose a broad rewrite unless the current architecture genuinely cannot work.

### Patch
If confident, provide a unified diff against the latest GitHub `main`. If a unified diff is impractical, provide complete replacement function(s) and exact replacement locations.

### Regression checklist
Check each known regression guard above and say whether the proposed change preserves it.

### Test expectations
Describe exactly what should happen in-game if the fix works and which diagnostics/log fields would best prove it.

Do not claim you pushed or committed anything. Provide a review/patch for ChatGPT to inspect and integrate into GitHub.

## Development rule

Prefer the simplest implementation that produces the desired in-game behavior. Keep component-scoped edits small. Diagnose from captured runtime state before redesigning architecture. The frozen core stays untouched unless the issue genuinely belongs to a core component.
