# #135第二片 · 离场后代强度快照

基于待review的#167（1749dfb），本片实现b0f959a；目标develop/0.0.3，依赖#167先合并。本片不修改#167分支，不自动合并，不关闭#135。

## 行为与边界

旧AbilityResolver在出队时读取等级/配置：先移除引信再升级，会追溯改变已排队爆破。现在在离场触发、dispatch生成合法activation时保存独占RemovalStrength，只保存计算后的标量，不持有配置Resource或等级容器。

- 爆破：范围、选择性过滤、每枚得分、固定额外分、链深额外分、引信目标奖励系数及核心装填范围/数量均在本事件触发时保存。
- 扫线：主/交叉带宽、每枚奖励、额外倍率、固定匹配奖励及引信/染色目标奖励系数在触发时保存。
- 实际目标、目标当前颜色、引信/染色印记在执行时查询；后叶新增目标仍可命中，已离场目标不复活、不计分。标记实际存在与其奖励系数分开采样。
- 升级后被父事件移除的棋子，在自己离场时产生新事件，使用新强度；同根允许父子强度不同。嵌套Composite仍只有最外层flush。
- 余震在普通队列排空、符合既有资格并实际创建余震事件时采样，不提前从首个核心复制旧强度。余震资格窗口和根行动结算奖励未改。

ExplodeEffect/LineSweepEffect仍是纯命中查询，Resolver提交BoardRules与ScoreLedger。运行时不再通过event.ability.definition.effect或等级查询决定已排队事件的范围、过滤与得分。activation仍按原AbilityEvents票据完成/消费，不改变次数政策。

规则版本升至run-commands-v37-trigger-strength。MatchResult/RunRecorder事件增加trigger_strength，分别记录冻结参数、实际removed与score；RunSnapshot增加pending_removals只读投影。投影返回新字典及标量，改投影不会改变队列。此字段不是磁盘恢复实现，#160安全存档仍未交付。

## 配置与职责检查

| 检查 | 实际入口与限制 |
| --- | --- |
| 配置来源 | 读取既有ExplosionConfig/DemolitionConfig/LineClearConfig/DyeConfig；没有新卡、平衡值或Catalog修改 |
| 本局状态 | BlastRequest独占本次RemovalStrength；AbilityResolver拥有等待队列，A/B局不共享 |
| 修改入口 | 同一_remove_and_enqueue捕获、_resolve_blasts/_resolve_line_sweep执行、BoardRules/ScoreLedger提交；不加第二执行器 |
| 顺序/失败 | S01～S07规则级用例、后代新强度、固定/动态目标边界；沿用#167异常清理，未实现完整T分类 |
| 表现/服务 | UI消费既有结果；记录增加可复核字段，不新增暂停/动画依赖或IO规则入口 |
| 版本/证据 | v37明确拒绝v36；同版本新局/落盘/独立回放，完整和定向回归见机器证据 |

## 验证与覆盖限制

新增test_trigger_strength十二项，包含S01旧半径/S02新半径、S03得分和固定奖、S04失效目标、S05新增目标、S06父子新旧强度、S07真实嵌套runner、S08局部配置与A/B污染、扫线带宽/得分、目标标记系数、来源过滤、投影隔离与记录字段。

原实现首批10项中7项失败（14/30断言通过）；修复后10/10通过，再补真实嵌套及记录测试，定向3脚本25/25测试、129断言、0.114秒。规则用例不依赖界面节点，测试配置不进入正式卡池。

本片只交付离场爆破/扫线事件强度，以及余震创建时采样。匹配附引信的资格沿#167已冻结，但其配置范围/数量仍有flush时读取路径；染色接续及其资格/预算仍沿现有专用窗口，尚未统一成延迟强度事件；旧道具倍率按实际盘面计算，未迁移其架构。完整S08的磁盘恢复/暂停恢复与全部B/S/T仍未验收，不将本片当作整个S系列收口。

EX03有本片新增证据，EX01验证独占配置/另一局/投影，EX07沿正式Catalog命令回放；异形EX02/EX04、自动描述EX05、存档恢复EX06与整版EX08仍未观察或后续交付。#136在实际合并树进行最终质量回归。

Godot4.7.2 / Compatibility / GUT9.6.0，独立APPDATA/LOCALAPPDATA。完整统计与复现见[机器证据](../evidence/issue135-strength/README.md)。未进行编辑器人工试玩或Web导出。

最终完整回归：82脚本、599/599测试、22519断言，436.792秒、退出0，无SCRIPT ERROR或Parse Error，82个脚本均参与。v37独立回放415条成功；v36返回record_version_mismatch、检查0条，符合版本边界。
