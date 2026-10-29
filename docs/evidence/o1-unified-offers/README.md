# O1 统一抽选验证证据

基线：1a03cb19d7cde1570edfecbc56e1fd3bfa878407（含 #210）。引擎：Windows Godot 4.7.2.stable.official.ed1daf0bf，GUT 9.6，headless / Dummy / fixed-fps 60，隔离 APPDATA。

完整回归受测提交 **59e8ef3c7267310bf2fcc26765ab13fcaae91905**：`tests/rules,tests/integration`，141 脚本，1005/1005 测试，29753 断言，退出 0。输出副本为 gut-full.log（仅去掉行末空格；原始输出留在本地 .godot/o1-unified/final.log），源文件哈希为 source-manifest.json。

后续提交 **5f996b2dc83bacd0f9ff5ecaa7915c62d66b3421** 只修改 SkillPoolText 的七能力前置与已取得一次提示及其回归。对 skill_pool、skill_cards、skill_mechanic_icons、game_themes 四脚本专项：34/34，5965 断言，退出 0（gut-ui-increment.log）。该增量没有重跑全量；不能将前一提交的全量成绩标成最终代码 head 的新全量。增量文件哈希在 validation.json。两次复审发现的解释一致性和目录旧消费者/内部码问题均已修复，授权只读审查最终 APPROVE。

完整日志仍含29条浮点/整数比较警告；两条对象在信号期间释放的诊断均为 test_contact_shadow.gd:106 → GUT free_all 同历史栈，未在本批修复，也不据此宣称生产崩溃。根证书读取为本机环境诊断，三个无效模板 push_error 为预期负例。证据没有删掉这些输出。早期 all/frozen 日志因遗漏目录旧字段有10项失败，保存在本地 .godot/o1-unified/，不作为通过证据；ui-fix首次指错一个脚本路径的诊断也不作为最终专项证据。

自然样本受测提交 **f23109339ce7af17e1c8365ee3f5305a388e9c72**，与全量提交相比后续只增加目录文案适配。greedy-v1，种子1000～1002，每局最多60步；实际完成43/34/31步，得分629/300/250，奖励选择3/2/2，3局均board_full，全部落盘回放成功。分析3文件、1057事件、3局、0错误。重复同一文件两次保持418事件、1局、3次取得；损坏尾部保留有效前缀，标incomplete、1条invalid_telemetry_json、退出1。

bot-runs.csv、各局 summary.json 和 analysis-summary.json 是可审查摘要。完整命令/埋点 JSONL 保留于独立工作树 `.godot/o1-unified/frozen-batch/{records,telemetry}`；绝对位置、字节数和SHA256列于input-manifest.json，不修改历史样本。CLI日志均保留。原始文件未纳入Git，远端复现可按同种子重新采集，不能冒充同一份原始记录。

本批仅验证统一抽选与观测链路。a/d=.25、Q/V=1、s=0、平坦稀有度曲线均为trial_unvalidated；不声称450局旧故障复现、参数校准、真人体验或#160完整恢复已验收。

## 下游接口

规则版本 `run-commands-v45-unified-offers`，抽选版本 `offer-unified-trial-v1`，六随机流协议沿用#161。offer_generated增加explanations、slots、build_snapshot、parameters、replaces_offer_id；analysis summary的opportunity_protocol为parent-run-reward-v1。合法池资格统计是generated_pool_diagnostics，不能当作展示/曝光。旧缺失字段为null。

| 新拒绝码 | SkillPoolText可读投影 |
| --- | --- |
| missing_required_capability:core_supply | 缺少前置升级 · 需先获得爆壳手登场 |
| missing_required_capability:fuse_unlocked | 缺少前置升级 · 需先解锁引信路线 |
| missing_required_capability:live_fuse | 缺少前置升级 · 棋盘上需要引信 |
| missing_required_capability:row_supply | 缺少前置升级 · 行清除手登场 |
| missing_required_capability:column_supply | 缺少前置升级 · 列清除手登场 |
| missing_required_capability:line_supply | 缺少前置升级 · 行清除手登场 / 列清除手登场 |
| missing_required_capability:dye_engine | 缺少前置升级 · 染色接续 |
| already_acquired_once_per_run | 取得 1 / 1 · 当前不可选 |

这些投影复用既有中英文翻译，不变更Game/HUD消息契约；未知配置错误仍保留真实诊断。
