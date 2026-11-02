# #88 试验参数局的合法成对窗口

#235已合并至7b045d9。复用归档a0/d.25、seed1000原局时，旧paired CLI退出1：分支转为fixture后，RuleReplay的trial入口仅允许bot，拒绝invalid_offer_trial_binding。这是现有H20/50实验通路的真实门禁，不涉及新增参数取舍。

修复只允许带可重放父链的paired fixture：保存原bot Header，重建并重放完整父前缀；核对完整配置hash、a/d绑定、派生pair ID、同一冻结reward/offer、两个真实合法候选及首条处理/对照选择。普通fixture/human不因此接受trial，父链损坏、奖励/候选/配置/干预篡改仍拒绝。默认配置、规则版本、writer及snapshot恢复协议不变。

子分支Header仍标source=fixture、collection_context=paired_window；既有采集器会按source将遥测context归一为fixture（本批保留该行为），不能混进自然根局；父采集commit与执行commit分别保存。CLI新增可选--commit记录本次执行，未提供时unknown，不继承冒用旧父commit。

相关9脚本67测试2642断言通过；来源增量3脚本19测试357断言通过。专项含三档a、H20/50、父链与奖励候选篡改、非a/d字段拒绝、父数据不变、外部截尾delta=null；该合成测试不作为校准样本。独立只读复审通过。

真实有限验证在6598e9a上使用同一个原父局，首个真实奖励三个候选循环下一张作对照，各H20/50一次：6对、12分支，仅1父簇。进程95.73秒退出0，12个分支均落盘回放通过；6对均有已知结局，分支6次自然满盘、6次达到H边界。既有Reader处理12分支无错误，恰6个测量事件，仅treatment写出；父身份与执行commit核对一致，原父文件SHA未变。完整证据在课程工作区validation/0.0.3/o1-paired-trial-20261102。

这仅证明通路可用，不是6个独立父样本，不估参数效果、普适技能净价值或正式区间；触发attempt仍未知。原300局描述数据与失败/hash均保持原字节，没有新自然局、没有d扫描或150新seed复核。

## #88的下一完整出口

1. 明确首次核心取得/明显连携的操作定义、自然失败与未触发口径；工程已区分 install_effect/manual/recurring（见进度第 9 点），**明显连携**数值与最高k5/真人体验仍缺。不能把供给安装等同明显连携；attempt 分母不能单独定稿作者口径。
2. 作者确认a阶段后冻结下一候选与接受标准的数值/单位、最大不确定度/样本上限/停止规则；需要d扫描时先按已确认顺序登记，不在本批擅自选择a或阈值。
3. 在相同真实候选上补稀疏技能H20/50，按父局聚类、保留所有截尾/失败和明确对照卡；通路与小样本已有，仍非正式区间。
4. 最终候选及接受线明确冻结后，才采150新seed并做作者试玩；逐项将a/d、稀有档曲线、s/V、配额与体验参数标为正式/试调/待测，保留高k及真人缺覆盖。未完成不关闭#88。

## 作者确认（2026-11-02，白话）

1. **装上 ≠ 用上。** 进一步要求：按次统计消除时实际触发的技能/连携次数（不是只看有没有装上）。`AbilityTriggerStats` 已区分 consumed（用上）与 attempts（同主同事件下的条件/次数拒绝也计入分母）；owner/事件类型噪声不计。0 consumed 且 attempts>0 表示试过未用上；attempts=0 才是窗口内无在范围尝试。
2. **a 阶段。** 同意先扫 a=0 / 0.25 / 0.5（d 暂钉 0.25）；试调默认 0.25。接受线白话：相关卡更常被选到、又不会几乎张张同族、均分/满盘不崩。定不下来继续标「试调 0.25」，不假装最优。d 扫描等 a 阶段结论后再开。
3. **稀有/少见技能。** 作者要求其权重应重点看**当前棋盘压力**（原文按「稀有 / 棋盘」理解；若是别的意思请改正）。现状：压力快照会拍，但权重里救场项 `s` 仍为 0、未启用。下一片把「压力影响稀有卡权重」列为明确试验，再谈 H20/50 覆盖。
4. **种子（跨 #161，单独写清）。** 作者确认 0.0.3 **必须一局一个主种子**；出生/抽卡/补棋等由主种子派生，便于存档与复现。当前未见必须「多主种子」的理由；命名随机流可以仍有多条，但都从这一局主种子长出。细节与缺口归 #161，不塞进 a/d 接受线。

## 工程进度（按作者批准顺序）

1. **触发记账（已合入 #237）**：`AbilityTriggerStats` 汇总 `consumed=true` 触发；成对窗口/压力报告可记账。装上≠用上。
2. **a 三档批测（已合入 #238 读数）**：同种子 `880100`、greedy×20、`d=0.25`、commit `ed1674c`、实验 `o1-a-scan-20261102`。三档均 20/20 `board_full`。相关槽约 0.14→0.15→0.23；相关选中约 0.15→0.19→0.19；机制重叠约 0.26→0.33→0.35。均分/p50：567/510、477/403、485/400。未见张张同族或满盘崩。**小样本不冻结最优**；试调默认 **a=0.25**。作者 Web 试玩暂无阻塞后已开 d 扫描（见第 8 点），仍不假装 a 最优。
3. **棋盘压力→稀有权重（接线 #239 + s 小样本）**：公式已通；默认 `situational_gain=0`。同种子 `882100` greedy×20、`a=d=0.25`、实验 `o1-s-scan-20261102`（commit `4d025a1`）：
   - s=0 / 0.25 / 0.5 均 20/20 `board_full`，回放 OK。
   - 稀有(≥2)候选槽占比约 0.120→0.129→0.143；高压(P≥40)下稀有槽约 0.143→0.159→0.183（低压约 0.10→0.11→0.11）。
   - 稀有选中率仍约 0.08（greedy 仍偏常用卡）；均分/p50：523/407、468/407、532/344。
   - **小样本不冻结 s**；正式默认保持 0。若继续试验，优先试调 **s=0.25** 再谈稀疏卡 H20/50，不开假装最优。
