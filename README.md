# Skill Lines

[Play in your browser](https://godot-li.itch.io/roguematcher) · [中文说明](README.zh_CN.md) · [0.0.1 release](https://github.com/LiGameAcademy/GodotRogueMatcher/releases/tag/0.0.1)

![Skill Lines promotional cover](docs/preview/cover.png)

**Five-in-a-row meets roguelite builds.** Move geometric pieces across a 9×9 board, line up five or more of the same color, and draft skills as your score grows. Keep space open, build explosive combinations, and see how long your board survives.

An open-source **AI-assisted vibe-coding tutorial project** by **Li Game Academy**. Human-directed design, implementation, testing, and iteration with Cursor and OpenAI Codex / ChatGPT are part of the learning process.

## In the 0.0.1 Web preview

- 32 skills with five rarity tiers, weighted offers, and an evolving Blast Core build.
- Persistent upgrades, limited-duration effects, color weights, and color / row / column clearing.
- Explicit color selection, foldable skill choices, special-piece tooltips, and a real next-turn piece preview.
- Score pop-ups, animated feedback, sound controls, and a low-effects option.
- Four independent tutorial exercises, help, pause, and end-of-run summary.
- English and Simplified Chinese. Choose **Language** on the start / pause menu; the preference is saved locally.

![English gameplay](docs/preview/gameplay-en.jpg)
![English skill choice](docs/preview/skills-en.jpg)

![中文界面](docs/preview/language-zh.jpg)

## Current development slice (unreleased 0.0.2)

The source now offers **Stage challenge** (default) and **Classic endless** in the F1 menu. Switching modes starts a new run; retry keeps the selected mode. The published 0.0.1 Web release remains the baseline described above.

In Stage challenge, each accepted move or manual detonation advances pressure. Refills grow from 3 to at most 6 pieces while the target remains unmet. Passing restores the base refill to 3 and earns one skill choice, keeping the board and build. There is no action deadline. Excess eligible action points carry over; each next stage still needs one new action. A full board takes priority over passing. The last stage completes the challenge without another card. Instant skill rewards affect total score, not stage progress.

The eight-stage targets and pressure intervals (4/4/4/3/3/3/2/2 actions) are experimental and editable in [StageConfig](gameplay/progression/stages/stage_config.tres). Each action pays its previously previewed refill; passing does not waive that cost. Direct matches still skip refills unless the board is fully cleared. Test this slice directly in the Godot editor; Web exports are reserved for release or Web-specific checks. Headless bot batches use stage rules by default; add `--legacy` after `--` to compare classic rules.

## How to play

Click a piece, then a reachable empty cell. Pieces can only travel through empty cells. Five or more matching colors in a horizontal, vertical, or diagonal line clear and score. A move without a direct line usually adds three pieces; a full-board clear also refills. A full board ends the run.

Score thresholds offer three skill cards. After acquiring the manual detonation upgrade, double-click a Blast Core to detonate it; this spends an action. Hover over special pieces to read their abilities.

| Control | Action |
| --- | --- |
| Mouse | Select and move; choose skills and colors |
| Esc | Pause / resume |
| F1 | Help / menu |
| F8 | Fast playback |
| F9 | Skip a skippable presentation |

## Run the source

Use **Godot 4.7.2** with matching export templates. No C# runtime is required.

```sh
git clone --recurse-submodules https://github.com/LiGameAcademy/GodotRogueMatcher.git
```

Import `project.godot` and run the main scene. The `godot_core_system` submodule supplies reusable localization, settings, triggers, and other core services; gameplay rules remain separate from presentation.

Run the headless GUT suite:

```sh
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Export a Web release with PowerShell:

```powershell
./tools/export_web.ps1 -GodotPath "C:/path/to/godot_console.exe" -BuildName web_preview
```

Serve `production/web_preview/` over HTTP, or upload the generated ZIP to an HTML5 host. See [directory guide](DIRECTORY.md) and [development notes](docs/README.md).

## Preview scope

Designed for desktop browsers with mouse and keyboard; 1280×720 or larger is recommended. Mobile touch controls and cross-refresh run continuation are not included. Balance is experimental. Missions and additional rescue pieces are planned, not shipped.

Settings, tutorial progress, and run records stay in local browser storage; this build has no telemetry upload endpoint. Clearing site storage removes those records.

## Learning, support, and credits

- [Patreon — Godot tutorials and indie development](https://www.patreon.com/cw/LiGameAcademy)
- [Bilibili](https://space.bilibili.com/8618918) · [YouTube](https://www.youtube.com/channel/UChFeMZTeF1HZbqVh_1HtN_w)
- [Report feedback](https://github.com/LiGameAcademy/GodotRogueMatcher/issues) or comment on [itch.io](https://godot-li.itch.io/roguematcher).

AI assistance was used for code, writing, and the promotional cover. The gameplay screenshots show the actual game. AI output is reviewed and tested; this project openly documents vibe-coding as a tutorial workflow.

The game is licensed under [GPL-3.0](LICENSE). Dependency licenses are retained in their respective folders; [Noto Sans SC](assets/fonts/README.md) uses the SIL Open Font License. Godot uses the [MIT license](https://godotengine.org/license/).
