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

## 0.0.2 release candidate

Source version: **0.0.2**, pending Web release validation and publication. The public links above still serve the 0.0.1 preview. The screenshots above also show that earlier version; see [current visual evidence](docs/o3_acceptance.md).

- Choose **Stage challenge** (default) or **Classic endless** on the start menu. Changing mode starts a new run; retry retains the mode.
- Stage targets use cumulative total score, including instant skill rewards. Unmet targets increase refills from 3 to **at most 5**, including skill modifiers. Passing resets pressure and offers three skills; board, score, and build carry over. Each stage requires one new valid action. A full board takes priority; there is no hard action deadline.
- Complete eight stages to win, then optionally continue with the same board and build. Further stages add 1,000 to the target total each time. Initial targets and four-action pressure intervals are experimental: [StageConfig](gameplay/progression/stages/stage_config.tres).
- Build Blast Cores or row/column sweepers, upgrade their span and cross patterns, and trigger special-piece chains. Manual abilities have three uses per card per run; chain reactions do not spend extra uses.
- Select a skill card, then confirm below the cards. Browse the piece pool and skill pool, including tag/rarity/level filters and sorting.
- Light toy and dark instrument themes; settings contain playback, sound, background, board signal, and low-effects controls.

The 0.0.1 section describes the earlier public build, not the current skill count. Daily testing stays in the Godot editor; Web builds are reserved for release or Web-specific checks.

## How to play

Click a piece, then a reachable empty cell. Pieces can only travel through empty cells. Five or more matching colors in a horizontal, vertical, or diagonal line clear and score. A move without a direct line adds the previewed pieces; a full-board clear also refills. A full board ends the run.

Score thresholds offer three skill cards. After acquiring the manual detonation upgrade, double-click a Blast Core to detonate it; this spends an action and one manual use. Hover over special pieces to read their abilities.

| Control | Action |
| --- | --- |
| Mouse | Select and move; choose skills and colors |
| Esc | Pause / resume |
| F1 | Settings |
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
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/rules,res://tests/integration -ginclude_subdirs -gexit
```

Export a Web release with PowerShell:

```powershell
./tools/export_web.ps1 -GodotPath "C:/path/to/godot_console.exe" -BuildName web_preview
```

Serve `production/web_preview/` over HTTP, or upload the generated ZIP to an HTML5 host. See [directory guide](DIRECTORY.md) and [development notes](docs/README.md).

## Preview scope

Designed for desktop browsers with mouse and keyboard; 1280×720 or larger is recommended. Mobile touch controls and cross-refresh run continuation are not included. Balance is experimental. The background remains at its accepted prototype quality; further visual tuning and waiting-time analysis are deferred.

Settings and tutorial progress use local browser storage. Web disables the desktop telemetry collector and hides record-folder/export controls; it does not provide a supported playtest-data download. Internal command records are not a browser export guarantee. Clearing site storage removes saved preferences. Nothing is uploaded to a telemetry endpoint.

## Learning, support, and credits

- [Patreon — Godot tutorials and indie development](https://www.patreon.com/cw/LiGameAcademy)
- [Bilibili](https://space.bilibili.com/8618918) · [YouTube](https://www.youtube.com/channel/UChFeMZTeF1HZbqVh_1HtN_w)
- [Report feedback](https://github.com/LiGameAcademy/GodotRogueMatcher/issues) or comment on [itch.io](https://godot-li.itch.io/roguematcher).

AI assistance was used for code, writing, and the promotional cover. The gameplay screenshots show the actual game. AI output is reviewed and tested; this project openly documents vibe-coding as a tutorial workflow.

The game is licensed under [GPL-3.0](LICENSE). Dependency licenses are retained in their respective folders; [Noto Sans SC](assets/fonts/README.md) uses the SIL Open Font License. Godot uses the [MIT license](https://godotengine.org/license/).
