# AI Development Handoff

This file is the short, current operational handoff for AI-assisted development of the LEKMOD 30.7 extensions in this repository.

## Collaboration roles

- **User / tester:** runs the local `T` one-click update, launches Civilization V, tests behavior, and captures diagnostics with Dev Tool option 7 when needed.
- **ChatGPT:** has GitHub write access for this repository. It integrates fixes, keeps runtime / installer / verifier in sync, reviews diagnostics and commits testable changes to `main`.
- **Claude Desktop:** currently has public read access only. It should independently review the current GitHub source, identify bugs / simpler approaches / regression risks, and return precise findings or a patch for ChatGPT to review and integrate.

GitHub `main` is the shared source of truth for anything the user should test with `T`.

## Current test target

**Fair Trades v1.1.3 — SAFE ONE-SESSION NATIVE**

Primary runtime:

`internal/fair/UI/LEKFairTrades.lua`

Deployment / verification:

- `internal/fair/Install.ps1`
- `internal/fair/Verify.ps1`
- `internal/DevTool.ps1`

### Status

v1.1.3 is the **current test target, not yet proven good**.

The previous v1.1.2 diagnostic proved that the scanner was running and could see human spare luxuries, but its pre-session Gold/GPT currency probe incorrectly returned `CURRENCY_UNIT_NOT_POSSIBLE` even when the AI visibly had Gold and GPT available.

v1.1.3 therefore removed the pre-session currency pricing probe. It now:

1. Selects one eligible AI without opening diplomacy.
2. Opens at most one trade session for that AI.
3. Seeds one safe spare luxury inside the selected AI session.
4. Uses Civ V native trade helper behavior inside that one session to build/equalize the offer.
5. Rejects the result unless it is restricted to Luxury / flat Gold / GPT and preserves each civilization's final luxury copy.
6. Displays the exact native scratch deal in place rather than snapshotting/rebuilding it.

## Proven behavior / infrastructure

- LEK Core v1.3 is the frozen known-good core. Do not modify it for Fair Trades work unless a problem is definitively a core issue.
- The `T` workflow is working: Git pull -> frozen Core verify -> Fair Trades install -> Fair Trades verify -> RAS wonder hotfix install / verify.
- Fair Trades dedicated loader/context architecture works.
- The transient turn-start ready-signal approach works better than the abandoned `ContextPtr:SetUpdate` retry approach on the target multiplayer setup.
- A previous Fair Trades implementation successfully displayed a native Civ V AI trade offer.
- Direct trade-window presentation is possible without opening the default greeting state.

## Known regressions that must not return

1. **No final-copy luxury offers.** A proactive offer must never give away the human's or AI's last available copy of a luxury.
2. **No queued empty AI windows.** Candidate search must not open trade sessions for multiple AIs. One selected AI session maximum per scan / turn.
3. **No stale scratch-deal mismatch.** A displayed item must not transform into another resource when clicked. Avoid cross-AI scratch state and unnecessary snapshot/rebuild behavior.
4. **No progressive turn slowdown.** Avoid broad loops, repeated visible helper calls, or unbounded valuation work.
5. **No strategic resources.** Current Fair Trades scope is luxury resources plus flat Gold / GPT only.
6. **No default greeting interruption.** Offers should use the normal trade-offer UI rather than a generic leader greeting.
7. **Do not modify frozen Core v1.3** for isolated Fair Trades problems.

## Desired Fair Trades behavior

The eventual feature should proactively offer deals that resemble deals the AI would normally accept / propose in manual diplomacy, with relationship affecting frequency somewhat but not making decent trades excessively rare.

Currently desired deal families:

- spare Luxury <-> spare Luxury
- human spare Luxury -> AI flat Gold
- human spare Luxury -> AI GPT
- AI spare Luxury -> human flat Gold
- AI spare Luxury -> human GPT

For proactive luxury offers, the seller should retain at least one copy after the trade.

## Current debugging priority

Test whether **v1.1.3** actually produces valid proactive luxury / Gold / GPT offers without reintroducing the v1.1.0 UI-session bugs.

If it does not, prefer diagnosing the smallest failing API assumption before introducing another large valuation engine.

The design preference is deliberately simple:

> Use Civ V's existing trade behavior where reliable; add the minimum custom logic needed for scheduling, safety, allowed item types, and UI handoff.

## Diagnostic workflow

When a test fails:

1. User runs Dev Tool option `7` once after the failure.
2. Inspect the diagnostic ZIP and runtime DB/log fields before changing architecture.
3. Identify the narrowest failure reason.
4. Make a component-scoped edit.
5. Keep `LEKFairTrades.lua`, `Install.ps1`, and `Verify.ps1` version expectations synchronized.
6. Commit to `main` only when it is ready for the user to pull with `T`.

## Instructions for Claude Desktop

Before reviewing Fair Trades, read this file first, then read the latest versions on `main` of:

- `internal/fair/UI/LEKFairTrades.lua`
- `internal/fair/Install.ps1`
- `internal/fair/Verify.ps1`
- `PROJECT_STATE.md` when historical context is useful

Do not assume older code snippets supplied in chat are current if GitHub differs.

Focus especially on:

- Civ V Lua API misuse or ordering assumptions
- trade scratch-deal lifecycle
- native helper behavior / side effects
- multiplayer event timing
- ways to accomplish the requested behavior with less code
- any path that can open more than one diplomacy session
- last-copy resource safety
- performance / repeated-work hazards

When reporting back, use this structure:

### Findings
For each issue: severity, exact function / code location, why it is wrong or risky, and the smallest safe fix.

### Recommended minimal change
Describe the smallest implementation change that addresses the findings. Avoid broad rewrites unless necessary.

### Patch
If confident, provide a unified diff against the latest GitHub `main`, or provide complete replacement function(s) with exact insertion/replacement locations.

### Regression checklist
Explicitly state whether the proposal preserves all seven items in **Known regressions that must not return** above.

### Test expectations
State what the user should observe in-game and what diagnostic fields should change if the fix works.

## Instructions for ChatGPT when receiving Claude findings

- Re-read current GitHub source before integrating Claude's suggestion.
- Treat Claude's output as an independent review, not automatically correct.
- Prefer the smallest change that survives both reviews.
- Push the integrated test build to GitHub so the user continues using `T` rather than manual file replacement.
- Update this handoff whenever the active test target or proven state materially changes.
