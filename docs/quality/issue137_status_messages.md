# #137 HUD状态消息：稳定ID与双语边界

## 身份与范围

- 开发基线：`1a03cb19d7cde1570edfecbc56e1fd3bfa878407`，目标分支`develop/0.0.3`。
- 本片仅迁移HUD底部StatusLabel及其正文/tooltip生产者；不改布局、播放政策、规则、奖励消费、候选、随机、采集schema或技能描述。
- #160未在本片实施。正式恢复仍等待O1候选/版本/采集接口稳定；本片不启用SaveManager。
- 本地独立工作树；主工作树的project.godot排序及UID变化未动，课程仓库指针未动。

## 已复现与证据边界

原基线Hud保存`_status_source`并执行`tr(text)`。Game终局先调用`StageText.end_title()`翻译，再把结果传给HUD。受控探针加载基线原Hud脚本：英文显示`Board full. Run over!`后切中文，仍显示英文，`BASELINE_DEFECT_REPRODUCED=true`。这证明当前实现存在已翻译文字缓存问题，不等于锁定作者0.0.2 Web截图报告的唯一根因。

静态盘点还发现输入缓冲返回的两条中文提示缺少原game.csv译文，奖励内部reason直接进入HUD，以及演出失败拼接中文/内部reason。旧Web具体残留动作仍未观察，保留该限制。

## 实现与唯一所有权

| 职责 | 实现 | 边界 |
| --- | --- | --- |
| 唯一手工文案 | localization/game.csv的32个hud.status.*条目 | 原有其它文案保留，translation是引擎生成产物 |
| 模板读取/校验/格式化 | ui/hud_status_messages.gd | 读取当前受支持语言的CSV生成资源，拒绝缺键/空译文/原始ID/坏占位符；不跨语言回退 |
| 当前消息缓存 | ui/hud.gd | ID＋独立参数副本，正文/tooltip共享渲染；语言刷新不执行原操作 |
| 初始化 | hud.tscn默认提示留空，Hud._ready经同一ID入口 | 保留布局与样式，不从场景闪现中文 |
| 正常流程与终局 | gameplay/game.gd | 传ID，不传源句或StageText已翻译结果；语言服务刷新不覆盖当前消息 |
| 输入及异常 | Board/BoardInputBuffer/BoardRunFlow、GameRewardFlow信号接线 | 规则错误与演出原因留诊断，玩家获得目录消息，不展示内部reason |
| 旧工具消费者 | demolition_capture.gd、skill_ux_capture.gd | 保留fixture/计分/推进，只迁移ID及次数参数 |

当前动态消息只有补棋格式验收模板(current/total)及截图工具次数(count)，均为非负int；不新增补棋进度UI。未知/字符串/浮点/额外参数被拒绝，因此不接收缓存的中文对象/颜色文案；没有新增需要颜色参数的状态。两语言占位符集合相同，可重排和重复；参数不会被再次作为模板解析。

失败先报告ID、语言、参数及原因，再显示当前语言unavailable；兜底也不可用则显示“—”。同ID/语言/原因诊断去重且容量有界，未知源句不会作为玩家文案。读取资源前检查存在性，避免缺目录文件绕过统一诊断反复触发load错误。降级不是验收通过。

## 验证

| 批次 | 实际结果 | 限制 |
| --- | --- | --- |
| 基线终局探针 | 基线英文→中文仍英文，已复现 | 控制探针，不冒称历史Web真人复现 |
| 首轮相关4脚本 | 20/20，773断言 | 该轮后又补了参数/语言服务及缺资源保护，不冒称最终头全部证据 |
| 新消息专项最终修正 | 2脚本11/11，313断言，退出0，无退出资源保留 | 两语言全目录、参数边界/重复/重排/特殊字符、缺键/错型、兜底/去重、当前消息副本、真实语言服务、终局/异常 |
| 既有相关回归4脚本 | 23/23，573断言，退出0 | reward_coordination/reward_presentation/localization/input_buffer；包含旧回调/重试/四播放模式；退出8对象/4资源保留，未判为生产缺陷 |
| 独立代码复审 | 首审建议已修；最终增量APPROVE，无CRITICAL/HIGH/MEDIUM/LOW发现 | 本地代理复审不是GitHub批准或远端CI |
| 实际Web出口 | **未通过**：db7d287导出门禁拒绝，96条ERROR | 失败产物只作浏览器诊断；未部署/发布；详见下节 |

