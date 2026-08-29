# AI Development Handoff

This file is the short, current operational handoff for AI-assisted development of the LEKMOD 30.7 extensions in this repository.

## Collaboration roles

- **User / tester:** runs the install/verify cycle, launches Civilization V, tests behavior, and captures diagnostics with `internal/CaptureState.ps1` when needed.
- **Claude:** works directly on this repository — reviews code and diagnostics, writes patches, runs the installer/verifier on the user's machine, and commits/pushes to `main` with the user's confirmation before each push. There is no separate integrator role anymore.

GitHub `main` is the shared source of truth for anything the user should test.

## Current state

**Fair Trades v1.2.2 — native-accepted relationship pricing**, on top of **LEK Core v1.3** (Reroll/Rehost v0.21, Host Instant Start v0.1, UltraFast MP Startup v0.3.1, RAS MP Bridge v0.8.8) and **RAS wonder hotfix v0.8.9**.

Primary runtime: `internal/fair/UI/LEKFairTrades.lua`
Install/verify/uninstall, per component: `internal/fair/*.ps1`, `internal/ras-wonder/*.ps1`, `internal/core/{R,H,U,RAS}/*.ps1`
Combined, one-command: `internal/InstallAll.ps1`, `internal/VerifyAll.ps1`, `internal/UninstallAll.ps1`
Interactive menu: `internal/DevTool.ps1`

### Status

Fair Trades v1.2.2 is proven working: luxury swaps and Gold/GPT currency offers both complete on Accept in testing. Two known, low-severity follow-ups remain open (see `PROJECT_STATE.md`'s "Known, accepted follow-ups").

Core v1.3's actual install/uninstall scripts were imported into this repo on 2026-08-28 from the original component packages (previously only read-only verifiers lived here); a `pre-consolidation-2026-08-28` git tag preserves the repo's state from immediately before that import.

## Proven behavior / infrastructure

- LEK Core v1.3 is the frozen known-good core. Its packaging is now version-controlled here, but its patch logic must not be modified for Fair Trades or RAS wonder hotfix problems unless the issue is genuinely a core defect.
- `internal/InstallAll.ps1` installs core → RAS wonder hotfix → Fair Trades in the proven safe order (their file backups nest); `internal/UninstallAll.ps1` reverses it.
- The transient turn-start ready-signal approach works better than a `ContextPtr:SetUpdate` retry approach on the target multiplayer setup.
- Fair Trades' offer UI enters via a private `LuaEvents` bridge into EUI's own `LeaderMessageHandler` (patched into `diplotrade.lua`), not `UI.OnHumanOpenedTradeScreen` or a spoofed generic leader greeting.
- `UI.incTurnTimerSemaphore()`/`decTurnTimerSemaphore()`, installed in that same bridge, pauses Auto End Turn while an offer is open and releases it on Accept, Refuse, screen close, or dispatch failure.

## Known regressions that must not return

1. **No final-copy luxury offers.**
2. **No queued empty AI windows.** One selected AI session maximum per scan/turn.
3. **No stale scratch-deal mismatch.**
4. **No progressive turn slowdown.** Stay inside the shared 8-native-evaluation ceiling per scan.
5. **No strategic resources.** Luxury resources plus flat Gold/GPT only.
6. **No default greeting interruption.**
7. **Do not modify frozen Core v1.3's patch logic** for isolated extension problems.
8. **Auto End Turn must not advance through an unresolved offer** — turn-timer semaphore pause/release must stay balanced across every exit path.

## Desired Fair Trades behavior

Proactively offer deals resembling what the AI would normally accept/propose in manual diplomacy, with relationship affecting frequency and starting price, without making decent trades excessively rare.

Deal families: spare Luxury <-> spare Luxury; human spare Luxury -> AI flat Gold or GPT; AI spare Luxury -> human flat Gold or GPT. The seller retains at least one copy after a proactive luxury trade.

## Current debugging priority

Watch for the two open follow-ups in `PROJECT_STATE.md` actually manifesting in longer play sessions (a suppressed-then-resurfaced rejected offer; an unaffordable escalated GPT amount slipping past `IsPossibleToTradeItem`). Neither has been observed yet as of the last diagnostic capture.

## Diagnostic workflow

1. User runs `internal/CaptureState.ps1` (`CAPTURE_DEV_STATE.bat`) once after a failure.
2. Extract the `LEK_DEV_STATE_*.zip` and query `DB\LEK_FAIR_TRADES-1.db`'s `SimpleValues` table with Python's stdlib `sqlite3`/`zipfile` (no external tools needed) — see the diagnostic-key list in recent session history for what to look at (`OfferScanReason`, `OfferVisitedDueAIs`, `OfferNativeEvals`, per-AI `LastShape`/`LastShapeResult`/`PartnerRejected`, `LastShownAI`/`LastShownTurn`/`LastShownShape`, bridge fields).
3. Identify the narrowest failure reason from actual runtime state before proposing a fix.
4. Make a component-scoped edit, run `internal/InstallAll.ps1` or the specific component's `Install.ps1`, then `internal/VerifyAll.ps1` or the component's `Verify.ps1`.
5. Commit with the user's confirmation; push only after explicit confirmation.

## Instructions for future AI sessions

Read this file first, then `PROJECT_STATE.md`, then the latest versions of whatever files the task touches — don't assume an older chat message's code is still current if the repository differs.

Focus areas that have mattered repeatedly in this project:
- Civ V Lua API argument-count/signature mismatches (e.g. Gold's `IsPossibleToTradeItem` takes one fewer argument than GPT's).
- Native trade-deal valuation ordering: all search/valuation before `DoTradeScreenOpened()`, nothing after.
- Multiplayer event timing (turn-start message-queue busy states, the turn-timer semaphore).
- Ways to accomplish the requested behavior with less code — reuse `internal/LekTools.ps1` helpers rather than duplicating Steam-detection/file-patching logic.
- Any path that could open more than one diplomacy popup/session.
- Last-copy resource safety.
- Performance/repeated-native-call hazards against the 8-evaluation ceiling.
