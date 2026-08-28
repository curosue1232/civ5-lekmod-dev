# Claude Desktop Review Prompt

Copy/paste the prompt below into Claude Desktop when you want an independent review of the current Civ V mod state.

---

Read the latest `main` branch of this public GitHub repository:

`https://github.com/curosue1232/civ5-lekmod-dev`

Start with `AI_HANDOFF.md`. Treat it as the current operational handoff.

Then read the latest versions of the files it identifies, especially:

- `internal/fair/UI/LEKFairTrades.lua`
- `internal/fair/Install.ps1`
- `internal/fair/Verify.ps1`

Do not assume code from an older chat message is still current if GitHub differs.

Your job is to act as an independent reviewer, not to rewrite everything. Look for:

- Civilization V Lua API mistakes or incorrect parameter/order assumptions
- scratch-deal lifecycle problems
- native trade-helper side effects
- multiplayer event/timing problems
- any code path that could open/queue multiple diplomacy windows
- final-copy luxury safety failures
- unnecessary complexity or a simpler native-game solution
- performance problems that could worsen turn time
- verifier assumptions that do not match the runtime

Respect every item under `Known regressions that must not return` in `AI_HANDOFF.md`.

Return your answer in exactly these sections:

## Findings
List concrete issues in severity order. For each one include the exact function or code location, why it is wrong/risky, and the smallest safe fix.

## Recommended minimal change
Describe the smallest coherent change you recommend. Do not propose a broad rewrite unless the current architecture genuinely cannot work.

## Patch
If you are confident, provide a unified diff against the latest GitHub `main`. If a unified diff is impractical, provide complete replacement function(s) and exact replacement locations.

## Regression checklist
Check each known regression guard from `AI_HANDOFF.md` and say whether your change preserves it.

## Test expectations
Describe exactly what should happen in-game if the fix works and which diagnostics/log fields would best prove it.

Do not claim you pushed or committed anything. You are providing a review/patch for ChatGPT to inspect and integrate into GitHub.

---
