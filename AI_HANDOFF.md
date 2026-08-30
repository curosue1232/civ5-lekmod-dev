# AI Development Handoff

## CURRENT OPERATIONAL HANDOFF — 2026-08-29

This section supersedes every older “current state” or “current debugging priority” section below. Older material is retained only as investigation history.

- Repository: `C:\Users\dlnwi\Desktop\civ 5 work\LEK_Dev_Workspace_v1_2_1`
- Branch/HEAD: `main`, `0dbde2b Add Space unit skip and trade acceptance`
- GitHub `main` remains canonical, but the current Space Autopilot work is intentionally **uncommitted and unpushed** until the user confirms the final hands-free test evidence and approves staging.
- The latest build is installed directly. **Do not run `T`**; it may restore the older GitHub build over the test install.
- Civ V was closed for the latest install.
- `internal/VerifyAll.ps1` passed completely after installation: frozen Core/RAS, RAS wonder hotfix, Fair Trades v1.2.5, Space v0.7, production/research, and policy/Congress.
- Frozen Core/RAS logic was not changed. Fair Trades is stable and is not the current focus.

Expected dirty working tree (preserve all changes): `AI_HANDOFF.md`, `PROJECT_STATE.md`, `internal/CaptureState.ps1`, `internal/VerifyAll.ps1`, `internal/thumb-action/{Install,Uninstall,Verify}.ps1`, plus new `autopilot-production-research/` and `autopilot-policy-congress/` directories.

### Codex coordination update — 2026-08-29 17:46 PDT

- A Claude-role code audit and Antigravity-role workflow audit were performed by parallel Codex subagents; they were not the actual Claude or Gemini models.
- `LEK_DEV_STATE_20260829_093719.zip` is newer than the capture previously called latest. It is a successful post-fix **Enhance Religion** trace: `RL_bFoundingReligion=0`, beliefs 4/5 are `14`/`33`, the button is enabled, `RL_LastPcallOK=1`, and `RL_LastResult=CONFIRMED_RELIGION`. `Lua.log` contains no current religion exception. `RL_LastError` still contains the obsolete `_G` error because that key is not cleared after success.
- The capture has `Active=0`, so repository evidence alone cannot prove the entire Enhance sequence was hands-free. Ask the tester whether AUTOMATE drove it through confirmation before declaring the final religion gate closed.
- The workspace contained a newer, not-yet-installed combat-unit patch (war enemy -> barbarian/camp -> reachable frontier guard, with ten-turn guard review). Its reachable-frontier function called a later-declared local helper, which Lua would resolve as a missing global. The helper was moved before its caller, and the verifier now enforces that ordering.
- The scoped `internal/thumb-action/Install.ps1` was run directly after Civ V was confirmed closed. The full `internal/VerifyAll.ps1` then passed: frozen Core/RAS, RAS wonder hotfix, Fair Trades v1.2.5, Space v0.7, production/research, and policy/Congress. No `T`, commit, or push was performed.
- Religion verification now explicitly requires `CheckifCanCommit()`, `RL_Belief1` through `RL_Belief6`, `RL_FoundReligionDisabled`, `RL_LastPcallOK`, and `RL_LastError`.

**Exact next step:** confirm whether the turn-47 `093719` Enhance result was fully AUTOMATE-driven. Then run one clean hands-free BNW multiplayer pass covering Found Religion plus the newly installed combat behaviors (war target, barbarian/camp, frontier guard, and ten-turn reassessment). If anything stalls, leave the screen untouched and AUTOMATE active, note the turn, and run `internal/CaptureState.ps1` while Civ V remains open. Do not change Enhance logic unless a new live capture shows a recurrence.

### Codex cleanup installation — 2026-08-29 18:03 PDT

- Civ V was confirmed closed.
- Ran the scoped `autopilot-production-research/Install.ps1` and `autopilot-policy-congress/Install.ps1` installers after Claude removed the temporary `LEKAUTOMATE_DIAG` prints from their source.
- Direct inspection confirms those diagnostic prints are absent from the live EUI `SocialPolicyPopup.lua`, `CityView.lua`, and `TechTree.lua` files.
- `internal/VerifyAll.ps1` passed the complete installed stack after installation. Frozen Core/RAS was not changed. No `T`, commit, or push was performed.
- **Next test:** launch BNW multiplayer, enable AUTOMATE, avoid keyboard input, and let the first Great Prophet complete Found Religion fully hands-free. If it stalls, do not interact with the popup; note the turn and run `internal/CaptureState.ps1` while AUTOMATE remains active.

### Current driver design

AUTOMATE uses `Modding.OpenUserData("LEK_SPACE_AUTOMATE",1)`, key `Active`. A persistent driver is patched into all four installed `InGame.lua` layouts. Every **0.7 seconds** it performs a synchronous two-phase dispatch:

1. `LuaEvents.LEKSpaceAutomateTick()` lets visible modal screens act first.
2. A visible modal calls `LuaEvents.LEKSpaceAutomateModalHandled(1.7)`, consuming that cycle and pausing for **1.7 seconds**.
3. Only when no modal consumed the cycle does the driver emit `LuaEvents.LEKSpaceAutomateWorldTick()`.
4. `ActionInfoPanel.lua` listens only to the world phase. It calls `LEKSpaceActivateOrSkip()` without a `ContextPtr:IsHidden()` gate and without a duplicated/local pause flag.

