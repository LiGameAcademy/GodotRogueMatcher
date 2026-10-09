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

Reader按版本校验v1/v2，v1缺失的新维度保持unknown。v2的turns.csv来自action_resolved，不再叠派生turn_resolved；mode_id/collection_context/commit/pressure/collection_config加入分组。可直接分析菜单导出ZIP中的telemetry JSONL；自动解包与Excel回填仍在#17，不声称现有CLI能一键处理ZIP/xlsx。

工程场景 tools/telemetry_analysis/collection_benchmark.tscn 生成 .godot/collection_benchmark.json。它测冻结事实投影、编码与批量IO，排除规则、UI、初始化和终局，不能当作60FPS增量帧基准。collection_probe.tscn接收 -- hold|recover <测试目录>，只用于独立受控进程；结束该探针前核对ready.json的PID，不对作者运行中的编辑器进行强杀。真实Editor Stop仍须人工验收。
