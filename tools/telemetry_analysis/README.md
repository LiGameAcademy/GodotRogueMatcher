# 离线埋点分析

在实际Godot工程目录运行，将 `godot` 替换为本机Godot 4.7可执行文件：

```powershell
godot --headless --text-driver Dummy --path . -s tools/telemetry_analysis/analysis_cli.gd -- user://telemetry user://telemetry_reports/latest
```

第一个参数可为单个JSONL文件或目录，目录只读取本层 .jsonl。输出 runs、turns、offers、inputs、intervals、skills、events 七张CSV与 summary.json。嵌套字段为JSON；空值为空单元格。损坏文件保留已验证前缀，报告 errors 并返回退出码1，不把缺失终局标成完成。

生成一个隔离的机器人批次再分析：

```powershell
godot --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- --count=3 --seed=777000 --moves=300 --output=user://bot_reports/d1 --telemetry-output=user://telemetry_d1
godot --headless --text-driver Dummy --path . -s tools/telemetry_analysis/analysis_cli.gd -- user://telemetry_d1 user://telemetry_reports/d1
```

正常机器人批次默认采集到 user://telemetry；隔离目录用于避免混入此前测试/试玩。回放文件仍落盘读回验证。重复运行使用新的run_id，不覆盖旧样本；只分析本次批次时指定新的目录。

报告按 source、initialization、schema/rule/content/offer/build版本、游戏config_hash、strategy_version、bot_config_hash、experiment_id、variant_id 分组，局结果再按结束status区分。分组键包含维度摘要，每组输出完整 dimensions。bot_config_hash包括实际策略配置，不能把不同搜索参数混成同组。build未由启动者提供时为unknown，不能用它识别不同二进制。

事件按event_id去重，冲突内容报错；每个run_id只有一条局汇总行，完整文件可补全旧前缀，旧前缀不能降级已完整终局，冲突元数据拒绝合并。重复数据源的诊断仍保留在 errors。

真人技能机会分母是已实际展示的唯一offer，机器人分母是已生成的唯一offer；fixture、replay和不同实验独立分组。conditional_selection_rate=成功取得/机会；无机会时null。生成未展示、展示未消费、失败选择另计；重复展示与重复确认不增加取得次数。尚未采集合法过滤全过程，资格率为null。

基础分布采用排序后的 floor(q*(n-1)) 样本分位数，输出P10/P50/P90。小批次只能验收链路，不足以判断技能平衡或真人15分钟体验。深度H窗口、详细因果索引与线上平台接入留D2/D3。

## #13 schema 2 基础协议

Reader按版本校验v1/v2，v1缺失的新维度保持unknown。v2的turns.csv来自action_resolved，不再叠派生turn_resolved；mode_id/collection_context/commit/pressure/collection_config加入分组。Reader自身接受解包后的JSONL；下面的#17入口负责ZIP与xlsx。

工程场景 tools/telemetry_analysis/collection_benchmark.tscn 生成 .godot/collection_benchmark.json。它测冻结事实投影、编码与批量IO，排除规则、UI、初始化和终局，不能当作60FPS增量帧基准。collection_probe.tscn接收 -- hold|recover <测试目录>，只用于独立受控进程；结束该探针前核对ready.json的PID，不对作者运行中的编辑器进行强杀。真实Editor Stop仍须人工验收。

## #17 一次导入与工作簿观测首片

在游戏停止后提供导出ZIP、JSONL/summary目录或七表CSV目录，工具在游戏外运行，不增加游戏帧内IO。结果是指定v0.4工作簿的新副本，保留原有十个模型页，新增或刷新五个工具管理页：观测汇总、技能观测、退出观察、数据来源、自动参考。不改原文件、运行Resource或目标曲线。

需要Python 3.11+、Node.js、Godot 4.7与已提供的`@oai/artifact-tool` Node依赖。Python入口只用标准库。Codex桌面环境可通过workspace dependencies获得Python/Node及依赖目录；不把这些机器路径提交成项目配置。首次在游戏目录建立一个忽略的依赖链接：

```powershell
$artifactPackages = '<已安装Artifact Tool的node_modules绝对目录>'
New-Item -ItemType Directory -Path .godot/model_runtime -Force
New-Item -ItemType Junction -Path .godot/model_runtime/node_modules -Target $artifactPackages
```