This solved the previous permanent-pause desynchronization and prevents map actions from firing behind an open choice screen. Any keyboard keypress deliberately disables AUTOMATE; mouse clicks do not.

### Latest in-game results

The newest capture is `LEK_DEV_STATE_20260829_093719.zip`, taken after the `_G` correction was installed. Proper SQLite inspection shows a successful Enhance path at turn 47:

```text
RL_bFoundingReligion = 0
RL_Belief4 = 14
RL_Belief5 = 33
RL_FoundReligionDisabled = 0
RL_LastFOLLOWER2Count = 20
RL_LastENHANCERCount = 12
RL_LastPcallOK = 1
RL_LastResult = CONFIRMED_RELIGION
```

This proves the patched code selected both Enhance beliefs, enabled the button, opened the confirmation, and called `OnYes()` on the next tick. Because the capture's Automate database has `Active=0`, ask the tester whether the sequence was entirely AUTOMATE-driven before calling the final hands-free gate complete. The older `_G` value still present in `RL_LastError` is stale; successful calls do not currently clear that key.

The newest Found Religion reproduction was captured at turn 34 in `LEK_DEV_STATE_20260829_092350.zip`. AUTOMATE opened the Founder/Follower belief flow but left the list visible and stopped; manually closing the popup and restarting AUTOMATE allowed it to complete. Proper SQLite inspection found the exact exception:

```text
RL_LastError = Assets\DLC\Expansion2\UI\InGame\Popups\ChooseReligionPopup.lua:110: attempt to index global '_G' (a nil value)
RL_LastFOUNDERCount = 12
RL_LastFOLLOWERCount = 21
```

The root cause was not the 0.7s/1.7s driver timing. `LEKSpaceSetBelief` assigned `g_Beliefs[slot]` and then tried to update the injected Civ V UI controls through `_G["Controls"]`; this Lua context has no `_G`, so the function aborted before updating the labels, calling `CheckifCanCommit()`, and closing the belief panel. The installer now uses the native-supported dynamic form `Controls[control.."Name"]` / `Controls[control.."Description"]`. The verifier requires both direct `Controls` expressions and forbids `_G["Controls"]`. This correction is installed, and `internal/VerifyAll.ps1` passes completely. Enhance now has a successful post-fix trace; hands-free provenance and one clean Found pass remain to be confirmed.

The user successfully ran AUTOMATE through ordinary turns, production, research, and social policy. It then stopped at **Found a Religion** on turn 36.

Live capture: `LEK_DEV_STATE_20260829_063602.zip`. Proper SQLite inspection showed:

```text
RL_LastPressTurn = 36
RL_LastReligionID = 1
RL_LastResult = NO_LEGAL_FOUND_BELIEF
```

The screen visibly had Buddhism and Goddess of the Hunt selected with empty Founder/Follower slots. The religion listener was alive; this was not a heartbeat failure. The user manually exited the religion screen, enabled AUTOMATE again, and it then reopened the flow, chose beliefs, and founded the religion. This proves full popup re-entry refreshes the engine-side belief availability state.

### Religion recovery installed; successful Enhance trace captured

`internal/thumb-action/autopilot-policy-congress/Install.ps1` now:

- stages native belief-category opening (`OnFounderBeliefClick`, `OnFollowerBeliefClick`, etc.) and selection over separate cycles;
- closes the belief subpanel after direct selection;
- when an opened category still returns zero beliefs, closes the subpanel and entire religion popup so the Prophet/world dispatcher can reopen it;
- caps full-popup recovery to one retry per game turn via `LEKSpaceReligionRetryTurn`;
- records per-category counts, `RL_LastPcallOK`, and `RL_LastError`.

This build passed PowerShell parsing, component installers/verifiers, and the full stack verifier. `093719` confirms successful post-fix Enhance behavior, but the user still needs to confirm whether that run was fully hands-free and complete one clean Found reproduction before staging.

### Exact next steps for Claude, ChatGPT, or Antigravity

1. **Scout-Upgraded-Archer / Explorer Auto-Explore Fix:** When a Scout upgrades to an Archer via an Ancient Ruin, `unitClass` becomes `UNITCLASS_ARCHER`. It previously bypassed `AUTOMATE_EXPLORE` and fell through to combat unit logic (which tried to path back to borders and got cancelled/skipped by `LEKSpaceTrackedUnit`). Fixed by checking `PROMOTION_IGNORE_TERRAIN_COST` / `UNITAI_EXPLORE` to keep upgraded scouts on `AUTOMATE_EXPLORE`. Also improved stuck-unit debounce in `ActionInfoPanel.lua` to track X, Y, and remaining moves so units actively spending moves are never prematurely skipped.
2. **Delete Unit Confirmation Modal Fix:** `ConfirmCommandPopup.lua` (both EUI and vanilla) wrapped for `Keys.VK_SPACE` and `LuaEvents.LEKSpaceAutomateTick`.
3. **Trade accept & Scout delete fixes:** Both completed and verified in `internal/thumb-action/Install.ps1`.
4. **Religion diagnosis readiness:** Granular per-slot logging (`RL_Belief1`..`RL_Belief6`), button disabled state (`RL_FoundReligionDisabled`), and full 6-slot duplicate exclusion are installed and fully verified via `internal/VerifyAll.ps1`.
5. **In-game test:** Space or Automate will now automatically explore with Scout-upgraded Archers and confirm delete modals. Continue testing religion Found/Enhance.
6. If tests pass cleanly, clean up temporary diagnostic logging, run `internal/VerifyAll.ps1`, and proceed with staging/commit with user approval.

