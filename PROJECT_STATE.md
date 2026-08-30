# Project State

> **CURRENT STATUS — 2026-08-29 18:03 PDT:** The older “Automate does not drive production/research/policy” investigation below is historical and solved. The authoritative operational state is the top section of `AI_HANDOFF.md`. The installed uncommitted build uses a two-phase driver with 0.7-second checks and 1.7-second modal handoffs; production, research, and policy passed in-game. Claude's temporary Policy/CityView/TechTree diagnostic prints have been removed from source and the two cleaned components are now installed; direct inspection confirms the live files are clean. `LEK_DEV_STATE_20260829_093719.zip` is a successful post-fix Enhance Religion trace, though its `Active=0` value means the tester must confirm whether the sequence was fully hands-free. The newer combat-unit enemy/barbarian/frontier-guard patch is installed after correcting a Lua helper-order scope bug. Frozen Core/RAS is unchanged, Fair Trades v1.2.5 is stable, and `internal/VerifyAll.ps1` passes the entire installed stack. The next test is a hands-free Found Religion run. Do not run `T`, commit, or push before final in-game confirmation and user approval.

This file is the **standalone current operational handoff** for the Civ V LEKMOD development project. If an external reviewer can read only one file from the repository, this is the file to use. See also `AI_HANDOFF.md`, which carries the same information in a slightly different structure and is kept in sync with this file.

## Collaboration roles

- **User / tester:** runs the install/verify cycle, launches Civilization V, tests behavior, and captures diagnostics with `internal/CaptureState.ps1` (`CAPTURE_DEV_STATE.bat`) when needed. The user works with both Claude and ChatGPT on this repo at different times — either assistant should treat this file as authoritative over any stale assumption from its own prior context.
- **AI (Claude or ChatGPT):** works directly on this repository — reviews code and diagnostics, writes patches, runs the installer/verifier, and commits/pushes to `main` with the user's confirmation before each push. There is no separate integrator; this replaced an earlier workflow where a different assistant held GitHub write access.

GitHub `main` is the shared source of truth for anything the user should test.

## ACTIVE FOCUS: Space Autopilot ("Space" + "Automate") — mid-debugging

This is the current priority, ahead of Fair Trades below (which is stable and not presently being worked on).

**What it is:** pressing Space during a game blows through the current turn — opens whatever screen is blocking end-turn and makes a reasonable (not optimal) choice, one decision per press, falling back to Skip/Fortify when nothing better applies. An "AUTOMATE" button was added to the in-game Escape menu (all three copies of `GameMenu.xml` — base, Gods & Kings, Brave New World — since the loaded one depends on active DLC) that repeats Space's action on a 0.5s timer until any key is pressed.

**Manual Space presses work correctly on every screen, confirmed repeatedly.** The open bug is that **Automate does not reliably trigger the same logic on screens other than the world-view turn-advance itself.**

### Mechanism

- Space: each screen is its own native Lua file wrapped with a `LEKSpaceChooseX()` function bound to `wParam == Keys.VK_SPACE` in that file's own `InputHandler`. Solid, proven, no outstanding bugs.
- Automate: a shared UserData flag (`Modding.OpenUserData("LEK_SPACE_AUTOMATE",1)`, key `Active`) that `GameMenu.lua`'s button writes and `ActionInfoPanel.lua` polls on its own `ContextPtr:SetUpdate` (0.5s cadence). Each tick, `ActionInfoPanel.lua` broadcasts `LuaEvents.LEKSpaceAutomateTick()` (a cross-file pub/sub event, confirmed to work natively elsewhere in the base game) so every other automated file's registered listener (`LuaEvents.LEKSpaceAutomateTick.Add(function() if not ContextPtr:IsHidden() then pcall(LEKSpaceChooseX) end end)`) can act if it's the screen currently showing, then calls `LEKSpaceActivateOrSkip()` directly for world-view logic.

### Current bug (unsolved as of this handoff)

- CityView (production): does not act at all, even on a manually-opened, long-settled screen — not just a just-opened-timing issue.
- SocialPolicyPopup (policy): partially works — a selection happens (opens the native confirm dialog) but never advances past confirm.
- TechTree (research): reported broken, not yet re-tested since the ordering fix below.

