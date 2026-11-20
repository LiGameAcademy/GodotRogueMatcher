# #119 试玩汇总与筛选结果整理

将`screening_records`中的原始JSONL和同名`-screening.json`摘要整理为可读报告；人工观察、筛选结论单独录入。工具不修改原始记录、不自动保留或关闭形状。O4继续冻结。

## 先汇总，再填写观察

在Godot工程目录运行（`$engine`为本机Godot 4.7.2控制台程序路径）：

```powershell
& $engine --headless --path . -s tools/screening_analysis/report_cli.gd -- <记录目录> <新的输出目录>
```

只读取该目录下直接包含的.jsonl，不递归子目录；配套摘要从同目录同名文件读取，不跟随摘要中的record路径寻找其他文件。建议先完成并封存当前样本，再汇总。未封存、截断或损坏记录单列错误，不当作零分/未触发。

输出三个文件：

- screening-report.md：六配置总表、单条样本、人工固定题核对、原文观察、手填结论及诊断。
- screening-report.json：结构化结果，含原记录路径/SHA256、来源、配置/指纹、种子、窗口、得分/行动/空位/来源统计，以及独立人工字段。
- observations-template.json：待填写观察与结论模板，真人未观察字段均null。

复制模板为自己的observations.json，只填写确实观察到的内容，再生成另一个新目录：

```powershell
& $engine --headless --path . -s tools/screening_analysis/report_cli.gd -- <记录目录> <另一个新输出目录> <observations.json>
```

原始JSONL、自动摘要、人工笔记和既有输出均不被覆盖。输出目录可以存在，但三个目标文件任一已存在就报错，不覆盖旧报告；换新目录生成下一版。源记录仍是权威证据，报告是只读投影。

## 人工字段

文档schema=screening-observations-v1，顶层只有observations和decisions两组数组。模板保留真实run_id，勿改成参与者ID；同一run_id只能出现一次。

| 字段 | 填写方法 |
| --- | --- |
| participant | 匿名参与者ID；未知null |
| role | author或new_player；未知null |
| round | initial或retest；未知null |
| explanation_count | 截至该题核对时的累计说明次数，非本题新增次数；未知null，不默认0 |
| prediction_correct | 实际核对后的true/false；未核对null |
| planned_layout / willing_again | 实际观察/回答的true/false；未知null |
| use_case / interference / notes | 参与者用途、材料干扰、其他原文；未知null |

填写任何观察时，participant、role、round必须一起明确。false表示确实观察到否定结果，不能用它填补未知；空字符串、字符串“false”、用0代替布尔或错拼字段均会报诊断。unknown字段仍null，不以分数推测人的理解、布局意图或选择意愿。

来源为screening_playground仅表示来自试玩入口，初始仍是human_unobserved，并不证明有人参与。机器人/自动夹具/未知来源不能被标注成真人。自动文件中的participant/predictions/selection_decision不作为人工证据入口，使用独立观察文件关联run_id；不编辑原始记录来“修”结论。

## 固定题3/4核对

按参与者、作者/新玩家、首测/复测、配置ID、完整配置指纹、build和seed分组。只有四个不同题目均有明确预测布尔，且每题核对时的累计说明次数都明确为1，才输出once_explained_three_of_four布尔；缺题、未知说明、重复题均null。

已观察题数与正确数单独保存，未观察的正确数是null，不补成0。作者/新玩家、不同build/配置指纹/种子和复测不混算。旧入口的build可能只是development，不含Git提交；若不同提交仍有相同build和配置指纹，工具无法自动区分，主持人必须按实际受测提交分目录运行，并在笔记登记提交。报告不认证构建身份。3/4只是既有试验方案的暂定排查指标，不是统计置信结论，也不会自动生成“保留”。布局解释、选择理由、混合可解释性和作者判断仍需人工证据。

## 整理筛选结论

每配置的decision、reason、author_confirmed、evidence_run_ids、config_hash、build初始均null，保留config_id。无需结论时整行保持空，不能由最高分、零分或机器人成功补齐。

手填结论可为retain（保留）、adjust（调整）、disable（关闭当前配置）、insufficient（证据不足）。必须填写非空理由、适用的build/config_hash和作者确认布尔；false表示待作者确认，true仅为人工录入声明，工具不认证身份或替代review。

保留/调整/关闭必须引用非空、实际存在、同配置/指纹/build的run_id，且至少一条有合法人工标注。insufficient允许明确的空证据数组，但仍须手填适用版本、理由及确认状态；它不会自动产生。证据引用不等于全部验收门槛已满足，作者仍按原方案核对缺覆盖和选择理由。本工具不改变GitHub议题、名单、配方或游戏开关。

重复人工run_id或重复配置结论会把该ID/配置的冲突内容全部隔离，而不是按文件顺序选第一条。改正原观察文件后重新生成新报告即可；原笔记不会被工具重写。

## 自动数据的口径与诊断

- 每条记录须先完整精确回放，保持当前Godot版本/v43兼容约束；缺Footer、篡改、记录写入失败和摘要冲突均单列，不伪装成功样本。
- 校验实际模板几何与ScreeningConfig一致，并限定v1的9×9/五连/经典模式。仅有相同shape_id或初始化名称不算同配置；其他配置另立版本，不能混入本报告。
- 同run_id且原始记录/摘要字节都相同的副本只计一次；字节冲突则隔离该run_id的全部副本。诊断保留来源路径，不能用“最后文件覆盖”消除分歧。
- 匹配事件按event_id去重；共享移除按棋子ID去重；形状事件每种形状每事件最多一次。直线/模板命中数不重复增加基础分。分数取真实Footer，来源分列取已记录事件。
- births_in_window不含Header之前的正常初始出生；出生来源单列。net_empty_cells为样本起点占格减终点占格，正值表示净腾空，负值表示变拥挤；不是只算消除数量。
- 完整固定题须1行动且正确封存；自由窗口按v1的15行动或480秒核对，自然终局另列。缺时间摘要时elapsed_ms及时间窗口完整性可为null；缩短测试窗不冒充正式15行动/8分钟。
- 自动记录数/得分/消除等可以为已观察的0。人类理解、自然遭遇率及筛选结论不会由这些数值推断，未知仍null。

退出码：0=生成完成且无错误；1=输出失败或目标文件已存在；2=输入/标注校验错误。多文件中部分出错时仍输出有效样本与诊断，并返回2；不要忽略诊断把它当成全通过。其他旧profile记录标为不适用警告。

## 本片样例与范围

样例来自#184已归档的34条记录：24固定题、6个机器人15行动窗、4条UI封存测试。自动来源30条；4条“试玩入口”仍无人工观察，其中缩短窗口明确不算正式完整自由样本。模板和示例报告没有虚构参与者、预测、意愿或作者结论。单元测试中的合成参与者仅用于验证类型/分组逻辑，不是体验证据。

首次运行只生成空观察表；后续由主持人依据真实笔记填写。正式筛选人员、双形状选择、真实取得观察、#120配方和#121综合验收仍待推进。
