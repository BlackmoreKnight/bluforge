# CLAUDE.md — BluForge project notes

Operational context for AI coding sessions working on this addon. Read this first.

## What this is
**BluForge** — a Blue Mage focused [Ashita v4](https://www.ashitaxi.com/) addon for **FFXI**. It combines
BluSets-style spell setting with a BluCheck-inspired ImGui UI and a job-trait planner.

- Repo: https://github.com/BlackmoreKnight/bluforge
- Derived from atom0s' BluSets / BluCheck (Ashita Development Team). Licensed GPL-3.0.

## Development layout (dev vs runtime are kept separate)
- **Development / git repo (source of truth):** this repository checkout. All git work — commits, pushes, the
  workflow, README/LICENSE/docs, `build.ps1`, `deploy.ps1` — happens here. Keep the checkout outside the live
  Ashita install so development stays separate from what runs in-game.
- **In-game runtime copy:** the Ashita `addons/bluforge` directory holds **only the files needed to run** the
  addon (`bluforge.lua`, `blu.lua`, `ui.lua`, `data/bludata.lua`, `data/spells.json`). It is **not** a git
  checkout and should never contain `.git`, docs, or tooling.
- After changing code, run `deploy.ps1 -Target <Ashita>\addons\bluforge` to copy the runtime files into the
  addons directory so the changes take effect in-game. Do all editing in the repo, never in the runtime copy.

## Compatibility (important)
Tested **only on retail FFXI with Ashita v4.30**. Memory signatures (in `blu.lua`) and packet behavior may
differ on private servers / other versions — do not assume otherwise.

## Files
- `bluforge.lua` — addon entry: meta, events (load/command/packet_in/d3d_present), slash commands (`/bluforge`, `/bf`, `/bforge`).
- `ui.lua` — all ImGui UI: spell browser, slot editor, save/load/apply, trait planner, spell info.
- `blu.lua` — spell-setting library copied verbatim from BluSets (safe/fast packet modes, memory reads). Keep in sync with upstream; avoid editing.
- `data/bludata.lua` — set-point costs per spell + the job-trait table + `compute_traits()`.
- `data/spells.json` — "learned from" data (zone → mobs), keyed by spell id. Zone keys may be numeric ids or zone-name strings.

## Data sources (when extending)
- Set-point costs (`blu_points`) originally extracted from XIUI's `horizonspells.lua`.
- Job-trait thresholds + per-spell points: BG-Wiki `Blue_Mage_Job_Traits`.
- Set/point/slot limits by level: BG-Wiki `Blue_Mage` chart (base 55 pts at lvl 99 main; +5 Assimilation merit; +20 Blue Magic Point Bonus job points).
- Missing learn-from entries were filled from individual BG-Wiki spell pages.

## Key implementation notes
- Spell ids: resources use full ids (513+). The equip packet uses `id - 512`; conversions happen in `ui.apply_set` and `ui.load_from_game`.
- Limits are deterministic from the level chart (`POINTS_BY_BRACKET` / `SLOTS_BY_BRACKET` in `ui.lua`), keyed by effective BLU level (main level if BLU main, sub level if BLU sub). Main adds `GetAssimilationPoints()`; the JP bonus is taken from the game's reported max, bounded to `base+20`.
- Spells above the current BLU level, and slots beyond the level's set limit, are disabled in the UI and rejected on assign.
- Browser colors: bright green/red = known/unknown settable; muted = non-settable (cost 0, `n/a`); `[Lv]` = above level.
- Persisted settings (Ashita `settings` lib): the two browser toggles (`filter_known`, `filter_settable`) only. The trait-bonus gift level is auto-detected from job points, not stored.
- `data.bludata` is loaded via `require('data.bludata')`. `spells.json` via `io.open(addon.path .. '/data/spells.json')`.

## Validation without the game
LuaJIT is available. Syntax-check: `luajit -bl <file> /dev/null`. The trait engine can be unit-tested with a
minimal `T` stub (sugar table). UI/packet behavior can only be confirmed in-game.

## Git / release workflow
- **Auth:** pushing uses whatever git authentication the contributor has configured locally (an SSH key, a
  per-repo deploy key, or a credential helper) — none of which lives in this repo. In an AI sandbox, network
  git commands must run with the **sandbox disabled**.
- **Releases are automated.** `.github/workflows/release.yml` triggers on any `v*` tag push, builds a
  runtime-only zip (the 3 Lua files + `data/`, under a `bluforge/` folder, forward-slash paths) and publishes a
  release via the `gh` CLI using the built-in `GITHUB_TOKEN`. No PAT, no third-party actions.
- **To cut a release:** bump `addon.version` in `bluforge.lua`, commit, then:
  `git tag vX.Y && git push origin main vX.Y`
- `build.ps1` reproduces the release zip locally for testing (`.\build.ps1`).
- Commit messages end with the `Co-Authored-By: Claude ...` trailer. Only commit/push when asked.