Current component owners: root `internal/thumb-action/Install.ps1` owns ActionInfoPanel, InGame drivers, trade acceptance, and Automate menu; `autopilot-production-research/Install.ps1` owns CityView/TechTree; `autopilot-policy-congress/Install.ps1` owns policy, Congress, pantheon/religion, free choices, archaeology, city capture, and ideology.

Codex bundled Python (for captured ZIP/SQLite inspection): `C:\Users\dlnwi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`.

### Three additional confirmed bugs found 2026-08-29 (Claude, later same session, live diagnostic — no fix applied yet)

Live SQLite capture (`LEK_DEV_STATE_20260829_065819.zip`, `DB/LEK_SPACE_AUTOPILOT-1.db`, queried with the Codex Python above — proper SQLite query, not raw `strings` scanning) plus two further in-game screenshots at turn 50/52 surfaced three more issues on top of the religion Found/Enhance one. All three are small, isolated, independently diagnosed; none have been applied yet pending the user's go-ahead, per "do not disturb the current install" above.

1. **Incoming AI trade offers are never accepted by Automate at all.** `internal/thumb-action/Install.ps1`'s `LEKSpaceAcceptIncomingOffer()` (TradeLogic.lua bridge, ~line 577) is registered **only** on the manual-keypress `InputHandler` (~line 599: `if wParam == Keys.VK_SPACE then if LEKSpaceAcceptIncomingOffer() then return true end`). There is no `LuaEvents.LEKSpaceAutomateTick.Add(...)` / `LEKSpaceAutomateWorldTick.Add(...)` listener for it anywhere in the file — it was never wired into Automate in the first place (same class of gap as the 9 policy-congress popups that were missing `ModalHandled` earlier). **Fix:** add one listener calling `pcall(LEKSpaceAcceptIncomingOffer)`, matching whichever tick phase (`LEKSpaceAutomateTick` vs `LEKSpaceAutomateWorldTick`) a modal-type screen is supposed to listen to under the current two-phase driver.
2. **The "stranded unit gets deleted" fallback logs success but doesn't actually delete anything**, so Automate gets stuck repeatedly re-selecting the same Scout every cycle (reproduced twice, turn ~45 and turn 52, both times near unreachable/icebound terrain). DB showed `U_LastResult = DELETED_STRANDED_UNIT` logged, yet the unit is still alive and still "needs orders" in the next screenshot. Root cause: this fallback (in `internal/thumb-action/Install.ps1`'s `LEKSpaceActivateOrSkip()`) sends a raw `Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_COMMAND, CommandTypes.COMMAND_DELETE, -1, -1, false)`, but the native Delete button (`UnitPanel.lua:892`) never uses that pathway — it goes through `Game.HandleAction(actionID)`, the same generic mechanism already proven for Promotion. No delete-confirmation dialog exists natively (checked), so that's not the blocker. **Fix:** replace the raw network call with a `GameInfoActions` scan for `ActionSubTypes.ACTIONSUBTYPE_COMMAND` + `Type=="COMMAND_DELETE"`, `Game.CanHandleAction` check, then `Game.HandleAction(actionID)` — mirrors the already-working promotion/religion-mission pattern exactly.
3. **Religion stall recurs at Enhance, not just Found.** Same game progressed past the turn-36 Found-Religion snag (recovery logic worked) but by turn 49 hit `RL_LastResult = NO_LEGAL_ENHANCE_BELIEF` — the identical dead-end shape, now on the Enhance side of `LEKSpaceReligion` (the `g_bFoundingReligion == false` branch). The Found-side recovery (stage native belief-category opening, close/reopen popup on empty availability, capped one-retry-per-turn) was apparently written only for the Found branch. **Fix:** mirror the same recovery logic onto the Enhance branch, or better, factor it into one shared helper both branches call, since the underlying "belief pool sometimes reads empty until the popup is fully closed and reopened" behavior is evidently not specific to founding.

**Update, same session, after Civ was closed for reinstall:** #1 (trade accept) and #2 (Scout delete) are now fixed, installed, and verified — both in `internal/thumb-action/Install.ps1`, `internal/VerifyAll.ps1` passes the entire stack. #3 (religion Enhance) is **not fixed** — see below, it needs live diagnosis, not a blind code change.

