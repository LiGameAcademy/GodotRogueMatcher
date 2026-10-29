# #129 技能池规则语境与同族补齐

技能池过去总是读取配置摘要，即使已持有卡也无法显示当前倍率贡献或补棋剩余；卡面随后按默认摘要行数切分详情，接入运行语境时还可能截错前置信息。本批由SkillPoolText.rule_view统一给出正文和语境，详情与SkillCard.configure_catalog消费同一投影，不复制参数或制造候选。

| 产品入口 | 本批采用的语境 |
| --- | --- |
| 无Run上下文的summary、技能池未持有卡 | 配置定义，不承诺候选等级或冻结目标；资格仍由原有只读规则展示 |
| 技能池已持有持久卡 | 当前等级，最大等级读取已持有配置，而不是不存在的下一档 |
| 技能池临时卡 | 已取得且仍有共享修正余次时显示当前剩余；已到期回配置定义。未取得卡不借用其他卡的共享计数冒充持有 |
| 真实奖励卡面 | 保持#215的拟取得等级与真实冻结预览，不由浏览技能池生成/重选目标 |

D05持有时继续分行显示有限补棋修正与持续权重，余次不作为整卡寿命；非持久卡的取得历史也不虚构成升级预览。卡池的当前等级筛选、前置/资格、翻译切换、暂停恢复及奖励往返沿原入口保留。

## 同族范围

在原D01～D06基础上仅补六张：refill_more、color_weight_up、color_weight_down、line_column_span、instant_color_clear、instant_color_dye。它们复用现有RefillCountEffect/ColorWeightEffect/InstallLineUpgradeEffect/ClearMaterialEffect/DyeMaterialEffect，不增加Effect家族、技能、平衡数值或通用描述框架。

- 列范围沿LineClearRules.line_count和upgrade_for_axis，保留边缘截断及不授予主动权限。
- 权重颜色在候选时随机冻结，取得只修改该冻结色。多次取得可能影响不同颜色，不按持有等级把delta累乘到同一颜色；独立权重正文不套用Composite减量到期语句。
- 即时染色的当前Resource为FIXED：随机冻结色和至多N枚普通异色棋（含引信），任一固定目标失效拒绝、不补选，染色后检验匹配；N读取DyeRules.CONFIG。
- 补棋增量、实际计次、清色普通棋/引信边界均复用既有规则描述。新中英句式由本批专属翻译表维护，Effect参数与Resource没有修改。

## 52正式卡覆盖

运行审计直接读取SkillOfferGenerator.CATALOG的52项Resource、每个声明有限等级的真实Effect树/参数及两语生成结果，见[coverage.json](../evidence/issue129-pool-context/coverage.json)。目前12卡生成、40卡明确诊断并显示人工规则；不把相同class但不同stat/upgrade/selector当作已支持。maximum_level=0的可重复旧路径只审配置级别1，未声称穷举所有未来等级。

| 真实根Effect | 卡数 | 生成 | 人工回退 |
| --- | ---: | ---: | ---: |
| RefillCountEffect / ColorWeightEffect / CompositeEffect | 6 | 6 | 0 |
| InstallLineUpgradeEffect | 5 | 2 | 3 |
| ClearMaterialEffect | 2 | 1 | 1 |
| DemolitionStatEffect | 5 | 1 | 4 |
| DyeMaterialEffect / InstallGoalBonusEffect | 2 | 2 | 0 |
| InstallUpgradeEffect / InstallDyeUpgradeEffect | 22 | 0 | 22 |
| 其它七类根Effect | 10 | 0 | 10 |

后续17张InstallUpgrade、5张InstallDyeUpgrade、其它Demolition stat、行列清理等需要各自已确认语义与参数计算来源，不在本批借接口接入扩写。原型异形也未加入正式池。

## 验证和身份

基线e3e3f978（#215已合），冻结源码1201816b4f11ce465b3e0cdca92eeb2a73e35b9e；后续仅加入本记录及证据。实际日志/图片/源码SHA256见[证据记录](../evidence/issue129-pool-context/README.md)。

- 最终相关4脚本14/14、3994断言：实际覆盖/语境和既有全目录卡面/构筑布局，包含current/next/max/remaining/fallback、Resource与六RNG不变；不是整库成绩。
- 本批较早的技能池/描述相关4脚本24/24、1443断言，之后只增审计参数记录和第三项滚动GUI场景；该批身份保留为开发中树，不把它冒称另一轮冻结树全量。
- 真实RTX2070 Compatibility GUI 3/3、506断言、exit0；中英1024×640和1280×720，共8图逐张目检。Scroll逐段展示正文、语境和前置/资格，返回按钮在视口内；不声称一屏显示全部52项或每张长卡全文。关池/暂停/原奖励往返由原有技能池回归覆盖。
- 独立静态复审修正权重采样时机后APPROVE，无剩余阻断；集成另行独立复审亦APPROVE。本地复审不是GitHub批准/CI。相关自有代码均≤500物理行。

第一次语境测试使用了未支持的初始化mode，使本局已有规则错误，随后无法安装列范围；改用既有fixture_dye并显式断言初始化/安装无规则错误，未改生产规则迎合测试。失败原始压缩日志保留。最终日志有沙箱根证书读取限制；实际退出及其它诊断按validation.json记录，不宣称零ERROR日志。

按B档交集成串行核验：本批工程出口完整，剩余措辞/读感和#131整体真人样本仍null；#129保持OPEN。40人工回退、新Effect家族、其它FJ/FI及整版体验不由本批结项，也未导出或发布发行包。