Already tried, did not fully fix it: (1) building the broadcast+listener mechanism at all (confirmed via diagnostic capture that it does reach SocialPolicyPopup — its DB showed `PC_LastResult=NO_LEGAL_CHOICE_CLOSING`, i.e. `LEKSpaceChoosePolicy()` was genuinely invoked); (2) reordering the tick to broadcast *before* `LEKSpaceActivateOrSkip()` each cycle, to avoid evaluating a screen the instant `OnEndTurnClicked()` opens it — user re-tested, CityView still never acts.

**In-flight, not yet installed:** temporary `print()` diagnostics (to `Lua.log`, not the UserData DB — see gotcha below) were added to `internal/thumb-action/Install.ps1` (central tick), `internal/thumb-action/autopilot-production-research/Install.ps1` (CityView listener), and `internal/thumb-action/autopilot-policy-congress/Install.ps1` (SocialPolicyPopup listener). All three pass syntax-check. Next steps: close Civ V, run those three `Install.ps1` files + `internal/VerifyAll.ps1`, have the user reproduce the stuck state, run `internal/CaptureState.ps1` while still stuck (doesn't require closing the game), and read `LOGS/Lua.log` (`grep -i LEKAUTOMATE_DIAG`) from the resulting zip — this will show definitively whether each listener even fires, what `IsHidden()` reports, and what the wrapped function returns/throws. **Remove these print() statements once root-caused** — debug-only, will spam `Lua.log` in normal play otherwise.

### Established design decisions (already shipped, do not re-litigate without the user asking)

- Automate's stop condition is any keypress, not just Escape.
- City Capture: Puppet by default; Raze only if forecasted net happiness (`GetExcessHappiness()` minus the puppet-happiness delta) would drop below -5 *and* the city is population ≤2 *and* `CanRaze` is legal. Never Annex automatically.
- The only remaining hard safety exclusion: DeclareWar* "does this mean war?" confirmations on `DeclareWarPopup.lua`'s shared host Context. Every *other* originally-excluded hazard (ideology switching, World Leader self-vote, player-targeted League proposals) was explicitly de-restricted by the user this session and is now automated:
  - Ideology: Space picks an initial ideology and now also *initiates* a switch whenever the native button itself would be enabled (existing ideology + positive `GetPublicOpinionUnhappiness()`); the switch target is always engine-computed, never a free pick.
  - World Leader vote: Space casts every available vote for itself.
  - League proposals needing a player target: Space targets whoever it's at war with, else lowest-ID eligible player. Luxury/religion-targeted proposals still skipped.
- Great Prophet: 1st use founds a religion (legality-checked via `Game.HandleAction`/`GameInfoActions`, same mechanism as promotion), 2nd enhances it, 3rd+ spread to the current city or move toward the nearest own city lacking the religion's majority.
- Work Boats (`UNITAI_WORKER_SEA`) use `AUTOMATE_BUILD` like land Workers, not `AUTOMATE_EXPLORE` like Scouts (a real bug, fixed). Production won't train one if no sea resource is within 8 tiles (`LEKSpaceHasSeaWorkTarget`).
- A unit still blocking on the very next press after Space already acted on it gets force-resolved: Scouts/Work Boats get deleted (`COMMAND_DELETE`); everything else gets Skip.
- Trade units establish a route to whichever reachable destination yields the most Gold via the native destination list, bypassing the popup.

### Gotchas learned this session

- **Never put a literal Lua `--` comment in actual PowerShell code outside a `@'...'@` heredoc** — PowerShell parses `--` as a decrement attempt and `&` as a reserved operator; both caused real syntax errors. Use `#` for PowerShell comments.
- **`Insert-Before` is a local helper, not shared** — defined separately in each `Install.ps1` that needs it.
- **GameMenu.xml has three copies** (base/G&K/BNW); a BNW game loads the Expansion2 one. Any new button must patch all three, matching the pattern in `internal/core/R/INSTALL_V021.ps1`'s Reroll button.
- **Idempotent `Remove-LEKMarkedBlock` round-tripping with raw string insertion is easy to get subtly wrong** — its regex eats at most one optional `\r\n` touching each marker; mismatched surrounding whitespace accumulates stray blank lines on repeated installs. Prefer index-based `.Insert()` at a uniquely-located anchor over anchor-string `.Replace()`.
- **Not every `ContextPtr:SetUpdate` is a persistent timer** — CityView.lua's native `UpdateStuffNow` is one-shot/self-clearing (calls `ContextPtr:ClearUpdate()` immediately, re-armed elsewhere via dirty flags). Always check for existing `SetUpdate` usage before adding one; this is why Automate uses a cross-file `LuaEvents` broadcast from one central file instead of a per-file timer.
- **Raw `strings`/`grep -a -o` extraction from the UserData SQLite DBs is unreliable for "what's the current value"** — stale byte sequences from prior overwrites can be scanned out alongside the live value with no ordering. For anything timing/ordering-sensitive, use temporary `print()` to `Lua.log` instead (strictly append-only, chronological, plain text). No `sqlite3` CLI or usable Python is on the dev machine as of this writing.
- **`internal/CaptureState.ps1` does not require Civ V closed** — safe to run while stuck, for the freshest snapshot. Extended this session to also capture `LEK_SPACE_AUTOMATE-*.db`.
- All `Install.ps1`/`Uninstall.ps1` scripts **do** require Civ V closed (`Test-LEKCivRunning` guards it) — confirm via `tasklist //FI "IMAGENAME eq CivilizationV_DX11.exe"` first.

### Files and markers — Space Autopilot

All under `internal/thumb-action/`: root `Install.ps1` owns `ActionInfoPanel.lua` (`LEK_EXT_SPACE_NEXT_ACTION_V07`), `TradeLogic.lua` (`LEK_EXT_SPACE_ACCEPT_TRADE_V03`), and the Automate button/menu logic (`GameMenu.xml` x3 copies + `GameMenu.lua`, `LEK_EXT_SPACE_AUTOMATE_BUTTON_V01` / `_MENU_V01`). `autopilot-production-research/Install.ps1` owns `CityView.lua` and `TechTree.lua` (both `LEK_EXT_SPACE_AUTOPILOT_PR_V01`). `autopilot-policy-congress/Install.ps1` owns nine popups: `SocialPolicyPopup.lua` (POLICY_V04), `LeagueOverview.lua` (LEAGUE_V04), `ChoosePantheonPopup.lua` (PANTHEON_V05), `ChooseReligionPopup.lua` (RELIGION_V06), `ChooseFreeItem.lua` (FREEITEM_V07), `ChooseFaithGreatPerson.lua` (FAITHGP_V07, append pattern — no pre-existing InputHandler), `ChooseMayaBonus.lua` (MAYA_V07, append), `ChooseArchaeologyPopup.lua` (ARCHAEOLOGY_V07), `DeclareWarPopup.lua` (CITYCAPTURE_V07 — shared GenericPopup host), `ChooseIdeologyPopup.lua` (IDEOLOGY_V08). Each `Install.ps1` calls its own `Verify.ps1` at the end; `internal/VerifyAll.ps1` re-checks the whole stack.

## Known-good baseline

- LEK Core v1.3 (Reroll/Rehost v0.21, Host Instant Start v0.1, UltraFast MP Startup v0.3.1, RAS MP Bridge v0.8.8) is working and frozen. Its actual install/uninstall scripts now live in this repo under `internal/core/{R,H,U,RAS}/`, imported unchanged from the original packages — see `internal/core/README.txt`-equivalent per-component READMEs. A `pre-consolidation-2026-08-28` git tag preserves the repo's exact state from before this import.
- RAS wonder hotfix v0.8.9 (`internal/ras-wonder/`) is an isolated fix on top of RAS v0.8.8, preventing duplicate natural-wonder placement on reroll.
- Fair Trades v1.2.5 (`internal/fair/`) proactively offers AI trades (luxury swaps and Gold/GPT currency deals) with native-value gating on both the search side and a restored AI-side acceptance check; flat-Gold offers are capped at 10, and luxury-for-luxury swaps are prioritized when the human's empire is unhappy.
- `internal/InstallAll.ps1` / `internal/VerifyAll.ps1` / `internal/UninstallAll.ps1` install, verify, or uninstall the whole stack (core → RAS wonder hotfix → Fair Trades) with one command, in the proven safe order. `internal/DevTool.ps1` remains the interactive menu wrapper.
- The transient turn-start ready-signal approach works better than a `ContextPtr:SetUpdate` retry approach on the target multiplayer setup.
- `UI.incTurnTimerSemaphore()`/`decTurnTimerSemaphore()` pauses the MP turn timer while a Fair Trades offer is open, releasing on Accept/Refuse/close or dispatch failure — installed via the same marked-block bridge in EUI's `diplotrade.lua` that synthesizes the AI-offer message.

## Current Fair Trades state

**Fair Trades v1.2.5 — native-accepted relationship pricing with Gold capped at 10 and happiness-aware luxury priority**

Primary runtime: `internal/fair/UI/LEKFairTrades.lua`
Deployment/verification: `internal/fair/Install.ps1`, `internal/fair/Verify.ps1`, `internal/InstallAll.ps1`, `internal/VerifyAll.ps1`

Search and all native valuation happen before `Players[ai]:DoTradeScreenOpened()` (presession); no `IsPossibleToTradeItem`/`GetDealMyValue`/`GetDealTheyreValue` calls occur after the backend session opens. GPT prices start at a relationship-tier target (Guarded 3 / Neutral 5 / Friendly-Afraid 7), while flat Gold starts from the duration-equivalent relationship price but is capped at 10. Prices adjust directionally toward what the AI's own native valuation (`FairFor(finalV,ai,ai)`) requires; Gold adjustments remain capped at 10. All search stays within a shared 8-native-evaluation budget per scan, including use of the final available evaluation when a starting price passes immediately. Rejected AI/resource/currency combinations are independently suppressed from recurring for 10 turns. Luxury swaps keep strict two-sided (`BothFair`) native fairness unchanged; when the active human's empire is unhappy (`Player:IsEmpireUnhappy()`), the luxury-for-luxury `SWAP` shape is tried first instead of taking its normal randomized rotation slot, so a fair luxury swap is more likely to surface than a Gold/GPT offer while happiness is low.

Known Fair Trades follow-ups: none currently established from diagnostics. Continue collecting a fresh capture for any new runtime failure before changing behavior.

## Desired Fair Trades behavior

The feature proactively offers deals that resemble deals the AI would normally accept/propose in manual diplomacy, with relationship affecting frequency and starting price, not making decent trades excessively rare.

Deal families: spare Luxury <-> spare Luxury; human spare Luxury -> AI flat Gold or GPT; AI spare Luxury -> human flat Gold or GPT. For proactive luxury offers, the seller retains at least one copy after the trade.

## Known regressions that must not return

1. **No final-copy luxury offers.** A proactive offer must never give away the human's or AI's last available copy of a luxury.
2. **No queued empty AI windows.** Candidate search must not open trade sessions for multiple AIs. One selected AI session maximum per scan/turn.
3. **No stale scratch-deal mismatch.** A displayed item must not transform into another resource when clicked. Avoid cross-AI scratch state and unnecessary snapshot/rebuild behavior.
4. **No progressive turn slowdown.** Avoid broad loops, repeated visible helper calls, or unbounded valuation work — stay inside the shared 8-eval ceiling per scan.
5. **No strategic resources.** Fair Trades scope is luxury resources plus flat Gold/GPT only.
6. **No default greeting interruption.** Offers use the normal AI-offer trade UI (`DIPLO_UI_STATE_TRADE_AI_MAKES_OFFER` via the private `diplotrade.lua` bridge), never `UI.OnHumanOpenedTradeScreen` or a spoofed generic leader greeting.
7. **Do not modify frozen Core v1.3's patch logic** for isolated Fair Trades or RAS wonder hotfix problems — only its packaging/orchestration is shared, never its behavior.
8. **Auto End Turn must not advance through an unresolved offer.** The turn-timer semaphore pause/release must stay balanced (paired `inc`/`dec`, idempotent release) across Accept, Refuse, screen close, and dispatch failure.

## Deployment workflow

1. Close Civilization V.
2. Run `internal/InstallAll.ps1` (or `internal/DevTool.ps1`'s one-click cycle) to install/update core → RAS wonder hotfix → Fair Trades in order, or `internal/VerifyAll.ps1` to re-check an existing install without changing anything.
3. If runtime behavior fails, run `internal/CaptureState.ps1` (`CAPTURE_DEV_STATE.bat`) once and inspect the resulting `LEK_DEV_STATE_*.zip` — it includes the `LEK_FAIR_TRADES-1.db` SimpleValues diagnostic table (query with Python's stdlib `sqlite3`/`zipfile`, no external tools needed) plus current InGame.lua/EUI/Fair Trades runtime files and log tails.

## Development rule

Prefer the simplest implementation that produces the desired in-game behavior. Keep component-scoped edits small. Diagnose from captured runtime state before redesigning architecture. The frozen core's patch logic stays untouched unless an issue is genuinely a core defect, not an extension problem.
