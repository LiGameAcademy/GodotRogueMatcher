# 恢复采集段证据索引

结论与边界见`../../quality/issue160_resume_telemetry.md`。主要验证基线669f92b，交付组合基线93d600d；`tested-source-sha256.json`记录最终受测源文件原始SHA256/仓库LF规范化Git blob及物理行数，index逐项核对。11脚本组合与GPU之后只收紧TelemetryLineage的六字段分析兼容门禁和对应断言；`lineage-before-final-compat.json`保留该文件组合时SHA256，追加专项覆盖最终门禁，不把此前运行身份写成未改变。纳入93d600d没有改本片运行时或GPU源码。

## 回归

`resume-final-output.log`：11脚本90/90、925断言、79.005秒、退出0，无解析/对象资源退出诊断。隔离APPDATA `.godot/resume-final-sandbox`。

```powershell
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 --log-file .godot/resume-final.log -s addons/gut/gut_cmdln.gd '-gtest=res://tests/rules/test_resume_telemetry.gd,res://tests/rules/test_telemetry.gd,res://tests/rules/test_collection_lifecycle.gd,res://tests/rules/test_collection_batches.gd,res://tests/rules/test_run_checkpoint_codec.gd,res://tests/rules/test_checkpoint_job.gd,res://tests/rules/test_checkpoint_recovery.gd,res://tests/integration/test_resume_collection_flow.gd,res://tests/integration/test_desktop_checkpoint_flow.gd,res://tests/integration/test_telemetry_scene.gd,res://tests/integration/test_release_flow.gd' -gexit
```

最后兼容门禁专项`resume-final-compat-output.log`：12/12、165断言、11.208秒、退出0；相同命令入口，仅gtest指定`test_resume_telemetry.gd,test_resume_collection_flow.gd`。`resume-python-final-output.log`：`python -m unittest -v test_resume_import test_model_import test_paired_statistics`，39项/0.453秒通过。

`resume-combined-output.log`：93d600d组合仅补`test_bounded_analysis.gd`，8/8、286断言、14.03秒。`resume-combined-result.json`与两个CLI日志：原默认入口六项等价/退出0；`--bounded <真实telemetry目录> <独立输出>`对v3为invalid_telemetry_header并保留父prefix未结束错误，退出1/complete=false，已知不支持而非通过。`combined-reader-summary.json`保留默认入口结果。

`resume-*-red/green/runtime/lineage/matrix/scene`等早期日志分阶段保留。失败日志gzip保持原始终端字节：初始身份/trace RED；早期v3 merge未覆盖schema引发unknown event/空数组测试错误；Python缺segment未捕获KeyError及改名文档误拒绝；真实菜单恢复观察停presentation。修正后对应专项与组合通过，未调规则/数据门槛凑通过。原系统根证书/故意IO失败诊断保留。

## 实际文件往返

`resume-real-probe-final-output.log`、`resume-probe-last.json`：正常规则seed23，源人类协议字段+`automated_integration`环境标记，机器执行，不能当真人样本。工具`tools/checkpoint_benchmark/resume_telemetry_probe.gd`，隔离APPDATA `.godot/resume-real-probe-final-sandbox`，普通headless `-s`入口，PID30964退出0。

`sources/telemetry/`保存真实父/恢复JSONL、session和摘要；`sources/records/`保留规则证据前缀，`sources/slot/`为对应检查点。旧父段在checkpoint后和恢复子段各行动一次，父段9条尾部事实被标记回退但原件hash不变；恢复附着只有run_resumed，两个实际动作在规范化视图只算一个。

`original-report/`为第一次Reader输出，`roundtrip/manifest.json`为原文件与派生报告一起再次ingest的清单，`roundtrip/report/`为现有CLI重新读取分段暂存的输出。`roundtrip/result.json`六项逐项相等、1run/2segments、21原始唯一事件→11分析事件，CLI退出0；`roundtrip/analysis.json`原统计核心仍1run、candidate指标0。命令链：

```python
manifest = ingest([Path("sources/telemetry"), Path("original-report")], Path("normalized"))
# 沿用原Godot工具：analysis_cli.gd -- normalized report
# 读取report/events.csv的event_json，再交model_statistics.analyze(events,30,100,17002,0)
```

重现时在独立输出目录使用此链，不覆盖随附证据；`resume_lineage.json`是包含原事件的证据文档，派生CSV通过source_event还原后去重，不能把派生行作为第二次自然观察。

## GPU

最终`resume-gpu-final-report.json`与同名log/四张PNG：RTX2070/OpenGL3.3、1280×720，PID19416自行退出。普通GUI引擎、独立APPDATA `.godot/resume-gpu-final-sandbox`，将前片正常benchmark的95行动primary/previous复制到该私有run_checkpoint，运行`-s tools/checkpoint_benchmark/desktop_gpu_probe.gd -- --prefix=resume-gpu-final`。

实际viewport输入命中继续/取消；95行动887records snapshot完全一致、旧Run退役、输入可用、正常保存退出。加载等待7.617秒，后台前缀准备479.673ms，等待最大17.526ms；**接管主线程266.121ms**另列，不能称端到端帧预算通过。退出保存10.383秒，等待最大18.222ms、最新冻结14.251ms。首次取消222.695ms最大间隔混入同步截图，不归因。前一次`resume-gpu-report.json`/log保留297.531ms接管及较大间隔波动。

v1旧存档无采集trace，所以该GPU例的恢复段lineage_unknown并排除比较，不能当正式父链证据。性能接受边界仍为10秒decode后软检查，非端到端硬期限。没有Windows物理鼠标黑盒或作者样本。

## 独立审查与未测

GDScript `/root/review_status` 与Python `/root/resume_python_review` 最终APPROVE；包括失败诊断延续、最终六字段兼容门禁。两者只读、未跑引擎。相关代码≤500行，diff check通过。#216原留审文件未改，交付时已按实际合并状态纳入；不外推其bounded模式支持v3。

余项：主线程接管分项profile/必要优化、实际应用关闭重启/写中受控强杀、Web持久化刷新及无Thread路径。普通退出不能替代强杀，#160/O5不关闭。