只在链接尚不存在时创建；也可传`--node-runtime`指向已有同结构临时目录。依赖未安装时入口明确报错，不输出假工作簿。

```powershell
python tools/telemetry_analysis/model_import.py '<导出包.zip>' `
  --workbook '<技能连珠-目标节奏与压力估值-v0.4.xlsx>' `
  --output '.godot/model_import/batch-01' `
  --godot '<Godot控制台可执行文件>' --node '<Node可执行文件>'
```

输出目录必须尚不存在且不能位于输入目录内。可在`inputs`位置传多个文件/目录；ZIP成员只读字节不按成员路径解包。每源上限128MiB、累计512MiB。不能传`user://`给Python，应传菜单打开的本机绝对路径。

输出包括`model-observed.xlsx`、`analysis.json`、`model_inputs.json`、`observations.csv`、`exit_observations.csv`、`groups.json`、`data_manifest.json`、`quality_report.json`、`changes.csv`、五张预览与Reader七表。证据从工作簿→analysis指标→event_id→manifest原文件/行号回溯；这些文件应一起保存。`dataset_hash`只标识去重后的规则事件，`evidence_hash`另包含会话与恢复证据；每个原文件另存SHA256。自动参考页是工具管理区，手动输入和公式继续放原模型页，导入会刷新观测页。

退出码0表示无诊断，1表示产物已生成但数据有诊断、不可自动升为参考，2表示失败，详见报告/日志。没有可用事件时只留诊断，不生成工作簿。旧schema按Reader校验和分组展示；不能升级成新schema。旧七表缺`event_json`无法无损恢复，需提供原JSONL。本次CSV新增完整信封列，旧扁平字段保留；混合CSV与JSONL同event_id只算一次。

### 观测、参考与缺项

按版本、模式、真人上下文、来源、初始化、策略与实验分组；规则异常前缀独立成组且不能进入参考。分层区分阶段、行动类型、构筑、20点压力段以及skill_id/等级/H。即时选卡应用收益与行动总分独立，安装前行动不进入技能暴露，主动退出/工具截尾/未结束不冒充阶段失败。

有合法分母才允许0；缺机会或缺埋点是null，工作簿显示待测并附缺失原因。P10/P50/P90采用floor(q×(n−1))；均值95%区间按局重采样500次，seed=17002，同bot种子合成一个簇。比例另存Wilson区间及相关性说明。真人开发者的30局不代表30位独立玩家。

默认只记录观测，不选择参考组。用`groups.json`确认完整组哈希后，可在下一次导入传`--group <完整哈希>`；只有该组同口径≥30个局/独立种子簇及≥100个有效相关事件，才更新新副本的自动参考区。未选组、缺值、样本不足、诊断均保留该语义键的旧参考。`--min-runs/--min-events`可以提高，不能低于30/100。原设计量、公式和人工值始终保留；本首片尚未把自动参考接入旧技能估值公式。

当前已有得分/独占空间/实际补棋/P/目标与carry/候选选择/安装暴露/退出观察。尚无可可靠推导的直接成线时点、补棋前全清、能力attempt/零效果分母，分别标`match_phase_not_recorded`、`pre_refill_empty_not_recorded`、`ability_attempts_not_recorded`。合法H对照窗口、参考构筑μ_ref及旧模型收益通道映射待#18/#19数据与#17后续接入；不能拿有卡/无卡局相关总分替代净技能价值，也不要求作者手工估数。

### 回归

```powershell
python -m unittest discover -s tools/telemetry_analysis -p test_model_import.py -v
node tools/telemetry_analysis/test_reference_updates.mjs
godot --headless --text-driver Dummy --path . -s addons/gut/gut_cmdln.gd '-gtest=res://tests/rules/test_telemetry.gd' -gexit
```

Python覆盖去重/前缀补齐/冲突/坏行/ZIP路径/完整CSV/会话、明确分母与跨版本隔离；JS覆盖参考值的有效0、缺值保护、分组/等级/H与重复导入。工作簿追加后读回检查原包部件字节保持、公式错误及单元格变更；正式样本还需核对预览与工作簿读回。
