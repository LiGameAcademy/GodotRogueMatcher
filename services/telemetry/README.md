# 本地数据采集 · D1

Game 默认开启 `collect_telemetry`，在 Inspector 关闭即可停止本地分析采集；`record_runs` 独立控制33回放文件。采集写入 `user://telemetry/<run_id>.jsonl`，回放仍写入 `user://run_records/`。没有 SDK、网络上传或玩家身份采集。

`TelemetryFactory` 由 Game 创建，一次启动共用 session_id，重试创建新 run_id。Board 显式持有投影；RunRecorder 的冻结记录信号提供已提交的规则事实，BoardObservation 补充真实弹窗、输入处置和观察时间。投影不引用棋盘节点、不调用规则、不消耗随机流。调试盘面标记 fixture，机器人标记 bot。

事件 schema 为1：run_started、command_resolved、turn_resolved、offer_generated、offer_presented、skill_acquired、observation_interval_closed、input_resolved、run_ended。独立 telemetry_seq 与稳定 event_id 用于分析去重；整数编码为十进制字符串，避免JSON数字损失64位精度，未知值为null。

候选生成与实际展示分别记录。真人只把已显示的候选算作机会，同一 offer 多次展示不增加机会数；机器人使用生成候选作为机会。技能取得仅消费成功应用的规则结果。回合从有效移动开始，聚合剩余生成、连携和技能应用直到 INPUT；按实体ID去重创建/移除、按原账本事件ID去重得分，技能应用得分是回合得分的子集。

观察计时使用单调时钟，优先级为 inactive > pause > choice > busy > input，区间互斥。缓冲等待和机器人计算时间另列，不加到这些区间总和里。失焦不计入 active_ms。

`TelemetrySink` 的写入结果区分 ACCEPTED、PERSISTED、FAILED。本地Sink每个事件刷新文件；首次失败提示“本局分析记录不完整”，游戏继续，最终 record_complete=false。突然退出无结束行、截断或序号缺口由离线读取器诊断；已有文件不会被新局覆盖。

实际复用 godot_core_system 的 JSONSerializationStrategy。插件修复范围仅序列化基类与JSON策略：移除独立策略对 CoreSystem.logger 的依赖，以 last_error 暴露失败；增加 indent/sort_keys 配置，默认格式保持原样。本地JSONL设置紧凑输出。未接插件异步IO、全局事件总线或随机选择器。

工具角色由 telemetry_config.tres 管理，目前仅 instant_thin 标记 emergency。未接完整合法过滤资格明细，eligibility_rate=null；规则未提供父事件链，parent_event_id=null。工程没有完整存档恢复，暂不声称读档去重已验收。实验/变体可通过 RunRecorder.metadata 传入；未激活34通用工具或36容量玩法。

分析命令和字段口径见 [离线分析说明](../../tools/telemetry_analysis/README.md)。专项测试见 tests/rules/test_telemetry.gd 和 tests/integration/test_telemetry_scene.gd。
