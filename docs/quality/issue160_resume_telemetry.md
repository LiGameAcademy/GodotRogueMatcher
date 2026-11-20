# #160 正式恢复采集段与父链分析

2026-10-30；实施/主要验证基于 #223 合并 `669f92bf726593d3c2173e8f8c5ffb913bf86bef`，交付前纳入 #216 合并 `93d600db72c6d0b12a2756f09e00c156787af147`，组合补测见下文。本片恢复桌面续局后的采集，不关闭 #160/O5。原规则、主备失效与长局边界分别沿前两片报告。

恢复保留逻辑 run_id，新建 session/segment。v3事件ID包含run、segment和段内seq；input/presentation身份同样分段，规则事件ID与随机游标仍按检查点恢复，不为采集改写。首次事件是 `run_resumed`，不会重发 `run_started` 或历史技能/奖励事件。输入点恢复进入真实输入观察状态，冻结组仍等待玩家；只读重建未完成根行动的观察累积器，后续完整行动/取得事件只发布一次。标题页的临时 Board 不挂采集factory，避免读档生成假新局样本；确认新局后仍沿正常v2新局路径。

## 格式与所有权

| 内容 | 当前策略 |
| --- | --- |
| Store容器、主备、journal、失效标记 | 不改协议，失效优先与单worker所有权沿 #217/#223 |
| 规则payload | `run-checkpoint-prefix-v1`不改；六流/候选/原继续位置/幂等与全部验证保留 |
| 新存档package | `run-checkpoint-package-v2`，四字段，携独立telemetry trace；必须有明确已知schema，替代键不能伪装缺失schema |
| 已知旧package | 旧三字段prefix-v1 wrapper可读，规则不补字段；没有trace就显式lineage_unknown，不能冒充完整采集父链 |
| 正常采集 | v1/v2读取兼容，正常新局仍输出v2 |
| 恢复采集 | v3，同run新segment、`run_resumed`/`resume_segment_closed`；旧构建不承诺读新package/采集协议，未知版本拒绝而非迁移/回滚 |

trace分别保存接纳序号与已持久序号、最后事件ID/hash、规则record序号及下一规则事件游标。取trace不强制flush，也不把accepted写成persisted。package与JSONL不是跨文件原子事务；保存失败不会把新trace当成已提交，采集失败以独立诊断保存，不阻止规则存档/独立候选恢复。坏trace不能造出可信父链；规则验证不依赖遥测成功。

主线程冻结trace与resume计划；后台只拿值和独占Store，在独立候选中验证规则、准备独立规则JSONL前缀文件和只读历史缓存，join后才接管。完整前缀写盘不向观察者重新发record_appended。取消后未接管的规则证据文件可保留，但没有新采集run_started，不是自然局样本。Scene接管使用已准备session_id，不再同步重写前缀。新段JSONL只追加新观察；原文件保持原样。旧projector/sink/Recorder/session先关闭，再换factory；错误汇总到本次诊断，不被新段清零，摘要保留telemetry_error/write_failed。正常保存退出只关闭观察段，不假报自然终局或玩家放弃。

观察时钟按新段重新计时。规则Recorder的完整前缀用于规则证据，不能把重建过程或其历史记录时间当作者观察时长。无完整结束的父段/恢复段不补造run_ended、行动、拒选或关闭时间。

## 分析与重复导入

TelemetryReader验证v3段；Report只在同run、匹配规则/内容/配置/来源等元数据下，沿唯一parent segment与seq/hash锚连接。锚点实际未落盘、缺父、坏锚、循环/断链、多个叶分支等均诊断排除，**不挑最长链、最新墙钟或任意叶子**。检查点后的旧尾部作为原始事实保留，不能覆盖/删除。

合法唯一链生成带source_event/source_event_id的v2分析视图，逻辑run及奖励/行动分母只算一次；恢复边界是观察边界，不是新run_started。段内elapsed转换只连接实际观察时长，不填离线空档。`resume_lineage.json`保留全部原事件、段关系及被回退事件ID；派生CSV能还原原始事件，再与原文件重复导入，不制造冲突或独立样本。分析视图不是重写后的产品日志。

Python导入先按segment暂存，再复用既有Godot Reader/Report/CLI。正常统计核心未另造；缺失/非字符串/不匹配session的segment明确诊断，lineage文档按schema识别而非文件名；坏派生source只能保留已验证前缀，不能回用未经验证view。写失败摘要在段摘要跳过前保留诊断。#216实施期间原留审文件未改，交付前按其实际已合并状态纳入；analysis_cli/bounded_analysis/bounded_observation及其README仍无本片改动，**本片不承诺有界模式支持v3**。

## 实测与审查

