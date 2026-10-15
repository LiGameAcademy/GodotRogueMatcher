# 0.0.2 · O3 整体验收（#9 / #4）

实现基线：`feature/stage-challenge`，合并#110后的`381061cd869719ff9a34c9077d33b1fdc2a9b96e`，Godot4.7.2 Compatibility。本次只整理最终回归与组合画面证据，不改玩法、参数或发布版本号，不新增视觉机制。工程仍显示0.0.1，正式版本、Web和发行身份由#10统一更新。

## 交付与作者反馈

| 实现片 | 合并 | 本轮认定 |
| --- | --- | --- |
| #28设置收拢 | #107 | 作者试玩通过；右侧工具进入设置/F1 |
| #29两套GameTheme | #108 | 作者试玩通过；补回框体、按钮轮廓，移除格子渐变；构筑名称16/描述13/Tag11 |
| #30流动背景 | #109 | 作者允许阶段性合并，明确未完全满意；保留#9整体打磨，不能写成最终满意 |
| #31棋盘信号 | #110 | 作者授权合并；本轮继续做整体操作与组合画面检查 |

本次捕获以最终基线运行，默认同时开启动态背景与棋盘信号。此前#30/#31各自的截图、演示和帧时间是隔离效果对照，不能冒充这次组合状态或Web实测。

## 已定位问题与结果

