# #160：纯值存储底座

基线`e3e3f978ad0ae9f0555756475c7392862c594036`。本片只新增CheckpointStore、CheckpointFiles及专属故障测试，无生产调用，不启用SaveManager、不接继续UI、规则快照、候选、RNG或采集。

## 单一职责与格式

- Store管理一个逻辑自动槽：primary.json为本代，previous.json为上一有效代；Files只处理同步小文件读写/复制/替换/移除，单文件上限16MiB。不依赖后台线程或CoreSystem节点存取。
- 容器包含固定format、run_id、十进制字符串generation、调用方提供的字符串manifest、不透明payload和SHA256摘要。摘要检测损坏，不防作弊。不登记游戏存档schema/随机协议的另一套权威。
- payload只收JSON纯值，拒绝Object/Resource/Vector等对象、非字符串字典键、NaN/Inf、过深结构及原始int；调用者须先将64位ID/RNG/计数编码为十进制字符串。有限float仅用于实际浮点值。Store不识别具体RNG字段或候选结构。
- 未知容器format拒绝，不默认补字段、重抽或迁移。load_latest要求manifest完全匹配；游戏定义/状态不变量及版本兼容仍由将来的规则适配层验证。

## API与失败含义

| API | 实际含义 |
| --- | --- |
| begin_run(run_id) | 允许该身份使用槽，不表示已保存或恢复；另一live身份必须先验证持久失效。继续前必须先检查load_latest及规则适配层验证结果 |
| stage(payload, manifest) | 深冻结独立副本，返回内存ticket；0表示拒绝，不是保存成功。只保留最新ticket |
| commit(ticket) | 临时写、读回、主备提交及最终验证完成且提交日志已退役才ok；重复当前已完成ticket幂等，过期/失效身份拒绝 |
| load_latest(manifest) | 返回值副本及fallback/recovered_write标志；只装载纯值，不恢复或推进规则。主坏回备，均坏/不兼容明确失败并保留文件 |
| invalidate(run_id, reason) | 只有验证后的持久marker才表示该run禁止续局；reason限restart/terminal/abandoned。marker优先主备，坏marker拒绝继续 |

调用方必须检查每次ok，不能把ticket、文件写入成功或任务错误当成完整保存/回滚。没有任意选档或选择旧代的API；未完成的临时候选不自动当成新检查点。

## 为何保留一个小型提交日志

只有“先轮转备份，再替换主档”会在第二步失败时丢失原backup代。为满足失败保留原pair，Store在触碰主备前复制原始字节到固定rollback副本并校验hash，提交一个只含原始存在性/hash、run/代次的日志。任何未完成事务都先恢复原pair再允许正常读取/重试；最后读回本代及上代、移除日志后才确认成功。

日志不保存第二份游戏权威状态或玩法操作，不引入通用事务框架。损坏日志/丢失rollback副本均拒绝读取，不静默删日志。没有有效事务日志时遗留tmp/rollback不参与正常续局选择。坏档原始字节另按hash保留，未先解码重写原件。固定槽文件名及hash路径不取自payload。

这些是同步单服务协议，不是跨进程锁或跨文件/断电绝对原子承诺；FileAccess.flush和读回不等于所有硬件已持久化。受控中断故障测试不是实际强杀/断电验收。未来异步适配仍需独立task_id/代次协调，当前没有异步API。

## 失效标记失败：不能误认新局已开始

invalidate返回失败会关闭当前实例的旧ticket，当前实例load/begin旧局为invalidation_pending；不同新身份也不能begin。调用方必须拒绝开始/接管新局，先重试并验证invalidate成功，不得忽略结果继续构造正式Run。

如果失败发生在最终marker提交前，只剩tmp或根本没写到磁盘，重新构造Store后最后成功的旧checkpoint仍可能可读；它没有被声明为已持久失效。**新Store的不同新身份仍因旧live身份而被begin_run拒绝。** 本片不识别残留失效tmp为正式终局证据。跨重启的失败意图/终局证据处理还需应用接入，不能称SV08通过。

相反，替换已生效后才报IO错误时，最终marker可能已经存在：后续实例仍按实际marker拒绝旧局，重试按已验证事实幂等。取消/错误不等于文件未写，更不等于回滚。

## 实际验证

Godot4.7.2 `ed1daf0bf` / GUT9.6，独立APPDATA位于本工作树`.godot/io-sandbox`，仅使用memory适配和`user://checkpoint-store-tests/<pid>-<tick>`测试目录，没有读写作者真实档案。

- 最终单脚本20/20，308断言，0.469秒，退出0，无退出资源保留；根证书读取环境诊断原样保留。日志在`docs/evidence/issue160-checkpoint-storage/`。
- 覆盖深冻结/返回副本、64位字符串、坏JSON/摘要/版本/manifest、非法代次/溢出/耗尽、重入及旧ticket/重复提交、13种写/读/复制/替换/完成失败、未完成日志恢复、坏日志fail-closed、旧身份/终局/坏marker/失败重试。
- 真实FileAccess/DirAccess：重开读取主备、原始坏字节复制、16MiB边界；实际rename前失败及rename生效后模拟不可用，新实例逐字节恢复旧主备；实际失效marker rename失败、tmp/final状态、跨实例新身份拒绝及成功重试后的禁止续局。
- 独立代码复审及最终测试增量复审均APPROVE，无阻断；本地复审不是GitHub批准或CI。三个代码文件均≤500行。

本片按A档工程底座交集成核验，Refs #160，**不关闭整项**。剩余：安全点判定、正式全状态编解码/新对象接管、奖励幂等、六流/冻结候选/继续位置、恢复采集分支、退出协调、跨重启失败意图、实际强杀/断电及真实Web持久化。没有运行这些SV验收，也不把本片当作正式续局或最终A6通过。