4. **#161 一局一主种子（已合入 #240 核对）**：现实现满足作者前提；跨环境/#160 联测仍不关闭 #161。详见 [issue161_one_master_seed_audit.md](issue161_one_master_seed_audit.md)。

5. **稀疏技能 H20/50（已合入 #242）**：paired CLI 增 `--min-rarity`；在 s=0.25 父批 `o1-s-scan-20261102/s_0.25` 上，11/20 父局含稀有候选并成功成对，产出 **26 对**（H20/50 各 13），全部 `known`，目标 rarity≥2。技能簇：`composite_clear_dye`×8、`line_column_span`×8，另有 `line_manual_clear` / `blast_chain_radius` / `blast_refill_relief` / `chain_reward` / `core_manual_detonation`。ΔS 有正有负；当时尚无 attempt 分母，`target_trigger_count` 多为 0 不能证伪未触发。证据 `.godot/o1-paired-rare-s025-20261102/`。**不能**据此冻结 a/d/s 或勾完 150 新 seed。
6. **attempt 分母（已合入 #243）**：`AbilityEvents` 对 `condition_rejected` / `trigger_limit_reached` 落盘 attempt 痕迹；成对窗口报告 `target_trigger_attempts` / `target_trigger_rate`；压力报告 `attempt_denominator` / `consume_rate`，coverage 含 `attempted_not_consumed`。owner/事件类型不匹配不计分母。成功完成痕迹仍以 `matched` 计 attempt，不另写冗余 `attempt` 旗标。
7. **attempt 重读 + 旧父回放兼容（本片）**：#243 一度把 `attempt` 写入完成痕迹并新增拒绝痕迹，导致同规则版本的旧 s=0.25 父前缀回放比对失败。现：完成痕迹不再带冗余 `attempt`；回放在「期望 activations 从未使用 attempt 字段」时，比对侧丢弃实际多出的拒绝 attempt 痕迹。同批父局重跑 `.godot/o1-paired-rare-attempts-20261102b/`：仍 **11/20** 父成功、**26** 对全部 `known`。**26/26** `target_trigger_attempts=0` 且 `missing_reason=no_in_scope_attempt`（consumed 同为 0）。抽查 `composite_clear_dye`：技能能力是 `skill_acquired` 一次性装上，窗口内 activations 只有先天 `on_eliminated_line_sweep`（`skill_instance_id=0`），故装上≠窗口内再尝试；手动技亦可能被 greedy 零次使用。ΔS 仍有正有负，只能说明选择差，不能当「触发率」。正式包仍是试调 **a=0.25 / d=0.25 / s=0**；不冻结最优，不开 150 新 seed，不关闭 #88。
8. **d 三档批测（本片）**：作者 Web 试玩「暂时没什么问题」后开扫。同种子 `881100`、greedy×20、钉 **a=0.25 / s=0**、实验 `o1-d-scan-20261102`。三档均 20/20 `board_full`、回放 OK。补缺槽占比约 0.038→0.045→0.083；补缺选中约 0.114→0.114→0.159；相关槽约 0.14→0.16→0.17。均分/p50：417/458、410/425、415/475。15/20 局三档终局代理指纹相同，说明本样本下 d 对多数轨迹影响弱。**小样本不冻结 d**；正式试调保持 **d=0.25** 与 a 并列，不勾 150 新 seed，不关闭 #88。
9. **触发/用上口径（本片）**：新增 `SkillTriggerPayoff`。目录卡分为 `install_effect`（装上即生效：leveled `skill_acquired`/`skill_upgraded` 或即时 `choice_effect`）、`manual`（`manual_use_limit>0`）、`recurring`（技能自身挂非取得事件，当前正式池几乎没有）、`unknown`。成对报告补 `target_trigger_mode`/`target_install_uses`；attempts=0 时 `missing_reason` 改为 `install_effect_not_recurring` / `manual_unused` / `no_in_scope_attempt`，不再把装上即生效误标成未触发。工程白话：**装上**=取得成功；**用上**=install 看 SkillInstance 取得计数、manual/recurring 看 activations consumed；**明显连携**仍待作者定数值口径，ΔS 不冒充连携。不关闭 #88，不勾 150 新 seed。
10. **稀疏成对新口径重读（本片）**：在 #247 上对同一 s=0.25 父批重跑 `.godot/o1-paired-rare-payoff-20261102/`：仍 **11/20** 父、**26** 对 known。模式：**22** `install_effect` + **4** `manual`；attempts 仍全 0，但 missing 为 **22** `install_effect_not_recurring`、**4** `manual_unused`，无再误标 `no_in_scope_attempt`。leveled 装上卡（如 `composite_clear_dye`/`line_column_span`）`target_install_uses=1`×16；无 levels 的增强卡/手动解锁（`blast_chain_radius` 等）install_uses 可为 0（选择即时生效，不走 SkillInstance 计数）。ΔS 读数与 #242 同量级。证明装上≠窗口内再触发，且多数稀有卡「用上」应看装上/即时效果。不冻结 a/d/s，不勾 150 新 seed，不关闭 #88。