本轮headless环境有根证书读取错误。新2脚本初轮11/11、312断言且没有退出资源保留；既有相关组合的退出保留需继续区分，不隐藏、不升级成已证实生产崩溃。历史contact_shadow/GUT清理诊断保持原提交归属，本片没有据此宣称已修或已完成整版质量验收。

复现命令使用Godot 4.7.2 `ed1daf0bf`、GUT 9.6，独立APPDATA沙箱，`--headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gtest=... -gexit`。具体脚本：

- tests/rules/test_hud_status_messages.gd
- tests/integration/test_hud_status_flow.gd
- tests/integration/test_reward_coordination.gd
- tests/integration/test_reward_presentation.gd
- tests/integration/test_localization.gd
- tests/integration/test_input_buffer.gd

不跑冻结树全量；本片成绩不代替#135/#136最终质量、#138发行、真人接受或#160续局验收。#137不自动关闭，PR保留作者review、不自动合并。

## Web实际观察与阻断

使用现成4.7.2模板，从干净`db7d2872c6251c753ffff96cb0c8ad6bdc7860c0`运行现有`tools/export_web.ps1 -BuildName web_issue137_candidate`。脚本因导出ERROR拒绝产物，没有把输出当成功发行包、没有ZIP或成功build.json；原始日志为`docs/evidence/issue137/web-export-rejected.log`，失败产物四文件身份见`web-diagnostic.json`。

对失败产物仅做诊断：本机HTTP 127.0.0.1:8873、Codex内置Chromium浏览器、1280×720。实际观察英文ready、移动中`Next piece queued`、`Paused`；通过设置→主菜单同局EN→ZH→EN后，暂停提示变为“已暂停”再变回“Paused”，回合2/行动1/空位73保持。刷新后英文偏好保留。没有在浏览器实际覆盖奖励等待、终局、异常注入、全部tooltip或所有播放模式；这些不以桌面测试补写Web通过。

浏览器启动控制台同时存在`ScreeningConfig`缺类型→`screening_deck.gd`→`run_controller.gd`/`game_manager.gd`依赖编译错误。界面可以运行及局部提示正确不能抵销这些错误。

只读归因与最小后续建议（**未实施**）：

1. `ui/item_widget.tscn`引用不存在的`res://icon.svg`，`popup_level_up.tscn`实例化该旧卡片。main/Game正式奖励走PopupSkillChoice，当前检索未见正式open_popup("popup_level_up")调用；all_resources仍会处理旧场景。可单独将旧卡片占位图引用修为现有合法资源并保留UID关系，不恢复旧奖励入口。
2. `data/item/effects/`旧资源直接使用`[sub_resource type="ConditionTiming"]`等脚本类名，未在这些子资源上绑定Script，报错堆栈为ClassDB原生类型实例化。对应.gd与class cache均存在，不能说类已删除；序列化格式是当前有证据的主要怀疑点。单独验证Resource＋显式Script引用并保留参数，而非删除类/改TypedArray规则；或由集成明确只排除已确认不进入正式路径的旧数据，但不能默默降低导出门禁。
3. 正式RunController静态引用ScreeningDeck，后者类型依赖`tools/screening_playground/screening_config.gd`，Web显式排除tools。此链有实际浏览器解析错误，不能归为无害未消费资源。建议由对应所有者将常驻依赖的纯配置类型移到非工具运行目录，或拆断正式脚本对工具类型的编译依赖；保持筛选规则/配置唯一来源，不临时把全部tools打进正式包。

上述相关源文件与1a03cb1逐字节相同，记录于manifest；未重新导出未修改基线，因此只证明缺陷结构在base已存在，不声称已运行基线同样96条错误。不因旧基线存在问题忽略门禁，不擅自修改这些额外职责。后续需相关场景/旧资源加载及筛选/正式运行解析回归，再从明确新提交重新导出并实际浏览器复测。当前PR保持draft。
