# #129 六卡同源规则正文

六张样板过去直接读取手写摘要，配置、持有等级及剩余次数变化后，正文不能同步解释实际规则。本批改由只读描述器投影运行Resource，候选传拟取得等级，构筑传当前等级和剩余实际补棋次数；卡底既有flavor_text保持独立，不新增完整规则tooltip。

范围为D01计分倍率、D02拓宽行扫、D03留白一手、D04过关嘉奖、D05留白调色、D06清色后染。Refs #129/#135；不关闭父目标或宣称全池已自动生成。

## 实现及语境

| 样板 | 同源参数与必要边界 |
| --- | --- |
| D01 | ExplosionConfig.multiplier_per_level；正文是基础匹配倍率的加法贡献，不是最终得分+20%。构筑乘当前持有等级；冻结预览显示贡献前后，不假设其他倍率来源不存在 |
| D02 | LineClearRules.line_count与真实等级；名义范围保留边缘截断、主动/离场均适用且不授予主动权限；满级仍能读取最后一级配置 |
| D03 | RefillCountEffect.delta/batches；实际补棋计次、同向延长不叠幅度、免补棋不扣次数、相抵各消费。预览读取冻结净数量和剩余前后，不自行重算上限/相抵；构筑显示当前剩余，归零不继续写初始次数 |
| D04 | InstallGoalBonusEffect.bonus_score；候选从下个目标起且不补发，已持有构筑写每次达标额外分，避免在新阶段误称仍要再等下个目标 |
| D05 | 有序RefillCountEffect→ColorWeightEffect；有限数量修正与持续权重分行，权重不是概率百分点，锁定预告不重抽。隐藏整卡“消耗”标签，构筑剩余标成补棋修正，不暗示持续权重一同过期。卡maximum_level=1，不承诺本卡重复取得 |
| D06 | ClearMaterialEffect.selector/score_cleared、DyeMaterialEffect.target_policy/allow_empty_targets、DyeRules.CONFIG.instant_targets；先自选清普通棋含引信，再随机选存活普通棋颜色与至多N枚异色普通棋，无目标合法跳过，最外层完成后才处理后代。动态预览不作冻结承诺；固定染色/拒绝空目标的变体走对应描述 |

SkillRuleDescription只读取上述参数及现有纯计算函数，不调用freeze/build/apply，也不持有Run或随机对象。Composite检查循环/深度及配置合法性，嵌套保留顺序，后代屏障仅在最外层表达；无关独立补棋/权重叶可用同源紧凑句式，未创建第二份平衡表。

正文和新增预览/剩余标签使用专属skill_rules.csv的完整中英模板与命名参数。先检查请求语言自己的Translation条目，避免英文fallback掩盖中文缺译；错误结果包含skill_id/资源路径/子叶或模板键。界面分别显示可识别的[人工规则]/[Manual rule]、[人工预览]/[Manual preview]，不把内部路径塞给玩家。未支持效果、非六卡、条件/触发限制、缺参数或缺译均明确回退，不假称自动覆盖All/Any/Not或全池。

卡池及其他既有无参数summary调用保持配置定义语境；O1所有的skill_pool_text.gd未改，待集成协调单次接入运行等级。卡面与构筑已分别接拟取得/当前语境，不依赖此后续接入。没有改SkillDefinition、Effect参数、抽选、记录/采集、HUD、Game、Board或O5状态目录；project.godot只追加两份翻译资源。

## 排版与真实缺陷修复

完整正文初版越出原360px卡面的Action；调整高度后窄窗仍超限。这是本批文字引入的回归，不是旧版既有缺陷。仅在SkillCard内沿现有content最小尺寸适配高度、按当前视口和主题panel边距限制三列卡宽，上限326px，卡池保留256px。没有改节点、三列、字号、底部确认区或整卡tooltip。

保留长规则的随机/至多/存活/跳过/先后/后代边界，仅去重复解释；D05/D06有精确结构才使用紧凑模板，其余合法嵌套走逐步描述。失效英文截图最后还暴露“原定目标已经失效”未翻译，补在本批专属表；实际消费者SkillCard.set_unavailable的Action和tooltip均走原tr调用，测试分别检查二者，不更换fixture来掩盖中文。

## 受测身份和验证

起始base为1a03cb19，随后合入#211后的7d78fd8fa26624b6ad7f81fe5c9447a60c856e54。最终源码身份、文件SHA256、引擎/插件、日志/图片清单和逐批实值统一见[证据记录](../evidence/issue129-rule-description/README.md)与validation.json。证据归受测源码提交，之后仅文档/证据提交不重称另一轮运行。

适用专项包括：六卡双语、配置/拟取得/当前等级、有限剩余/零次/最大级、参数改变、上限相抵的冻结净预览、嵌套、固定/动态目标、缺参/缺译与回退、规则/配置/六随机流不变；真实Popup两语言×1024×640/1280×720×1/2/3张、选中/失效、原生鼠标确认；默认未套GameTheme的三卡Popup；构筑当前正文与混合剩余标签。相关旧回归保留风格隔离、规则/回放、v46拒绝边界及真实Game闭环，只更新变化的显示契约断言。

独立静态复审最初指出持有D04时机、D05重复取得暗示、增量/随机对象、缺译与默认Popup宽度等，均已修正；最终无剩余代码阻断。独立本地复审不是GitHub批准或远端CI。技术截图来自Godot Compatibility/RTX2070，不是作者/非设计者观察或性能样本。

## 范围与后续

按B档交集成核验：已确认工程批可独立集成，剩余非阻断措辞/审美偏好归后续合批体验。作者本批体验、非设计者及#131整体样本均为null；现有风格切片接受不追记成本批接受。卡池运行等级接入、全池生成、正式O2新内容、全部FJ/FI、弱机/实际发行包仍各归已有出口，不因本PR关闭#129/#116或发布。

复现（在本游戏工作树，先完成editor导入）：

```powershell
$env:APPDATA = Join-Path $env:TEMP 'o4-desc-review'
$env:LOCALAPPDATA = $env:APPDATA
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_skill_rule_description.gd,res://tests/integration/test_skill_rule_description_ui.gd -gexit
# GPU专属短复验；O4_RULE_CAPTURE生成8张两语两尺寸图，不采真人或性能结论。
$env:O4_RULE_CAPTURE = '1'
& $engine --path . -s addons/gut/gut_cmdln.gd -gopacity=0 -gtest=res://tests/integration/test_skill_rule_description_ui.gd -gexit
```

作者如需读感复核，可运行同一冻结树的上述GUI专项查看八图与规则；自然取得体验按#131另安排。此批未导出Web/桌面发行包，未改发布支持范围。
