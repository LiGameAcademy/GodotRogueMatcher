# GameTheme：两套可切换的视觉主题（#29）

设置按钮 / F1 → 画面主题。提供默认的「明亮玩具」和「深色仪表」；选择立即应用并沿用表现偏好文件保存。旧文件没有此字段、或主题名失效时回退明亮玩具。低特效独立于主题，切换不重建棋盘，不重抽候选、不改变当前选卡、暂停、分数、规则或随机流。

两套主题共用布局：左侧滚动构筑＋紧凑连携，棋盘在右；整体作为一组居中，外侧保留空白。连携闲时压缩，得分后在固定区域滚动。深色采用近直角、低对比底色，明亮采用浅底、柔和几何棋子；颜色与形状的对应关系保持一致。技能卡用稀有度色条、选中轮廓体现层级。

## 职责与资源

| 文件 | 职责 |
| --- | --- |
| `gameplay/presentation/game_theme/game_theme.gd` | 只读 Resource，组合原生 Theme、BoardAppearance、既有反馈/漂字/进度条配置及背景色 |
| 同目录 `light_toy.tres` / `dark_instrument.tres` | 两套配置入口；`*_ui.tres` 是原生 Godot Theme |
| `game_themes.gd` | 当前预设列表与失效回退，不持有局内状态 |
| `ui/game_theme_ui.gd` | 在 Game 显式传入的 UI 根节点上应用皮肤，保留布局、字体大小、筛选和选择状态 |
| `gameplay/game.gd` | 接收设置请求、保存偏好，向 HUD/BoardView/菜单/弹窗下发主题 |
| `board_view.gd`、`cell.gd`、`chess_piece.gd` | 消费视觉配置；后续生成或重建的对象继承主题 |

不新增全局 ThemeManager，不将配置传入规则层。配置共享且只读；Cell、ChessPiece、GoalProgress 的 ShaderMaterial 在各实例 ready 时复制，动态 StyleBox 修改前复制。切换时已有移动、翻卡和进度条 Tween 继续；已发出的光点、爆炸和扫线保留出生时颜色直到结束，新效果使用新主题。反馈配置只调整配色，时序保持原值。

原生 Theme 负责 UI 颜色、StyleBox 与常量；GameTheme 补充 Node2D 棋盘、棋子、静态背景和效果配置。当前使用已有材质增加参数，#30 背景动画与 #31 后处理仍分别推进。本片不新增背景动画，不发布 Web 构建，也不代表整体 O3 已验收。

## 实机对照与 review

截图来自 Compatibility 渲染，主界面种子7、`fixture_dye`；特殊状态使用 `fixture_line_cross`。都是确定性展示夹具，不能作为真人平衡数据。截图工具：`tools/ux_capture/game_theme_capture.tscn`，输出 `.godot/issue29_captures`，不参与正式导出。

| 内容 | 明亮玩具 | 深色仪表 |
| --- | --- | --- |
| 中文1280×720 | [主界面](screenshots/game_themes/light_toy_zh_CN_1280.png) | [主界面](screenshots/game_themes/dark_instrument_zh_CN_1280.png) |
| 英文1024×640 | [主界面](screenshots/game_themes/light_toy_en_US_1024.png) | [主界面](screenshots/game_themes/dark_instrument_en_US_1024.png) |
| 三选一、已选未确认 | [卡牌](screenshots/game_themes/light_toy_cards.png) | [卡牌](screenshots/game_themes/dark_instrument_cards.png) |
| 英文设置1024×640 | [设置](screenshots/game_themes/light_toy_settings_en_US.png) | [设置](screenshots/game_themes/dark_instrument_settings_en_US.png) |
| 特殊棋子、选中、路径 | [正常](screenshots/game_themes/light_toy_special_states.png) / [低特效](screenshots/game_themes/light_toy_special_low.png) | [正常](screenshots/game_themes/dark_instrument_special_states.png) / [低特效](screenshots/game_themes/dark_instrument_special_low.png) |

改动前同盘面对照沿用 [#28 截图](playback_settings.md)。完整中英大小视口截图在同目录保留。

建议作者实际试玩：两主题分别移动、扫线、爆破和选卡；先选中候选再进入设置切换，返回确认；检查棋子池和技能池、筛选、新获得构筑卡；开关低特效后重复操作。F6/F7/F10/F11 等现有调试盘面可用于观察特殊棋子。截图已检查，整体美感、长期读盘与平台性能仍待实际验收，不据截图宣称提升了传播效果。

自动测试 `test_game_themes.gd` 覆盖保存/回退、设置暂停与焦点、规则及随机流不变、选卡保留、A/B 材质隔离、移动中切换后精确文件回放，以及重试/新卡继承。布局测试覆盖中文和英文、小窗口与放大窗口；验证记录见本 PR。
