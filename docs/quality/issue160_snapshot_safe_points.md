# #160 第二最小批：冻结奖励、阶段与快照采集续段

2026-11-01。延续作者确认的当前状态快照方案。仅隔离服务与规则核对，正式Game/菜单/自动保存入口没有切换，O5继续OPEN。

## 变化与契约

- snapshot-safe-v2支持正常经典/阶段模式的INPUT及已冻结REWARDS。保存当前候选原排序、reward/offer/replacement/repair身份、原目标与Composite叶子、未消费奖励及原继续位置；不重新生成、不重新采样、不执行取得效果。profile/unavailable补入快照，旧RunSnapshot回放格式保持原样。
- 阶段Config独占恢复、目标与升压来源参与manifest，保存阶段/延续/待奖励/本行动补棋与根结算身份。只保留最近阶段结果用于继续义务，旧累计阶段历史不读入快照。未结算当前根的既得行动分规范化到action_score；恢复后的账本仅有总分及next_id，新结算只加恢复后的新分，避免丢分/双计。
- 形状/原型仍明确不支持。已提交终局拒绝保存；合法ContinueChallenge命令后的奖励等待可恢复，不返还机会。所有恢复在隔离冷对象完成，实际序列化往返后严格投影对比，再写Store；未知格式拒绝自动迁移，旧prefix及第一批v1原件不自动覆盖。
- 新SnapshotHeader / run-snapshot-segment-v1用于独立的新命令段，带快照锚点与段身份，从1开始记录自己的序号；普通RuleReplay拒绝它，不伪装普通Header或完整开局前缀。单独解码锚点后，使用原逐记录规则比较器验证新段。返回whole_run_replay=false；段完整和整局完整不能混用。
- 新段只允许冷恢复、无历史账本且未挂Recorder的运行实例。真实记录文件仅写新SnapshotHeader/Checkpoint及后续事实，不复制旧记录。Recorder默认普通Header/完整历史行为保留。
- 采集沿既有telemetry-v3 resume envelope。已持久父observation_checkpoint明确绑定snapshot_state_hash，trace只保留小型指针；known必须具有真实持久水位及父原始行ID/序号/摘要/状态绑定匹配。未落盘、缺失或不匹配保持unknown，不影响合法规则恢复；不猜最长父链。正式Web接线必须从实际oncomplete确认视图提供父行，当前服务不能把accepted当ack。
- 冻结中途缺少历史行动观察时标记root incomplete，不重放旧展示/取得或伪造完整行动；known只证明父关系，不证明中断行动统计完整。源来源不硬编码human：known继承父source，其余显式来源或unknown。
- CoreSystem继续只复用纯JSON策略；没有启用SaveManager/定时器、增加第二个写入者或改变CAS/oncomplete。

## 验证

原生：相关snapshot/segments/legacy replay/telemetry/实际旧场景6脚本46/46、1849断言；最新safe-points/segments/Store/Recovery4脚本44/44、1180断言。另一次含阶段规则5脚本47/47、1830断言。套件重叠不累计。

包括正常真实生成冻结候选、阶段奖励/完成后继续、四种继续位置×1/2/3张受控合法组向量、重复命令只消费一次、目标与阶段逐字段坏类型/重哈希拒绝、独立状态/RNG与后继操作、真实父采集文件flush读回/known链重组、unknown不阻塞、真实新段JSONL及新段回放。受控向量不宣称全部在同一seed自然发生。

独立审查发现并修正SnapshotHeader metadata坏类型与探针把目录误当Web槽的问题。首轮解析/类型/测试清理错误原日志保留，不用退出码0掩盖脚本跳过。原生沙箱根证书存储读取诊断单列，无证书绕过。

原定实际Web计划（结果见下节）：经典8982和阶段8983隔离origin，各自空槽起步、同槽INPUT→REWARDS；经典额外45移动样本。新adapter重开、端点/源状态/后续操作、新段独立回放逐项确认。只算助手内核探针，不能替代正式UI/真人或目标设备预算。

## 正式切换判断

本批即使技术通过也只证明服务协议可用。正式入口仍需采集Web持久父锚点接线、保存串行合并/退出/终局/取消旧回调、场景接管及错误反馈、旧档显式策略、形状完整范围与目标设备预算/完整产品矩阵。独立审查与实际Web证据归档后再判断，不提前切换或收口。
## 实际Web结论与切换判断

| 模式/安全点 | 移动 | 快照 | 保存含确认 | 新adapter重开加载 | 保存/加载最大帧间隔 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 经典INPUT | 0 | 3727B | 65.9ms | 108.6ms | 51.9 / 26.5ms |
| 经典冻结REWARDS / before_end | 9 | 62806B | 140.3ms | 141.3ms | 94.6 / 49.6ms |
| 经典INPUT | 45 | 6877B | 102.8ms | 123.8ms | 62.1 / 27.0ms |
| 阶段INPUT | 0 | 4053B | 63.9ms | 108.6ms | 51.8 / 26.5ms |
| 阶段冻结REWARDS / after_spawn | 9 | 63802B | 136.7ms | 143.0ms | 94.6 / 50.7ms |

两个模式分别从空origin起步，同槽主备跨INPUT/冻结继续保存，均用新adapter打开数据库加载。每测点源状态不变、端点相等、后续3条相同外部命令一致，新SnapshotHeader命令段回放通过；两份报告ok=true、退出0，错误面板为空。45移动源425条历史不保存；冻结载荷约63KB包含当前完整候选/目标树与当组诊断，不是累计规则前缀。单次助手测点，最大帧间隔仍约95ms，未冻结目标设备门槛或证明产品体验通过。

来源：阶段b947f9f/8983，经典3ac9e0e/8984；两版本services/gameplay没有差异，经典仅修探针测点顺序、origin及幂等退出。严格产品Release source b947f9f，ZIP SHA256 `083AE4759DF42E4522855B1AF7E4B6D88C38C381678E1635216FC79339D84B1B`，正式ZIP未修改。诊断main_scene与tools排除项始终finally恢复；每个PCK/HTML摘要及原始report/console/status见`docs/evidence/issue160-snapshot-safe-v2/`。

原8920/8921受系统保留端口阻断；早期typed数组问题导致探针等待，补超时后报告退出2；经典旧测点顺序在自然终局后找不到奖励而整体失败。全部保留原始证据，不重标为通过；新顺序首次冻结先测，新空origin保留8982原件，不清库。看门狗是主循环协作超时，不是抢占式硬超时。

**本批服务协议通过，暂不切换正式存档入口。** 下一最小批需将新快照接入既有保存Job/串行合并及Game/RunCollection接管，提供实际Web采集oncomplete父锚点与新段存储接线，并验证菜单续局、终局失效、取消/旧回调/重复消费和错误反馈。形状完整范围、旧档显式策略及目标设备预算/真人体验仍列未完成；O5保持OPEN，PR #231继续Draft。