- Trade accept: added `LuaEvents.LEKSpaceAutomateTick.Add(function() if not ContextPtr:IsHidden() then LuaEvents.LEKSpaceAutomateModalHandled(1.7); pcall(LEKSpaceAcceptIncomingOffer) end end)` right after the existing `InputHandler` wrap in the TradeLogic.lua body (`internal/thumb-action/Install.ps1`).
- Scout/Work Boat delete: replaced the raw `Game.SelectionListGameNetMessage(...COMMAND_DELETE...)` call with a `GameInfoActions` scan (`SubType==ActionSubTypes.ACTIONSUBTYPE_COMMAND and Type=="COMMAND_DELETE"`, `Game.CanHandleAction` check) + `Game.HandleAction(deleteAction)`, with a `MISSION_SKIP` fallback if no such action is ever legal. Same file, same `LEKSpaceActivateOrSkip()` function.
- `internal/thumb-action/Verify.ps1` updated to match both (the old check for `CommandTypes.COMMAND_DELETE` was replaced since the fix now uses a string-compared `action.Type` instead of the enum, matching the existing `LEKSpaceFindMissionAction` pattern already proven for Promotion/Religion missions).

**Religion Enhance (#3) — investigated further, root cause NOT static-analysis-findable, needs live diagnosis:** Checked whether the Found-side recovery (`LEKSpacePickOpenBelief`/`LEKSpaceOpenBeliefContext`) was only wired to the Found branch — it wasn't; it's already shared and IS used by both `FollowerBelief2`/`EnhancerBelief` (Enhance) and `FounderBelief`/`FollowerBelief` (Found). Also checked the native `CheckifCanCommit()` function directly — its `elseif(g_Beliefs[4] ~= nil and g_Beliefs[5] ~= nil) then Controls.FoundReligion:SetDisabled(false)` branch looks structurally correct for enabling the Enhance confirm button. Since `RL_LastResult=NO_LEGAL_ENHANCE_BELIEF` (not a `NO_AVAILABLE_..._AFTER_RETRY` from the shared helper) was observed, both belief slots 4 and 5 must have already been filled by the time the dead-end fired — meaning `Controls.FoundReligion:IsDisabled()` was apparently still `true` despite both beliefs being set, which contradicts the native `CheckifCanCommit()` logic as read. **This needs a live capture during an actual Enhance stall** (`RL_LastFollowerBelief2` type per-slot logging isn't present yet — would need adding, or just inspect `g_Beliefs[4]`/`g_Beliefs[5]`/`Controls.FoundReligion:IsDisabled()` live) rather than another guess. Do not blind-fix this one.

Whoever picks this up next (Claude or ChatGPT): #1 and #2 are done and safe to build on. For #3, capture live state during an actual Enhance-belief stall (not just Found) and inspect whether `g_Beliefs[4]`/`[5]` are really both set and whether `CheckifCanCommit()` is actually being invoked/re-run after both are set, before writing any fix.

### Non-negotiable constraints

- Do not modify frozen Core/RAS behavior.
- Never automate Declare-War confirmation popups.
- Preserve the dirty working tree and all user/Claude changes.
- Do not run `T`, commit, or push until the final religion test passes and the user approves.
- Prefer captured evidence and the smallest component-scoped correction.

This file is the short, current operational handoff for AI-assisted development of the LEKMOD 30.7 extensions in this repository.

## Collaboration roles

- **User / tester:** runs the install/verify cycle, launches Civilization V, tests behavior, and captures diagnostics with `internal/CaptureState.ps1` when needed. Plays a live multiplayer (BNW/Brave New World) game as the primary test environment.
- **AI (Claude, ChatGPT, or Antigravity):** works directly on this repository — reviews code and diagnostics, writes patches, runs the installer/verifier on the user's machine, and commits/pushes to `main` with the user's confirmation before each push. There is no separate integrator role. Whichever assistant is active should read this file first and treat it as authoritative over any stale assumption from its own prior context.

GitHub `main` is the shared source of truth for anything the user should test.

## Current state — two active efforts

1. **Fair Trades v1.2.5** (proactive AI trade offers) on top of **LEK Core v1.3** (Reroll/Rehost, Host Instant Start, UltraFast MP Startup, RAS MP Bridge) and **RAS wonder hotfix v0.8.9** — stable, not the current focus. See "Fair Trades reference" section below if work resumes there.
2. **Space Autopilot ("Space" + "Automate")** — the CURRENT active focus, and mid-debugging right now. Described in full below.

## Space Autopilot — what it is

Pressing Space during a game blows through the current turn: it opens whatever screen is blocking end-turn and makes a reasonable (not necessarily optimal) choice, one decision per press, indefinitely falling back to Skip/Fortify when nothing better applies. A button labeled **"AUTOMATE"** was added to the in-game Escape menu that repeats Space's action automatically on a timer until any key is pressed, so the player doesn't have to hold Space down manually.

**Manual Space presses work correctly on every screen right now.** The bug under active investigation is specifically that **Automate does not reliably trigger the same logic that manual Space does** on screens other than the world-view turn-advance itself. See "Current debugging priority" below.

### Architecture

- **Space itself**: each automated screen is its own native Lua file, wrapped with a `LEKSpaceChooseX()`-style function bound to `wParam == Keys.VK_SPACE` in that file's own `InputHandler`. This part is solid and proven — installed/verified repeatedly this session with no outstanding bugs.
- **Automate**: a single shared boolean flag in a UserData SQLite store (`Modding.OpenUserData("LEK_SPACE_AUTOMATE", 1)`, key `"Active"`, 0/1) that different Lua *contexts* (which don't share globals) both write and read:
  - `GameMenu.lua`'s "AUTOMATE" button writes the flag and calls `OnReturn()` to close the menu.
  - `ActionInfoPanel.lua` (which already owns the core Space/world-view logic) runs a `ContextPtr:SetUpdate` timer that fires every 0.5s while the flag is active. Each tick it (a) broadcasts `LuaEvents.LEKSpaceAutomateTick()` — a cross-file pub/sub event — so every other automated screen can act if it happens to be the one currently open, then (b) calls `LEKSpaceActivateOrSkip()` to advance world-view turn/unit logic directly.
  - Every other automated file (CityView, TechTree, SocialPolicyPopup, LeagueOverview, ChoosePantheonPopup, ChooseReligionPopup, ChooseFreeItem, ChooseFaithGreatPerson, ChooseMayaBonus, ChooseArchaeologyPopup, DeclareWarPopup, ChooseIdeologyPopup) registers a `LuaEvents.LEKSpaceAutomateTick.Add(function() if not ContextPtr:IsHidden() then pcall(LEKSpaceChooseX) end end)` listener, so it only acts while it's genuinely the screen showing.

### Current debugging priority — Automate not driving non-world-view screens

**Symptom (as of the last test round):** with Automate on, world-view turn/unit progression (Space's core loop) works fine, but:
- CityView (production choice): does **not** act at all — confirmed even when the player has been sitting on a manually-opened, fully-settled CityView screen for a while, not just immediately after it opens. So this is not (only) a timing/settle issue.
- SocialPolicyPopup (policy choice): **partially** works — a policy selection appears to happen (opens the native confirm dialog), but the screen never advances past that — the confirm step (`OnYes()`/`OnTenetConfirmYes()`) never fires, so it sits on the confirm dialog indefinitely.
- TechTree (research choice): reported as also not working, not yet re-tested since the ordering fix below.

This inconsistency across screens (some fire and get partway, one seems to never fire) means the root cause is not yet nailed down. Two things have already been tried and did **not** fully fix it:
1. Building the `LuaEvents.LEKSpaceAutomateTick` broadcaster + per-file listeners in the first place (confirmed via diagnostic capture that the broadcast reaches at least SocialPolicyPopup, since its DB showed `PC_LastResult = NO_LEGAL_CHOICE_CLOSING` had been written, i.e. `LEKSpaceChoosePolicy()` was genuinely invoked).
2. Reordering the tick so the broadcast fires *before* `LEKSpaceActivateOrSkip()` each cycle (to avoid evaluating a screen the same synchronous instant `OnEndTurnClicked()` just opened it) — this was a reasonable theory (a manual Space press has human-scale delay that this lacked) but the user re-tested and it did **not** resolve the CityView-never-acts symptom.

**What NOT to conclude without more evidence:** don't assume `LuaEvents` itself fails to bridge across different Lua files — this was verified against native game code (`Assets/DLC/Expansion2/UI/InGame/CityView/CityView.lua` natively uses `LuaEvents.TryDismissTutorial(...)` and `LuaEvents.ProductionPopup.Add(...)` across files), so the mechanism is real and used by the base game. The bug is somewhere more specific — a per-screen difference, a `ContextPtr:IsHidden()` semantic that doesn't mean what's assumed for some contexts, or something about how/when each listener is actually reached.

**In-flight, NOT YET installed (as of this handoff):** temporary `print()` diagnostics (write to `Lua.log`, which is chronologically ordered and unambiguous — unlike the UserData DB, see gotcha below) have been added but not yet pushed to the live game:
- `internal/thumb-action/Install.ps1` — inside the central `ContextPtr:SetUpdate` tick in `ActionInfoPanel.lua`'s body: prints `"LEKAUTOMATE_DIAG: tick firing turn=..."` and the broadcast's own `pcall` ok/err.
- `internal/thumb-action/autopilot-production-research/Install.ps1` — CityView.lua's `LuaEvents.LEKSpaceAutomateTick.Add(...)` listener: prints whether the listener fired at all and what `ContextPtr:IsHidden()` reports, plus the `pcall(LEKSpaceChooseProduction)` result.
- `internal/thumb-action/autopilot-policy-congress/Install.ps1` — SocialPolicyPopup.lua's listener: same shape of diagnostic.

All three files pass PowerShell syntax-check as of this handoff. **Next steps:**
1. Close Civ V (`tasklist //FI "IMAGENAME eq CivilizationV_DX11.exe"` to confirm), then run the three `Install.ps1` files above (in any order) followed by `internal/VerifyAll.ps1`.
2. Have the user relaunch, get into a state where Automate is on and CityView/Policy would normally get stuck, let it run for a few seconds.
3. Run `internal/CaptureState.ps1` while still stuck (does not require closing the game), extract the resulting zip, and read `LOGS/Lua.log` (plain text, `grep -i LEKAUTOMATE_DIAG`) — this will show definitively whether each listener fires at all, what `IsHidden()` reports, and what the wrapped choose-function actually returns/throws.
4. Once root-caused, **remove the temporary `print()` diagnostics** before considering the fix done — they're debug-only and will spam `Lua.log` in normal play otherwise.

### Established design decisions (do not re-litigate without the user asking)

- Automate's stop condition is **any keypress**, not specifically Escape — implemented in `ActionInfoPanel.lua`'s `LEKSpaceNextActionInput`, which clears the `Active` flag on any `KeyEvents.KeyDown` before its own Space-specific handling.
- Puppet a captured city by default; Raze instead only if forecasted net empire happiness (`GetExcessHappiness()` minus the puppet-happiness delta from `GetUnhappinessForecast(nil, newCity)`) would drop below **-5** *and* the city is population ≤2 *and* `CanRaze` is legal. Otherwise always Puppet. Never Annex automatically.
- The only remaining **hard safety exclusion** (never automate, regardless of anything else): the DeclareWar* "does this mean war?" confirmations sharing `DeclareWarPopup.lua`'s host Context (`BUTTONPOPUP_DECLAREWARMOVE`, `BUTTONPOPUP_DECLAREWARRANGESTRIKE`, the plunder-trade-route variant). City Capture's own automation explicitly checks `g_PopupInfo.Type == BUTTONPOPUP_CITY_CAPTURED` and falls through untouched for anything else on that shared host. All of the *other* originally-excluded hazards (ideology switching, World Leader self-vote, player-targeted League proposals) were explicitly de-restricted by the user later in the same session and are now automated — see below.
- Ideology: Space now both picks an initial ideology (flavor-scored) and *initiates* a switch (not just confirms one already open) whenever the native Switch Ideology button itself would be enabled (existing ideology + `GetPublicOpinionUnhappiness() > 0`). The switch *target* is never a free pick — the engine computes it from world pressure.
- World Leader (diplomatic-victory) vote: Space now casts every available vote for itself, rather than skipping the session.
- League proposals needing a player target (embargo/denounce-style): Space now targets whoever it's at war with, else the lowest-ID other eligible player. Luxury/religion-targeted proposals are still skipped (no signal from the user to automate those).
- Great Prophet: 1st use founds a religion (native mission-legality-checked via the same `Game.HandleAction`/`GameInfoActions` mechanism as promotion, not a blind mission push), 2nd enhances it, 3rd+ spread the religion — to the current city if it lacks the religion's majority, else move toward the nearest own city that does.
- Work Boats are `UNITAI_WORKER_SEA` and must use `AUTOMATE_BUILD` (like land Workers), not `AUTOMATE_EXPLORE` like Scouts — this was a real misclassification bug, now fixed. Production will not even choose to train a Work Boat if no sea resource is reachable (`LEKSpaceHasSeaWorkTarget` scans an 8-tile radius from the city).
- A unit Space already acted on that's *still* the same blocker on the very next press gets force-resolved instead of retried forever: Scouts/Work Boats (and any `UNITAI_WORKER_SEA`) get deleted (`CommandTypes.COMMAND_DELETE`) since a stranded one is dead weight; everything else gets a plain Skip.
- Trade units (Caravan/Cargo Ship, `UNITAI_TRADE_UNIT`) establish a route to whichever reachable destination yields the most Gold, via the same native destination list (`GetPotentialInternationalTradeRouteDestinations`) the popup itself uses — bypassing the popup UI entirely, same as everything else.

## Files and markers — Space Autopilot map

| File (relative to Civ V install) | Owning Install.ps1 | Marker | Pattern |
|---|---|---|---|
| `Assets/DLC/Expansion2/UI/InGame/WorldView/ActionInfoPanel.lua` | `internal/thumb-action/Install.ps1` | `LEK_EXT_SPACE_NEXT_ACTION_V07` | append (`Set-LEKMarkedBlock`) |
| `Assets/DLC/UI_bc1/LeaderHead/TradeLogic.lua` | same | `LEK_EXT_SPACE_ACCEPT_TRADE_V03` | append |
| `Assets/UI/InGame/Menus/GameMenu.xml` **(three copies: base, `DLC/Expansion`, `DLC/Expansion2` — BNW loads the Expansion2 copy, must patch all three or a BNW game won't see the button)** | same | `LEK_EXT_SPACE_AUTOMATE_BUTTON_V01` | index-based insert after `RetireButton`'s closing tag |
| `Assets/UI/InGame/Menus/GameMenu.lua` (single file, shared across all three XML layouts) | same | `LEK_EXT_SPACE_AUTOMATE_MENU_V01` | append |
| `Assets/DLC/UI_bc1/CityView/CityView.lua` | `internal/thumb-action/autopilot-production-research/Install.ps1` | `LEK_EXT_SPACE_AUTOPILOT_PR_V01` | wrap via `Add-Bridge` |
| `Assets/DLC/UI_bc1/TechTree/TechTree.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_PR_V01` | wrap via `Add-Bridge` |
| `Assets/DLC/UI_bc1/Improvements/SocialPolicyPopup.lua` | `internal/thumb-action/autopilot-policy-congress/Install.ps1` | `LEK_EXT_SPACE_AUTOPILOT_POLICY_V04` | wrap |
| `Assets/DLC/Expansion2/UI/InGame/Popups/LeagueOverview.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_LEAGUE_V04` | wrap |
| `.../Popups/ChoosePantheonPopup.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_PANTHEON_V05` | wrap |
| `.../Popups/ChooseReligionPopup.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_RELIGION_V06` | wrap |
| `.../Popups/ChooseFreeItem.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_FREEITEM_V07` | wrap |
| `.../Popups/ChooseFaithGreatPerson.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_FAITHGP_V07` | **append** — no pre-existing `SetInputHandler` |
| `.../Popups/ChooseMayaBonus.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_MAYA_V07` | **append** — no pre-existing `SetInputHandler` |
| `.../Popups/ChooseArchaeologyPopup.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_ARCHAEOLOGY_V07` | wrap |
| `.../Popups/DeclareWarPopup.lua` (shared "GenericPopup" host for City Capture + several other popup types — see below) | same | `LEK_EXT_SPACE_AUTOPILOT_CITYCAPTURE_V07` | wrap |
| `.../Popups/ChooseIdeologyPopup.lua` | same | `LEK_EXT_SPACE_AUTOPILOT_IDEOLOGY_V08` | wrap |

Each `Install.ps1` above ends by invoking its own `Verify.ps1`, which independently re-checks every marker/token; run the specific component's script (or `internal/VerifyAll.ps1` for everything) after any edit. **All of the above are currently installed and verified** except the three not-yet-installed print() diagnostics described above.

## Gotchas learned this session (read before touching install scripts)

- **PowerShell files must never contain a literal Lua-style `--` comment outside of a `@'...'@` heredoc.** PowerShell parses `--` as a decrement-operator attempt and `&` (e.g. in "Gods & Kings") as a reserved operator — both caused real syntax errors this session. Use `#` for PowerShell-level comments; `--` is fine *inside* a heredoc since it's just text being written to the target Lua file.
- **`Insert-Before` is not a shared helper** — it's defined locally inside each `Install.ps1` that needs it (originally only in `autopilot-policy-congress`). If you add a new usage to a different script, define the function there too.
- **GameMenu.xml exists in three copies** (base game, Gods & Kings, Brave New World) and the *loaded* one depends on which DLC combination is active — a BNW game loads the Expansion2 copy. `internal/core/R/INSTALL_V021.ps1`'s Reroll/Rehost button already handles all three; any future GameMenu.xml button must too.
- **Round-tripping `Remove-LEKMarkedBlock` idempotently with raw string insertion is easy to get subtly wrong.** `Remove-LEKMarkedBlock`'s regex eats at most one optional `\r\n` immediately touching each marker and replaces the whole match with a single `\r\n` — if your inserted block's surrounding whitespace doesn't exactly mirror that, re-running the installer will accumulate stray blank lines each time (harmless to the game, but breaks any `.Contains()` idempotency check tied to exact original text). The GameMenu.xml button insert uses index-based `.Insert()` at a uniquely-located anchor (`ID="RetireButton"` then the next `</GridButton>`) specifically to sidestep this — prefer that pattern over anchor-string `.Replace()` for anything new.
- **Not every file's `ContextPtr:SetUpdate` is a persistent per-frame timer.** CityView.lua's native `UpdateStuffNow` is a **one-shot, self-clearing** handler (calls `ContextPtr:ClearUpdate()` on its own first line, re-armed via `SetUpdate` again whenever a dirty flag is set elsewhere) — adding a second, persistent `SetUpdate` to that same Context would fight this constantly. Always `grep -n "SetUpdate"` a target file before adding one; if it's already used, either capture-and-wrap the existing *named* local function (only possible if your insertion point is textually *after* its declaration) or find another mechanism (this is exactly why the Automate-driving mechanism uses a cross-file `LuaEvents` broadcast from `ActionInfoPanel.lua` instead of giving every file its own timer).
- **Raw `grep -a -o`/`strings`-style extraction from the UserData SQLite files is unreliable for "what's the current value."** SQLite doesn't necessarily overwrite in place; old byte sequences from prior writes can still be scanned out of the raw file alongside the current live value, with no ordering information. For anything where you need to know *the current, or the order of, values* (not just "has this key ever been set"), prefer temporary `print()` statements read back from `Lua.log` (strictly append-only, chronological, plain text) via `internal/CaptureState.ps1`. No `sqlite3` CLI or Python is installed on the dev machine as of this writing (`python3` only resolves to the Microsoft Store app-execution-alias stub) — a real SQLite reader would need to be sourced or a minimal page parser written from scratch if DB inspection becomes unavoidable.
- **`internal/CaptureState.ps1` does not require Civ V to be closed** — it just copies files (best-effort via `Copy-Safe`, swallows locked-file errors) — safe to run while the game is open and stuck, which is exactly when you want the freshest `Lua.log`/DB snapshot. It was extended this session to also capture `LEK_SPACE_AUTOMATE-*.db` (previously only `LEK_SPACE_AUTOPILOT` was captured).
- Every `Install.ps1`/`Uninstall.ps1` in this repo **does** require Civ V closed first (`Test-LEKCivRunning` guards it) — always confirm via `tasklist //FI "IMAGENAME eq CivilizationV_DX11.exe"` before running one.

## Diagnostic workflow (Space Autopilot)

1. Every automated Lua function logs its own turn number and outcome to the shared `LEK_SPACE_AUTOPILOT` UserData DB via a per-file `LEKAutopilotLog(k,v)` helper (e.g. `PR_LastResult`, `PC_LastResult`, `RL_LastResult`, `U_LastResult` — prefixes roughly match the screen). The Automate on/off flag lives separately in `LEK_SPACE_AUTOMATE` (key `Active`).
2. For anything timing- or ordering-sensitive, prefer temporary `print()` → `Lua.log` over reading the DB (see gotcha above).
3. Run `internal/CaptureState.ps1` (safe while the game is still open/stuck) → extract the `LEK_DEV_STATE_*.zip` → read `LOGS/Lua.log` directly (`grep`), or the `DB/*.db` files if only "has this ever happened" matters.
4. Make a component-scoped edit, syntax-check with `[System.Management.Automation.Language.Parser]::ParseFile`, confirm Civ V is closed, run the specific component's `Install.ps1` (it calls its own `Verify.ps1` at the end), then `internal/VerifyAll.ps1` for the full stack.
5. Visually re-read the live installed Lua for anything structurally novel (a new wrap pattern, a new cross-file mechanism) — don't rely on the marker/token checks alone to catch a logic error.
6. Commit with the user's confirmation; push only after explicit confirmation.

## Fair Trades reference (stable, not currently active)

Primary runtime: `internal/fair/UI/LEKFairTrades.lua`. Install/verify/uninstall: `internal/fair/*.ps1`, `internal/ras-wonder/*.ps1`, `internal/core/{R,H,U,RAS}/*.ps1`. Combined: `internal/InstallAll.ps1` / `internal/VerifyAll.ps1` / `internal/UninstallAll.ps1`. Interactive menu: `internal/DevTool.ps1`.

Deal families: spare Luxury <-> spare Luxury; human spare Luxury -> AI flat Gold or GPT; AI spare Luxury -> human flat Gold or GPT. The seller retains at least one copy after a proactive luxury trade. Luxury-for-luxury swaps are prioritized (not just their normal rotated slot) whenever the active human's empire is unhappy (`Player:IsEmpireUnhappy()`), without weakening the swap's own two-sided fairness gate.

**Known regressions that must not return:** no final-copy luxury offers; no queued empty AI windows (one selected AI session max per scan/turn); no stale scratch-deal mismatch; no progressive turn slowdown (stay inside the shared 8-native-evaluation ceiling); no strategic resources (luxury + flat Gold/GPT only); no default greeting interruption; **never modify frozen Core v1.3's patch logic** for an isolated extension problem; Auto End Turn must never advance through an unresolved offer (turn-timer semaphore pause/release must stay balanced across every exit path).

If work resumes here: query `DB\LEK_FAIR_TRADES-1.db`'s `SimpleValues` table for `OfferScanReason`, `OfferVisitedDueAIs`, `OfferNativeEvals`, per-AI `LastShape`/`LastShapeResult`/`PartnerRejected`, `LastShownAI`/`LastShownTurn`/`LastShownShape`, and the bridge fields — same DB-reliability caveat above applies (prefer a proper reader over raw `strings` scanning if timing matters).

## Instructions for future AI sessions

Read this file first — it supersedes any assumption from an older chat transcript, regardless of which assistant produced that transcript. Then check whichever files the task touches are still current (`grep`/`Read` the live repo state, don't trust a remembered snippet). The user works with both Claude and ChatGPT on this repo at different times; treat this file as the single shared source of truth between them.

Focus areas that have mattered repeatedly in this project:
- Civ V Lua API argument-count/signature mismatches (e.g. Gold's `IsPossibleToTradeItem` takes one fewer argument than GPT's).
- Cross-context communication requires either a shared UserData store (read/write, works for a persistent boolean-style flag) or `LuaEvents` (a real cross-file pub/sub confirmed to work natively) — plain Lua globals do **not** cross Context boundaries.
- Multiplayer event/network timing (turn-start message-queue busy states, the turn-timer semaphore, and — per the current investigation — Automate's own tick cadence relative to when a screen's state actually becomes queryable).
- Ways to accomplish the requested behavior with less code — reuse `internal/LekTools.ps1` helpers rather than duplicating Steam-detection/file-patching logic.
- Any path that could open more than one modal popup/session at once.
- Last-copy resource safety (Fair Trades).
- Performance/repeated-native-call hazards.
- Never automate the DeclareWar* "does this mean war?" confirmations — the one remaining hard safety exclusion in Space Autopilot.
