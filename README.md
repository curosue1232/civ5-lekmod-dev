# LEKMOD 30.7 Development Workspace

This is the clean Git-backed workspace for the custom Civilization V / LEKMOD stack.

## Root folder

User-facing files at the root:

- `LEK_DEV_TOOL.bat` — main interactive menu; use this for normal dev work (Civ path, baseline/core verify, Fair Trades and RAS wonder hotfix install/verify/remove, diagnostic capture, GitHub sync).
- `INSTALL_ALL.bat` / `VERIFY_ALL.bat` / `UNINSTALL_ALL.bat` — install, verify, or uninstall the whole stack (Core v1.3 → RAS wonder hotfix → Fair Trades) in one command, without the interactive menu.
- `GITHUB_SETUP.bat` — one-time Git connection/push.
- `README.md` — this file.
- `PROJECT_STATE.md` / `AI_HANDOFF.md` — current technical state and AI-assistant handoff notes.
- `.gitignore` — keeps machine-local files out of Git.

Everything else is intentionally under `internal/`. The root `.bat` launchers are the files you run; the `.ps1` files underneath are implementation files.

## Frozen foundation

LEK Core v1.3 (Reroll/Rehost v0.21, Host Instant Start v0.1, UltraFast MP Startup v0.3.1, RAS MP Bridge v0.8.8) remains frozen — its patch logic is never modified for extension problems. Its actual install/uninstall scripts now live under `internal/core/{R,H,U,RAS}/` (imported unchanged from the original packages), alongside the existing `internal/core/*Verify.ps1` verifiers. A `pre-consolidation-2026-08-28` git tag preserves the workspace's exact state from immediately before that import, as a recovery point.

## RAS wonder hotfix and Fair Trades

RAS wonder hotfix v0.8.9 (`internal/ras-wonder/`) and Fair Trades v1.2.5 (`internal/fair/`) are independent extensions on top of the frozen core — neither depends on the other. Fair Trades' runtime is `LEKFairTrades.lua` + `LEKFairTrades.xml`, entering play through a private `LuaEvents` bridge into EUI's own trade-offer handler rather than patching a generic leader greeting.

## Normal dev workflow

Run `LEK_DEV_TOOL.bat` for the interactive menu, or `INSTALL_ALL.bat`/`VERIFY_ALL.bat` directly for a non-interactive full-stack cycle. Machine-local state is written under `local/` and is ignored by Git.

## Producing a standalone distributable package

`internal/BuildPackage.ps1` assembles a clean, self-contained copy of everything needed to install the combined stack (core + RAS wonder hotfix + Fair Trades) — no git or dev tooling required — into `dist/<name>/` (and optionally a matching zip), for handing to someone who isn't working out of this git workspace. It excludes dev-only files (`internal/docs`, `BaselineCheck.ps1`, `CaptureState.ps1`, `GitHubSetup.ps1`, `DevTool.ps1`, `local/`, this repo's own docs). Run it whenever a fresh package is needed; it's regenerated from the real source each time, so it can't silently drift.

## GitHub

Canonical repository: `curosue1232/civ5-lekmod-dev`.

Run `GITHUB_SETUP.bat` once from the workspace folder. v1.2.1 fixes first-run setup when the local repository has no `origin` remote yet. It uses Git for Windows only; GitHub CLI is not required.

**Do not extract this over the old v1.0/v1.1 workspace.** A clean v1.2 folder can be updated in place to v1.2.1 because the file layout is unchanged.
