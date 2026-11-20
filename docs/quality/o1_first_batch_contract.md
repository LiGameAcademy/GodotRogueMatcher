# O1 首批实施边界与随机接口

2026-10-29，base `9589563051f845e2c710f9522f4deed76307a265`。作者授权O1首批开发；集成已确认本批热点无已登记冲突，独立worktree `work/o1-random-contract`。本文件记录本批实际边界，不关闭#85/#87/#161，不代表整版验收。

## #85：资格/能力映射与#86的交界

当前权威入口仍为SkillDefinition、SkillRules、RewardState及各机制State。本批不启用新权重、不改变正式运行池；旧分池、画像累计、历史/重复倍率仍待#86一次替换，不能称统一合法池已完成。

| 职责 | 当前基础 | 后续最小实现/验收出口 |
| --- | --- | --- |
| H与拒绝原因 | validation_error、等级/前置/合法目标检查，异形按稳定身份拒绝重复解锁 | 结构化原因与内容开放/历史限制对账；未知定义/坏配置不能作为“合法失效”触发重建 |
| 生命周期 | 等级归实例，acquired保留成功历史，形状解锁另有本局身份 | once/repeat/upgrade互斥校验及逐卡映射，不解析中文标签、不以载体离场恢复一次资格 |
| related | 旧Tag画像仍在运行 | 将机制分类、前置、亲和分离；一个/多个命中仅0/1；L取得不改变T的独立亲和；通用数量/倍率不叠机制关联 |
| fills_gap | 旧need_rule不是新能力映射 | 同一冻结能力投影，显式提供/需要通道与专属收益；先H再缺项；FG01～10；候选最多1，不另存一份可写构筑状态 |
| 候选事务 | 生成器临时复制三流，非空1/2/3张成功才提交；RewardOfferRules处理一次修复 | 复用RO与RC；部分失效不补卡，全失效同reward最多一次成功重建；零池/失败保留游标、身份、奖励 |
| 参数 | 运行旧参数不变 | a/d=0.25、F=1～2等仅新公式试调起点；未知接受阈值保持待测，不能声称正式校准 |

能力映射必须按真实Effect/状态核验，首轮明确边界如下。下表是实施输入，不是已接入运行的Resource映射表。

| 能力 | 提供/投入证据 | 不提供的内容/门禁 |
| --- | --- | --- |
| 核心持续供给 | core_drop → core_pool_unlocked；instant_core_transform成功取得只证明爆破投入 | 即时转化不是持续供给；core_supply_up仅升级概率；核心暂时为0不撤销永久前置 |
| 首个爆破额外收益 | blast_extra或blast_reward首级关闭同一个爆破收益缺口 | 基础爆炸本来得分；收益升级、范围/连锁/控制不是首个收益缺项 |
| 从零布种 | core_fuse_payload、fuse_match_plant按真实条件提供持续通道 | fuse_relay依赖存量，不单独提供从零布种；assign_fuse仅一次恢复；先守各卡自身前置 |
| 扫线持续供给 | line_row_drop / line_column_drop为同一供给家族；即时转化仅证明路线投入 | 行→列是轴向扩展；已有任一持续通道就不再按“缺通道”加权 |
| 首个扫线额外收益 | line_clear_score首级，行列共享一个收益缺口 | span/cross/control是强化；升级不是新缺口；当前扫线手0不是断供 |
| 通用收益 | score_multiplier / precision_reward / longline_reward等维持自身H与普通机会 | 不关闭也不获得机制专属收益缺项；不为每条可选收益分支自动建缺口 |
| 异形规则解锁 | 稳定shape_id、成功取得历史、永久启用状态 | 分类Tag不能冒充T前置或L→T亲和；正式名单与配方依O2，不把原型自动入池 |

下一抽选批需补齐**当前全部运行定义**的提供/需要/定位与互斥校验，再将其接入#86统一公式和逐槽分母；本批不以这张边界表冒充完成逐卡配置。

## #161：本批实际接口

`RunState.random_streams: RunRandomStreams`拥有每局六个Godot RNG；RewardState/SpawnState只保留对应对象引用。`RunState.random`暂保留为spawn_position引用，避免无关API搬迁；它的seed已不是主种子，主种子改读`random_streams.master_seed`。

| 稳定ID | 实际消费者 |
| --- | --- |
| spawn_content | SpawnState预告尾部：颜色、核心/行列类型；预告纯读取不推进 |
| spawn_position | RunController每枚实际出生的实时空格；空/唯一空格不抽样 |
| offer_candidates | SkillOfferGenerator临时候选抽选，成功整组才提交 |
| offer_order | 同一事务的显示排列 |
| offer_targets | 同一事务的固定目标/颜色/坐标；动态叶只冻结延迟契约 |
| effect_execution | AbilityEffectRunner到达动态叶后的目标/刷新；现有space_compressor概率；旧EffectDyePiece适配保留但不重新启用旧道具路径 |

派生输入为`sl-rng-v1\n<非负63位规范十进制主种子>\n<稳定ID>\n`的UTF-8无BOM字节。SHA-256前8字节大端、清最高位；不拼规则版本/构建号。固定向量由.NET SHA256独立计算，再由Godot测试核对。动态执行与候选冻结分流，确定性单结果选择跳过随机调用。

`data()`返回独立字典：`rng_scheme_version`、字符串`master_seed`、按六个稳定ID索引的`streams`；每流`seed/state`为**完整有符号64位十进制字符串**，负数保留Godot int的64位位模式，不截成63位。仅初始派生清最高位。

`RunRandomStreams.from_data(Variant)`校验规范整数、协议、全部六流后构造临时对象；未知协议/缺流/JSON数字/溢出/前导零等返回null，不补种、不修改活跃局。该方法只处理随机载荷，**不是整局读档或磁盘接管API**。

记录规则升级为`run-commands-v44-six-streams`；JSONL schema仍`run-jsonl-v1`，原Header已能承载扩展字段。Header增加协议、精确engine_build与六流；seed字段现在显式记录主种子。原offer规则版本保留，准确表明本批仍用旧抽选算法。Checkpoint新增rng载荷；原random数组及spawning.content_random作为记录兼容视图保留，均从同一对象投影，没有第二份可写游标。

回放只接受当前规则/候选/内容/配置、同Engine版本及构建和相同OS平台、正确六流与初始快照；旧规则明确拒绝，原fixture文件不改写。规则与配置变更不改变派生起点，但会拒绝不兼容记录。日志可查看/分析不代表可精确重算。平台标记不能替代发行支持清单；本批仅实测本机Windows组合，Web尚未验证。

## 交给O5的边界与剩余出口

O5应使用上述随机载荷并在临时对象校验，不能发明另一套派生或缺流补种。正式安全存档仍需由O5实现schema/支持清单、旧局失效优先主备、完整权威状态/冻结候选/继续位置校验、一次接管与IO故障政策；不得只替换random_streams而留下RewardState/SpawnState指向旧对象。完整安全点恢复不在本批。

主种子入口复用已有实现；本批未重新宣称RG整组或熵失败/跨重启续局通过。桌面同环境技术回归不自动扩大为Web或跨引擎支持；#89/#160最终恢复联测、当前完整manifest支持清单和#88正式校准仍未交付。真人观察保持null。
