# #136 当前合并树的迁移阶段验收

基线ea11167，2026-10-21；#133奖励归属、#134旧写入口退役和#135现有B/S/T已进入develop/0.0.3。本次复核实际消费者、执行合并树回归并划清遗留；不把分支证据等同实际合并树成绩。完整635/635、22913断言、194.384秒、退出0；机器人415条读盘精确回放通过。原始证据见[issue136](../evidence/issue136/README.md)。

## 六组跨模块证据

| 组 | 当前实际覆盖与消费者 | 未交付/限制 |
| --- | --- | --- |
| 连续奖励 | test_reward_waiting_rules：部分失效、一次重建、零池/重建失败RNG不变、重复确认；test_reward_coordination：真实弹窗关闭/恢复/候选隔离及两次奖励，普通/快放/低特效/组合四模式 | 任意磁盘恢复后的reward额度归#160 |
| 匹配与后代 | test_composite_offer_lifecycle/contract、test_trigger_strength/followup_strength：正式发牌动态叶0/1次、嵌套屏障、失效政策、容量前检、触发强度、局部故障中断、实际目标和退役 | 当前直线验证；L解锁/多模板收益与U/L验收待#118/#120 |
| 补棋继续 | test_refill_lifecycle、test_core_loop、test_spawn_preview及有限修正：真实批次扣次、出生查线后完成余数、预告锁定/类型、出生中重试不继续旧局 | 新的解锁全清恢复R待#118；不把旧移动全清补棋冒称R |
| 阶段终局 | test_stage_challenge/test_stage_scene：尾部收束再判关、满盘优先、继续挑战、奖励不增有效行动、终关无选卡；真实界面继续按钮 | 异形解锁/恢复中的阶段组合待对应功能 |
| 界面中断 | test_reward_coordination、test_skip_recovery、test_presentation_director/composite_contract_scene：关闭/查看、暂停、略过、恢复故障、新旧局回调隔离；四模式连续奖励与普通/组合强度一致 | 未宣称每一种故障与四模式全排列；人工可读性/性能未验 |
| 存取及工具 | test_commands_replay、test_collection_lifecycle/batches、test_telemetry_scene：真实命令重算、坏JSON/截断/配置拒绝、IO失败不阻断规则、采集前缀与退出、机器人读盘回放；tools源码显式fixture无旧注册 | 命令前缀重算不是#160中间叶存档；截图工具做源码/既有解析与入口核对，没有本轮图片产出 |

## 旧入口与实际保留理由

- SpawnManager、ItemEffectSystem、ItemPlacer均无Autoload/脚本/运行调用；测试只保留“旧根不存在”断言。BoardRunFlow→RunController是正式推进；表现不再发旧match_made、触发道具或重复提交分数。
- ItemRegistry是局部RefCounted工厂，只在测试提供ItemData显示元数据/资源隔离；旧效果显式接收run/ledger，不订阅正式对局。不进入SkillCatalog。
- MatchSystem保留MIN_MATCH_COUNT（Game/Board/规则夹具使用）和只读check_for_elimination/calculate_score。旧写方法check_and_eliminate已删；match_made仅声明及“零次发出”测试，无正式发射者。未来消费者迁完再退役，不为本片清空单例。
- LevelUpSystem只从绑定Run读取进度，消费者为兼容测试；旧随机池/注册/弹窗已退出，无第二份奖励状态。
- GameManager是现有Game/Board/UI显示桥，绑定当前Run，不另存账本。publish_score发布已提交分数；add_score只由Board.F7、两个截图fixture及测试调用。F7先结束正式记录并标debug_f7_not_balance_sample，属于显式调试写入口。reset/start/end/finish兼容桥仍存在，本轮未把它们声称全部删除或迁移；正式步骤由RunController承担，后续若改桥需逐消费者迁移。
- UIManager保留弹窗展示，GameRewardFlow协调奖励/暂停，PopupSkillChoice无规则消费权。CoreSystem仍用于本地化/偏好等实际依赖，save_manager和auto_save明确关闭；不把插件存在视作续局已实现。

静态完整线索见legacy-consumers.txt；零匹配不是唯一证据，上述结论同时核对了脚本实现、Autoload和实际规则/场景回归。316个自有脚本无500行超限；未改配置、资源、游戏数值、随机流或规则版本。

## QR01～QR06与出口

| 项目 | 当前结论 |
| --- | --- |
| QR01 | 固定实际合并提交、引擎/规则/配置与现有交付范围；工作区原本干净，外层作者设计改动保留 |
| QR02 | #133/#134/#135原始证据复核，加本次合并树完整集及六组固定流程，三层证据可追踪 |
| QR03 | 六组现有行为通过，四模式实际范围如上；未实现功能明确未验证，阻塞整版出口，不阻塞独立检测原型 |
| QR04 | 首次完整无失败，日志保留预期故障注入输出；未更改规则期望/断言或挑绿 |
| QR05 | 首次全量后不重复扩大套件，本次代码零变更无需额外跑插件；194.384秒自动测试，非人时/体验预算结论 |
| QR06 | 无未解释正式旧写入口；保留桥/调试入口和未来责任明确。迁移阶段可以进入#118，整版#136及#135保持open |

后续先做#118直线＋L的无UI检测/统一命中最小片，再接真实移动/出生/改色/预览及解锁生命周期；U/R和存档在实现后回到本表补证。#136不能因本次通过自动关闭，#138、O3/O4和发布出口独立。没有新增产品规则或提前宣布里程碑完成。
