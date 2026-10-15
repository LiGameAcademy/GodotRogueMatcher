# Skill Lines 0.0.2 — Release candidate

[Project / source](https://github.com/LiGameAcademy/GodotRogueMatcher) · [itch.io](https://godot-li.itch.io/roguematcher) · [中文说明](https://github.com/LiGameAcademy/GodotRogueMatcher/blob/feature/stage-challenge/README.zh_CN.md)

This is the 0.0.2 candidate package. Exporting it does not update the public itch.io page or create a GitHub release. See the adjacent build manifest for source identity and SHA256.

## Play

Move a piece to a reachable empty cell. Five or more matching colors in a horizontal, vertical, or diagonal line clear and score. A move without a direct match adds the previewed pieces; clearing the entire board also refills. A full board ends the run.

Choose Stage challenge (default) or Classic endless on the start menu. In Stage challenge, unmet targets increase refills from 3 to at most 5, including skill modifiers. Reach the cumulative target total to reset pressure and choose a skill. Instant skill scores also count. Each stage needs a new valid action; a full board takes priority. Complete eight stages to win, or continue with the same board, score, and build and further targets increasing by 1,000 per stage.

Build explosive and row/column-clearing chains. Manual abilities spend an action and have three uses per card per run; chains do not spend extra uses. Select a skill card, then confirm below the cards. Hover over special pieces for details. Browse the piece pool and filter/sort skill cards in the skill pool.

Esc pauses/resumes; F1 opens settings; F8 changes playback speed; F9 skips skippable presentation. Settings include language, sound, two themes, animated background, board signal, and low effects. Four independent tutorial exercises are available from the menu.

## 中文

0.0.2候选包：阶段挑战与经典无尽双模式；累计总分达标降压并三选一，未达标升压，补棋最多5枚。八阶段通关后可保留棋盘、总分与构筑继续挑战，后续每阶段目标增加1000分。

爆破手与行／列清除手支持升级和互相连锁；每张主动技能每局3次。技能先点选，再点击面板下方按钮确认。棋子池和技能池可查看，后者支持筛选与排序。Esc暂停／继续，F1设置，F8快放，F9略过允许跳过的演出。

明亮玩具／深色仪表主题可切换，动态背景和棋盘信号可分别关闭，低特效覆盖两者。背景按作者阶段性接受的现状保留；等待时间的真人统计留待后续。

## Platform and data

Desktop browsers with mouse and keyboard; 1280×720 or larger recommended. Mobile touch and cross-refresh run continuation are not included. Balance remains experimental.

Preferences and tutorial progress use local browser storage. Web disables the desktop telemetry collector and hides record-folder/export controls. Internal command recording does not provide a supported browser data download; use the desktop/editor build for playtest collection and export. There is no telemetry upload endpoint. Closing the browser is not a guaranteed final write.

Serve index.html through HTTP(S); opening a local file directly is unsupported. Godot 4.7.2 Compatibility, single-threaded, non-PWA. SharedArrayBuffer headers are not required.

## Credits and licenses

An open-source AI-assisted vibe-coding tutorial by Li Game Academy, developed with Cursor and OpenAI Codex / ChatGPT. [知识星球](https://wx.zsxq.com/group/28885154818841) · [Patreon](https://www.patreon.com/cw/LiGameAcademy)

Game: GPL-3.0. CoreSystem and font licenses are included in licenses/; font credits are in font_credits.md. Godot: [MIT license and third-party notices](https://godotengine.org/license/). Source and dependency revisions are recorded in the build manifest.
