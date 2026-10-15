# 0.0.2 Web 发布候选验收（#10）

状态：候选准备完成，尚未正式发布。作者已确认O3按现状收口，背景不再阻断本版；等待数据留待后续。#111已合并，feature/stage-challenge已同步至d2291ee。本PR继续#10，不关闭发行任务。

## 构建身份与修复

候选包为`production/web_0_0_2_rc2.zip`，源提交`961d2a6`，Godot4.7.2，Release / Compatibility / single-threaded。构建时源码干净，CoreSystem子模块版本与Git记录一致。[构建清单](validation/web_0_0_2_rc2.build.json)保留完整源提交、子模块、规则版本、配置文件指纹、PCK和ZIP SHA256。

ZIP SHA256：`34B2B2C761BF6A3E822C4A5EC738813BBFDC78F3EB16F8F5C1A04EAD00B946D0`。

RC1虽导出成功，Chrome实际启动报TelemetryReader缺失：运行时TelemetrySummary依赖tools下的类，而Web预设排除tools目录。将读取器连同UID迁至services/telemetry，内容不变；分析工具继续使用同一类。RC1判失败，不得发布；RC2两浏览器控制台未再出现脚本错误。预设仍排除工具与测试，不把开发代码整体装进发行包。

版本号更新0.0.2；中英README、包内发行说明与导出指南同步当前规则：补棋含修正最多5枚、累计总分目标、即时分也推进、通关继续、主动卡每局3次、选卡先点后确认、F1设置、两套主题。

## 自动与浏览器证据

- 原运行基线完整回归：529/529测试，19,508断言，详见[O3报告](o3_acceptance.md)。#111只改文档。
- 本次版本／发布流程与本地化：2脚本11/11测试，511断言；将记录版本测试从写死0.0.1改为验证ProjectSettings权威版本来源。
- 读取器迁移后：采集规则、批量写入与场景集成3脚本24/24测试，170断言。未修改读取算法或数据格式。
- PowerShell语法与git diff检查通过；导出脚本89行，发布测试208行，读取器56行。代码审查未发现阻断问题。

2026-10-15，本机HTTP服务，仅验证RC2 Release。Playwright驱动已安装Chrome155.0.8059.40与Edge155.0.4283.45，headless + SwiftShader软件WebGL；不能据此推断目标机器GPU性能或真人操作手感。以下中英/视口是实际抽样组合，并非全笛卡尔积。

| 检查 | 实际结果与证据 |
| --- | --- |
| Chrome中文1280×720启动 | 0.0.2开始页、无脚本错误；[截图](screenshots/release_0_0_2/chrome_start_zh.png) |
| Chrome正常移动与补棋 | 红棋移至上方空格，行动0→1、棋子5→8、下批预告更新；[截图](screenshots/release_0_0_2/chrome_move_zh.png) |
| Chrome设置、返回与暂停入口 | F1打开、Esc返回；设置到开始菜单并进入练习，操作有效 |
| Chrome主题／低特效1024×640 | 明亮切深色、开启低特效；独立开关和底部返回可见；[截图](screenshots/release_0_0_2/chrome_settings_small_zh.png) |
| Chrome练习前三步与选卡 | 真实鼠标完成五连与补棋，三选一点选计分倍率后确认，进入第4步；[选卡截图](screenshots/release_0_0_2/chrome_tutorial_cards_small_zh.png)。未操作完成第4步，不宣称完整教学通过 |
| Edge英文1280×720启动 | 英文开始页与0.0.2正常；[截图](screenshots/release_0_0_2/edge_start_en.png) |
| Edge英文1024×640正式棋盘 | 点击Play，棋盘、顶部预告、底部进度和设置按钮可见；[截图](screenshots/release_0_0_2/edge_board_small_en.png) |
| 浏览器控制台 | 上述两浏览器操作期间无pageerror或console.error；不代表任意长局均已测 |

## 发布前仍需验收

- 浏览器实际完整终局／重试／八阶段完成及继续挑战；两模式切换；完整四步教学；池界面筛选排序及查看返回；刷新后的偏好持久化。相关桌面自动案例已通过，不能代替Web实测。
- 实机硬件渲染下的声音、长局表现及低特效可读性；Safari/Firefox和手机未测，本版目标仍是桌面Chrome/Edge。
- itch.io嵌入与全屏、存储权限和公开入口操作；当前localhost不是公开部署。

为控制成本，不为本片再运行整套规则或新建分析工程；保留明确待测项，供作者在发布前实际试玩。

## 数据、许可与发布顺序

Web禁用桌面遥测采集器并隐藏记录目录／导出按钮。内部RunRecorder命令JSONL不等于提供浏览器下载入口；需用于分析的单局请在编辑器／桌面采集。设置和练习标记使用浏览器本地存储，清理站点数据会删除；刷新不续局，关浏览器不保证最后写入。没有上传端点。

候选ZIP附游戏GPL-3.0、CoreSystem许可、Noto Sans SC OFL与字体鸣谢，Godot许可入口见包内RELEASE说明。导出预设排除测试、工具与设计文档；源码及子模块版本可按清单还原。

本PR验收合并后，从最终合并提交重新导出正式包并保存新哈希，再创建0.0.2 tag／GitHub Release并更新现有itch.io页面；分别打开实际公开入口核对版本。不把RC2的源提交改写成合并提交。回退保留现有0.0.1发行包／tag与候选构建清单，更新失败时恢复上一版。

公开入口当前仍为0.0.1：https://godot-li.itch.io/roguematcher 。本片不创建Release、不上传itch.io；#10保持开放，#11图文／视频日志随后推进。

## 作者最终Web验收（2026-10-15）

作者确认已覆盖完整四步教学、模式切换、池界面返回、终局重试及通关继续挑战，并明确授权发布。以上为作者实际试玩反馈，与前文自动化抽样分开记录。公开版本、构建哈希及上传结果以#10最终发布记录为准；硬件性能、其他浏览器和移动端不据此宣称已测。