| 实际反馈 | 本版处理与证据 |
| --- | --- |
| 右HUD工具、说明过密 | 工具集中到设置/F1，构筑与连携同侧；[改前同盘面](screenshots/settings/before_zh_CN_1280.png)对照下文最终主界面 |
| 极简处理后缺少框体、按钮/卡牌边界弱 | 恢复面板底板与细边框，普通卡轮廓和选中轮廓区分；最终截图保留边界 |
| 格子纵向渐变像凸起按钮 | 移除格子渐变，使用纯色哑光；[渐变阶段截图](https://github.com/LiGameAcademy/GodotRogueMatcher/blob/3ed9fb2/docs/screenshots/game_themes/light_toy_zh_CN_1280.png)对照最终纯色格 |
| 构筑文案层级不突出 | 名称16、描述13、Tag11；等级/次数12，两主题共用字号 |
| 开局先深色后亮色 | 在初始补棋首次await之前应用偏好主题；`test_saved_theme_is_applied_before_initial_spawn_yields`覆盖两主题 |
| 缓慢背景不明显 | 对比/流速试调并加独立开关；作者仅阶段性接受，满意度仍待打磨，不能列为问题完全解决 |

不据截图编造“AI感改善百分比”；作者每轮的具体反馈及授权合并状态是体验判断来源。

## 最终画面

复用`tools/ux_capture/game_theme_capture.tscn`，种子7、固定染色盘，中英及1280×720/1024×640；选卡为三张真实Resource的UI展示夹具。记录/采集/偏好保存均关闭，不产生真人样本。以下仅保留有代表性的8张截图；完整组合矩阵的布局由现有测试及此次截图检查共同覆盖。

| 画面 | 明亮玩具 | 深色仪表 |
| --- | --- | --- |
| 中文1280×720 | [主界面](screenshots/o3_acceptance/light_toy_zh_CN_1280.png) | [主界面](screenshots/o3_acceptance/dark_instrument_zh_CN_1280.png) |
| 英文1024×640 | [主界面](screenshots/o3_acceptance/light_toy_en_US_1024.png) | [主界面](screenshots/o3_acceptance/dark_instrument_en_US_1024.png) |
| 英文设置1024×640 | [设置](screenshots/o3_acceptance/light_toy_settings_en_US.png) | [设置](screenshots/o3_acceptance/dark_instrument_settings_en_US.png) |
| 三选一、已选未确认 | [卡牌](screenshots/o3_acceptance/light_toy_cards.png) | [卡牌](screenshots/o3_acceptance/dark_instrument_cards.png) |

截图检查：棋盘/信息栏边界、顶部预告与棋子池、底部分数条、横卡字号层级、三选一卡片和确认按钮可见；英文小窗口的设置及两个视觉开关无截断。最终组合未发现新的截图遮挡问题；这不替代长局读盘、触发反馈和操作舒适度判断。

隔离效果与特殊棋子对照：[GameTheme](game_themes.md)、[背景与启动修复](background_flow.md)、[棋盘信号](board_signal.md)。#31隔离截图的变化像素仅在棋盘内，HUD未参与后处理；最终界面保留该渲染层级。

## 规则与操作回归

本轮在上述合并提交上运行自有`tests/rules`与`tests/integration`完整GUT回归，不包含第三方addons测试与旧演示脚本。结果为75个脚本、529/529项测试、19,508条断言通过，392.651秒，退出码0，未出现SCRIPT ERROR。保留[命令、范围和结果摘要](validation/o3_regression.json)；本机完整日志为`.godot/issue9-full-tests.log`。不将此前分片的通过次数相加作为新结果。

| 验收面 | 现有证据入口 |
| --- | --- |
| 普通移动、坐标及拾取 | `test_game_layout`的首尾格拾取/移动；`test_input_buffer`的缓冲与重试清理 |
| 技能确认、选色与查看返回 | `test_skill_card_selection`、`test_skill_target_ux`、`test_skill_pool` |
| 暂停、快放、跳过与恢复 | `test_playback_settings`、`test_feedback_settings`、`test_skip_recovery`；含固定案例快照/得分一致性断言 |
| 经典/挑战切换、教学与重试 | `test_release_flow`、`test_stage_scene` |
| 满盘/阶段完成/继续挑战/结束 | `test_stage_scene`、`test_reward_presentation`及规则层挑战案例 |
| 两主题、启动时机及资源隔离 | `test_game_themes`、`test_game_background`、`test_board_signal` |
| 普通/连锁/低特效表现 | `test_line_clear_visual`、`test_reward_presentation`、`test_score_floats`及上述反馈测试 |
| 实际文件精确回放 | 主题、背景、棋盘信号和技能集成案例，配合规则层命令/回放测试 |
| 基础数据记录 | `test_telemetry_scene`及规则层采集/恢复案例；不在此片扩展分析 |

通过固定案例可以证明这些路径中的一致性断言成立，不能解释为所有随机盘面的穷尽证明。真实手感与背景满意度单列，不从自动测试推断。

## 等待与性能：区分口径

渲染性能已有[背景帧间隔](background_flow.md#桌面帧间隔基线)和[棋盘信号帧间隔](board_signal.md#桌面帧间隔基线)，均为桌面隔离效果的短样本，记录机器、视口、P50/P95/P99；不是玩家思考时间，也不是一次完整演出的等待时间。

基础采集按`inactive > pause > choice > busy > input`互斥记录区间。`input`表示可操作期间，不能当作点击到响应的输入延迟；可操作区间也不能直接证明玩家一直在思考。本轮未新增人体行为推断，也不拿测试固定帧率下的耗时当真人等待分布。

本轮核对未找到对应最终界面的真人思考/演出/输入等待P50/P90报告，列为**待补证据**。沿作者暂不集中做数据分析的安排，继续保留基本记录，不要求手填Excel、不新增机器人批次或分析工程。#4已有勾选不能单独作为这些数值的来源；#9保持开放，等待作者确认整体体验与该项后续安排。

## 当前结论与下一步

独立实现切片已获合并授权，进入O3整体验收；本片不自动关闭#9/#4，不导出或发布Web，不创建GitHub Release/itch包。

待作者结合本次证据确认：两套主题读盘与操作是否足以进入发布验收，背景的已知不足如何继续跟踪，以及等待分布的缺失是否作为后续采样项。确认之后再按#10做版本信息、Web浏览器矩阵和正式发布；图文/视频开发日志仍走#11。代码质量指导中的奖励单例/旧道具桥重构继续独立安排，不混入本次视觉验收。
