# 技能连珠 · Skill Lines

[浏览器试玩](https://godot-li.itch.io/roguematcher) · [English](README.md) · [0.0.1 预览版本](https://github.com/LiGameAcademy/GodotRogueMatcher/releases/tag/0.0.1)

![技能连珠宣传封面](docs/preview/cover.png)

**五子连珠 + 肉鸽技能构筑。** 在 9×9 棋盘上移动几何棋子，组成同色五连获得分数，在技能三选一中逐步形成自己的爆破构筑，尽量维持棋盘空间。

这是老李游戏学院的 **AI 辅助 Vibe Coding 开源教程项目**。玩法设计由人主导，开发过程中使用 Cursor 与 OpenAI Codex / ChatGPT 完成实现、审查、测试和迭代。我们会把这种协作方式本身作为教程的一部分。

## 0.0.1 已实现

- 32 项技能、白绿蓝紫橙五档稀有度、加权技能池与爆破手前置升级链。
- 永久升级、持续回合效果、颜色权重调整及颜色／行列清理。
- 颜色清理须主动选色确认；技能面板可临时收起查看棋盘。
- 特殊棋子说明、真实补棋预览、分数漂字、音效与低特效选项。
- 四步独立新手练习、帮助、暂停与本局结算。
- 英文／简体中文／跟随系统切换，入口位于开始或暂停菜单，设置保存在本机。

![实际游戏画面](docs/preview/gameplay-en.jpg)
![技能选择](docs/preview/skills-en.jpg)

![中文界面](docs/preview/language-zh.jpg)

## 0.0.2 发布候选版

源码版本已更新为 **0.0.2**，尚待 Web 验收与正式发布。上方公开入口和旧截图仍对应 0.0.1；新版画面参见 [O3 验收](docs/o3_acceptance.md)。

- 开始菜单选择默认的**阶段挑战**或**经典无尽**；切换模式开始新局，重试保留模式。
- 底部显示累计总分／目标总分，选卡即时得分也推进目标。未达标持续升压，补棋从3枚升至**最多5枚，含技能修正**；达标恢复压力并三选一，保留棋盘、总分和构筑。每阶段至少一次新有效行动，满盘优先，没有硬行动死亡线。
- 完成八阶段后可以继续挑战，保留现有棋盘与构筑，之后每阶段目标总分增加1000。目标与每4行动升压仍为试调参数，见 [StageConfig](gameplay/progression/stages/stage_config.tres)。
- 爆破手与行／列清除手可升级跨度、十字并互相触发连锁。每张主动技能每局3次，连锁不额外扣次数。
- 技能先点选，再用面板下方按钮确认；棋子池与卡片式技能池可查看，支持Tag／稀有度／等级筛选和排序。
- 明亮玩具与深色仪表两套主题；播放、声音、背景、棋盘信号和低特效集中到设置。

上面的0.0.1清单保留为公开版本说明，不代表当前技能数量。日常仍在编辑器试玩，仅在发布或Web专项验证时导出。

## 玩法与操作

点击棋子，再点击可到达的空格；路径只能穿过空格。横、竖或斜向同色五连及以上即可消除。没有直接形成五连时按顶部预告补棋；全清后也会补棋。棋盘填满，本局结束。

得分达到门槛后选择技能；获取「主动爆破」升级后可以双击爆破棋子，占用一次行动。悬停特殊棋子查看效果。Esc 暂停／继续，F1 设置，F8 快速播放，F9 跳过允许略过的演出。

## 本地运行与验证

使用 **Godot 4.7.2**，克隆时包含子模块：

```sh
git clone --recurse-submodules https://github.com/LiGameAcademy/GodotRogueMatcher.git
```

导入 `project.godot`，运行主场景即可。`godot_core_system` 提供本地化、设置、触发器等通用能力，核心规则与表现分别维护。

```sh
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/rules,res://tests/integration -ginclude_subdirs -gexit
```

Web 导出参见 [English README](README.md#run-the-source)，目录参见 [DIRECTORY.md](DIRECTORY.md)。

## 预览版边界

面向桌面浏览器、鼠标与键盘，建议不小于 1280×720。手机触控和跨刷新续局尚未实现。数值仍在调整。背景按本次阶段性接受的效果保留，后续视觉打磨与等待时间分析另行安排。

设置与练习完成标记使用浏览器本地存储，没有遥测上传端点。Web关闭桌面采集器并隐藏记录目录／导出按钮；内部命令记录不代表提供了浏览器数据下载能力。正式采集与导出仍用桌面／编辑器版本。清空网站存储会移除偏好，本局不支持刷新续玩。

## 课程与支持

- [知识星球 · 老李游戏学院](https://wx.zsxq.com/group/28885154818841)
- [Patreon · Godot 教程与独立游戏开发](https://www.patreon.com/cw/LiGameAcademy)
- [哔哩哔哩](https://space.bilibili.com/8618918) · [YouTube](https://www.youtube.com/channel/UChFeMZTeF1HZbqVh_1HtN_w)
- [GitHub 问题反馈](https://github.com/LiGameAcademy/GodotRogueMatcher/issues) · [itch.io 评论区](https://godot-li.itch.io/roguematcher)

代码、文案和宣传封面使用了 AI 辅助；截图来自实际游戏。人工审查与可运行验证是交付流程的一部分，我们不回避这个项目的 Vibe Coding 属性。

项目采用 [GPL-3.0](LICENSE)，依赖保留各自许可。[Noto Sans SC 字体](assets/fonts/README.md)采用 SIL Open Font License；Godot 引擎采用 MIT 许可。
