# 设置与操作收拢（#28）

棋盘右侧只保留连携得分；快放、略过、低特效、音量和操作说明迁到独立的`ui/playback_settings/playback_settings.tscn`。临时技能状态继续在左侧构筑卡显示。顶部“设置”/F1、开始菜单和三选一均可打开同一面板。

Game继续拥有偏好应用和保存入口，设置控件通过信号请求变更。配置键和保存格式保持原值；初始化同步不触发保存，音量拖动即时预览、释放提交，拖动中关闭也保留最终值。

打开设置暂停表现和棋盘输入，关闭恢复原暂停状态及焦点。选卡时保留候选、目标、当前选择和确认状态；设置不产生行动、得分或重抽。“略过本次演出并返回”先关闭设置，再请求现有导演略过可跳步骤；原本暂停或正在选卡时禁用，必播动作仍需完成。设置中F8切换快放，F9请求略过，ESC/F1返回；调试快捷键不穿透。

真实查看位置记为`settings`，设置时间归暂停，不记作退出单局；关闭后恢复棋盘、演出、暂停、菜单或选卡的实际位置。重试先关闭面板，再初始化新局。

## 试玩与证据

1. 正常移动、演出中、ESC暂停后分别打开设置并返回，检查能否继续原操作。
2. 调整快放、低特效、音量；重启后检查偏好。演出时打开设置，点略过并返回，观察结算与输入恢复。
3. 三选一先选中一张卡，打开设置再返回，检查选中卡和确认按钮保留。
4. 从设置进入开始菜单，验证练习、语言、模式与新局入口仍可达。

自动回归覆盖暂停/焦点、选卡冻结、拖动保存、快捷键、跳过精确回放、重试、采集位置与中英布局；真人操作和整体观感仍待作者验收。

截图均为种子7、fixture_dye，同盘面/语言/视口，改动前基线为合并#106后的`e9f189f`。截图工具`tools/ux_capture/settings_capture.tscn`不导出Web；`--before`仅标注文件名，不切换代码版本。以下素材不参与引擎导入。

| 语言/视口 | 改动前 | 改动后 | 设置 |
| --- | --- | --- | --- |
| 中文1280×720 | [前](screenshots/settings/before_zh_CN_1280.png) | [后](screenshots/settings/after_zh_CN_1280.png) | [设置](screenshots/settings/settings_zh_CN_1280.png) |
| 中文1024×640 | [前](screenshots/settings/before_zh_CN_1024.png) | [后](screenshots/settings/after_zh_CN_1024.png) | [设置](screenshots/settings/settings_zh_CN_1024.png) |
| 英文1280×720 | [前](screenshots/settings/before_en_US_1280.png) | [后](screenshots/settings/after_en_US_1280.png) | [设置](screenshots/settings/settings_en_US_1280.png) |
| 英文1024×640 | [前](screenshots/settings/before_en_US_1024.png) | [后](screenshots/settings/after_en_US_1024.png) | [设置](screenshots/settings/settings_en_US_1024.png) |

后续#29已由作者选定深色极简仪表风，先确认静态样图，再独立推进背景及局部电子效果。本片保留现有视觉皮肤，不以工具收拢代替整体画风验收。
