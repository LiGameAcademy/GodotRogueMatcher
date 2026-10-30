# 随机参数实验登记与分析产物预检

这是 #88 的离线准备工具，只用 Python 标准库。它不运行机器人、不采样候选、不重算权重、不推荐或接受参数，也不写 Godot Resource、存档或工作簿。原始遥测仍由既有 Godot Reader/Report 分析，不在这里复制解析器。

先创建一个新的输出父目录，再登记实验：

```powershell
New-Item -ItemType Directory '.godot/calibration-prep'
python tools/random_calibration/calibration_cli.py plan --first-seed 1000 --output .godot/calibration-prep/plan.json
python tools/random_calibration/calibration_cli.py audit .godot/calibration-prep/plan.json docs/evidence/o1-bounded-analysis/bounded-summary.json --output .godot/calibration-prep/preflight.json
```

第二个命令使用已归档的真实小样分析产物，仅验证其报告契约；不会把旧小样认作新实验结果。新的分析产物可替换该路径，也可一次传多个summary。不得传原始JSONL、CSV、工作簿或ZIP。输出文件必须不存在；输入不覆盖。测试无需外层工作区或引擎：

```powershell
python -m unittest discover -s tests/offline_calibration -v
```

## 登记边界

plan默认给出3局smoke、100种子explore、150新种子confirm的**实验起始预算**，不是统计充分或验收达标门槛；可用`--smoke/--explore/--confirm`显式调整。三个阶段种子不重叠；同阶段各配置使用相同游戏种子。confirm数据应在候选冻结后另采，不因种子提前登记就声称独立复核已完成。种子是非负63位规范十进制字符串，溢出/前导零拒绝。

先登记a=0/.25/.5、d固定.25的三组；d扫描只登记候选值和selected_a=null，等a阶段核对后再明确，不自动展开笛卡尔积或选择a。接受标准的最小有意义差异、最大不确定度、最大采样量和停止规则默认null；填写数值时须给单位。未知保持未登记，不能从报告结果临时倒填接受线。

现有`tools/bot_testing/batch_cli.gd`没有OfferConfig参数覆盖接口。此片明确标记runner_parameter_injection_unavailable，不生成虚构的`--a/--d`执行命令，不用固定快照重新算权重冒充新策略完整对局。参数注入、实际分组绑定、种子/父局索引、区间估计和正式批次仍需单独实现/协调；尤其不要以当前配置反推旧报告的参数。

## 支持与输出解释

仅支持`telemetry-report-v1`产物中schema 2、规则`run-commands-v46-unified-offer-audit`、抽选`offer-unified-trial-v2`的分组；需无分析错误且完整非空pool_audit覆盖。恢复遥测schema 3或含resume_branches（即使分析器已归一化成schema 2）一律标unsupported，不能当完整样本。未知版本、坏记录、bounded.complete=false、无机会和缺维度均保留拒绝原因，不给缺覆盖填0。未来v3适配必须另补来源/回退/独立父局证明，不能只扩大白名单。

source/初始化/策略/配置/版本等维度逐组原样保留；fixture、真人、截尾/非终局仍可被看见，但显式列pending，不混入自然机器人接受结论。reported_runs仅转述报告值，独立parent数、首次发动机/连携等待、自然失败与目标完成拆分、高k覆盖、种子/变体对应均不能从summary可靠推导，保持null或缺项原因。

相同字节SHA256报告记为aliases；不同报告可能重叠，**不相加局数/事件/机会**，也不合并它们的配置组。每份最多8MiB，最多64份、累计读取32MiB；重复JSON键、NaN/Infinity及指数溢出拒绝。SHA256只追踪输入身份，不是签名；预检不独立验证原始遥测、整套分片或报告生产者的完整性，应保留原分析manifest/诊断并使用已有Reader的实际结果。

退出0只代表登记写出或summary契约预检有效；输出始终`status=preparation_only`、`ready_to_select_parameters=false`、`parameter_acceptance=null`。退出1表示已写出拒绝/缺覆盖报告；退出2表示参数、注册结构、JSON、IO或输入预算失败。即使退出0，未登记标准和执行接口缺口也不会消失，不能据此回写参数或关闭 #88。磁盘写失败的部分文件不是成功产物。

测试夹具带fixture标识，仅作合成契约正反例，不算真实对局或真人观察。工具不会修改O5的恢复、采集、Reader/Report或importer，也不触及主种子RG入口。
