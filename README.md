# LEKMOD 30.7 Development Workspace v1.2.1

This is the clean Git-backed workspace for the custom Civilization V / LEKMOD stack.

## Root folder

Only these user-facing files should normally be visible at the root:

- `LEK_DEV_TOOL.bat` — main menu; use this for normal work.
- `GITHUB_SETUP.bat` — one-time Git connection/push.
- `README.md` — this file.
- `PROJECT_STATE.md` — current technical state.
- `.gitignore` — keeps machine-local files out of Git.

Everything else is intentionally under `internal/`. The `.bat` launchers are the files you run; the `.ps1` files are implementation files and no longer sit beside duplicate-looking launchers in the root.

## Frozen foundation

LEK Core v1.3 remains installed and frozen:

- Reroll / Rehost v0.21
- Host Instant Start v0.1
- UltraFast MP Startup v0.3.1
- RAS MP Bridge v0.8.8

This workspace contains only the four read-only core verification scripts needed for development. It deliberately does not duplicate the full core installer/uninstaller tree. If the core ever needs reinstalling, use the separate known-good `LEK_Core_v1_3.zip`.

## Fair Trades

Fair Trades v1.0.1 lives under `internal/fair/`. Its runtime remains `LEKFairTrades.lua` + `LEKFairTrades.xml`, and its only current existing-file hook is the stable marked loader in LEKMOD `InGame.lua`.

## Normal workflow

Run `LEK_DEV_TOOL.bat`. The menu saves the Civ V path, verifies the baseline/core, installs/verifies/removes Fair Trades, captures one diagnostic ZIP, and pulls GitHub updates.

Machine-local state is written under `local/` and is ignored by Git.

## GitHub

Canonical repository: `curosue1232/civ5-lekmod-dev`.

Run `GITHUB_SETUP.bat` once from the workspace folder. v1.2.1 fixes first-run setup when the local repository has no `origin` remote yet. It uses Git for Windows only; GitHub CLI is not required.

**Do not extract this over the old v1.0/v1.1 workspace.** A clean v1.2 folder can be updated in place to v1.2.1 because the file layout is unchanged.