Godot4.7.2 ed1daf0bf / GUT9.6 / Windows；APPDATA与所有测试目录隔离，没有作者真实样本。证据、命令、逐文件SHA256/规范化Git blob见 `docs/evidence/issue160-resume-telemetry/`。

- 相关组合 **11脚本90/90、925断言、79.005秒、退出0**，无SCRIPT ERROR/Parse Error/ObjectDB/resources still in use；没有跑整库。覆盖规则payload/worker/坏档回备、原采集生命周期、真实菜单接管及新恢复矩阵。随后仅收紧六个观察策略/实验兼容字段及对应断言，受影响2脚本 **12/12、165断言、11.208秒**通过；运行时/worker/GPU路径未变，不重跑无影响大组合。Python导入/原模型/成对统计 **39项，0.453秒，通过**。
- 新用例覆盖accepted>persisted真实队列且不能抬高持久锚、缺尾诊断/稍后真实flush后验证、规则坏主回到previous的旧trace、保存失败保留旧trace而新观察继续、实际规则文件准备失败与采集sink路径失败不阻规则保存、错误状态跨factory延续、未完成冻结根行动不重发技能/行动、旧文件hash不变及新前缀可独立规则回放。
- 真实菜单用例确认临时局无projector/new run_started，实际继续后同逻辑run、worker预备文件不重写、观察进入board_input且原快照相等。首次发现presentation状态未更新，真实RED后修正观察适配层，随后通过；没有放宽规则门禁。
- 最终真实文件probe PID30964：父段在检查点后实际行动一次，恢复同一点的新段也实际行动一次，两个原始动作只生成**一个**规范化动作。旧文件hash不变，父/子session不同、run相同，同一后续命令的完整规则快照一致。原文件及派生报告一起重复导入：1逻辑run、2段、21个原始唯一事件→11个分析事件；现有CLI退出0，runs/events/groups/opportunities/errors/resume_branches六项逐项相等。原统计分析器也是1run、候选基线指标0，不把自动探针当真人/足量样本。
- 纳入93d600d时运行时/GPU源码未变化，仅补已有bounded专项 **8/8、286断言、14.03秒**。新基线默认CLI处理同一真实暂存数据，退出0、上述六项再次逐项相等；bounded模式对v3明确`invalid_telemetry_header`，并保留父前缀无完整结束诊断，退出1、bounded.complete=false。这是已知不支持，不能写成完整恢复采集分析通过或静默忽略错误。
- GDScript独立code-reviewer与Python独立python-reviewer最终均APPROVE。复审及实际验证中定位的wrapper缺schema、坏segment崩溃、改名文档拒绝、派生view验证失败回用、旧诊断丢失等均有针对性修正和用例；失败/RED日志原样压缩保留。审查未运行引擎，不替代运行证据。Game500行，Board原492行本片未改；相关自有代码均≤500行。

## 最新GPU成本与未完成出口

RTX2070/OpenGL3.3 Compatibility，1280×720，真实渲染/viewport继续与取消按钮，95行动887条记录、约10.38MB的正常旧存档；这是仪器化GPU场景，不是Windows物理鼠标黑盒或作者试玩。最终PID19416自行正常退出：取消保留旧Run且worker仍占用，重试后完整snapshot相等、旧局退役、输入开启。

第二次加载worker等待7.617秒/459帧，最大17.526ms；完整前缀准备479.673ms在后台。**主线程最后接管仍为266.121ms**，属于恢复时剩余卡顿，17ms不能当端到端帧预算通过。正常保存退出worker等待10.383秒/625帧，最大18.222ms，冻结最新值14.251ms。10秒仍只对decode完成后的耗时作接受检查，不能抢占，也不是端到端10秒上限。首次取消任务222.695ms尖峰包含同步截图编码，缺少因果时序，不能归因截图或规则。较早本片GPU的297.531ms接管/493.300ms后台准备/32.672ms等待间隔也保留，不挑更好数据抹掉波动。

旧95点没有trace，因此本次GPU恢复段显式lineage_unknown，不计入比较基线；它只验证旧格式恢复、文件准备/接管、取消与退出。正式父链证据来自上述新package实际probe。15/16MiB、4096记录上限与长期成本仍沿原报告，不承诺任意长局保存。

后续按完整出口推进：先分项profile对象挂载/视图构建/采集接线，决定是否做必要的最小优化；实际应用正常关闭/重启、写中受控强杀与上一验证代保证；单线程Web持久化/刷新/无Thread路径。本片新段实际落盘不能冒充强杀或Web通过。#160/O5保持开放，整体完成后集中作者review/试玩。

主动工程/分析/审查工时无法可靠分离，记未知；不以机器等待、墙钟或父子代理叠加替代人工。A2余额/日期仍由集成复核，不承诺预算内完成。
