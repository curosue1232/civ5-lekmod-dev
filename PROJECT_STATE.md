# Project State

This file is the **standalone current operational handoff** for the Civ V LEKMOD development project. If an external reviewer can read only one file from the repository, this is the file to use.

## Collaboration roles

- **User / tester:** runs the install/verify cycle, launches Civilization V, tests behavior, and captures diagnostics with `internal/CaptureState.ps1` (`CAPTURE_DEV_STATE.bat`) when needed.
- **Claude:** works directly on this repository — reviews code and diagnostics, writes patches, runs the installer/verifier, and commits/pushes to `main` with the user's confirmation before each push. There is no separate integrator; this replaced an earlier workflow where a different assistant held GitHub write access.

GitHub `main` is the shared source of truth for anything the user should test.

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
