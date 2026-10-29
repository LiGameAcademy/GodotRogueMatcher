# #119 当次试玩执行清单与空白观察表

2026-10-29准备包。没有预约、邀请或实际真人观察；不决定保留名单。作者六题仅为历史工具走查，自动鼠标复测不计正式参与者。

## 开测前由作者落实

| 条目 | 当前值 / 要求 |
| --- | --- |
| 主持人 / 匿名参与者ID | null / null；不用真实姓名替代必要匿名标识 |
| 作者或未参与设计者 / 是否参与设计 | null / null；作者与至少2位非设计者分开 |
| 两次可用时段 / 实际设备 | null / null；沿既定约90分钟/人分两次、总约6人时起点，不自动追加 |
| 系统 / 缩放 / 视口 / 普通或低特效 | null；记录实测值，不从截图推断DPI |
| 候选commit / 工作树是否干净 / 引擎与依赖 | null；开测前登记实际候选，不填计划版本 |
| 样本目录 / 笔记目录 / 截图目录 | null；每个提交、参与者、首测/复测分目录 |
| 单形状轮换顺序 / 说明方式 | null；开测前登记，避免全部按同顺序；第一次只说明一次 |
| 两组双形状 / 拟保留混合 | null；由单形状证据交作者决定，不预选全部模板 |

先在本机确认完整鼠标选卡→查看棋盘→返回→确认可用；发生遮挡、写盘错误、规则错误则停止对应体验判断，留失败记录和实际覆盖。两尺寸普通/低特效的自动通过不替代参与者体验。

## 实际操作顺序

1. 用明确候选打开`tools/screening_playground/screening_playground.tscn`。默认直线自由模式。准备好独立笔记，再选择配置、任务或重置；加载完成即开始墙钟，切题会封存旧样本并生成新run_id。
2. 先直线基线，再按预登记轮换L/T/＋/×/Z-S单形状；每形状四固定题，在行动前记录预测坐标与是否补棋。主持答案仅在[题集](issue119_single_shape_kit.md)中核对，不提前展示给参与者。U/环/方块仍为后批候选，不挤进首批全部流程。
3. 记录每题核对时的累计说明次数、额外提示和原话；不反复讲解凑3/4。奖励时工具缩为左上三个控件；查看时全隐藏，返回后可原样确认或切题。没有继续意图时封存中断，不能补造完成。
4. 自由模式按原窗口15个有效玩家行动或480秒先到；暂停/菜单/选卡计时，达到窗口后等待原行动、奖励与继续义务完整收束。无自然触发照样保留，两段未触发记“自然遭遇不足”；固定题不能代替自然体验。
5. 作者依据可用单形状批次决定两组双形状和拟保留混合，再验证共享材料、复测基线并记录学习效应。真实取得/立即全盘扫描/奖励恢复另列，开局profile不当真实取得历史。
6. 预算触顶、疲劳、Bug或缺样本均记录“证据不足/未覆盖”，沿既定最多一轮针对性调整和一次复测；不降低门槛。形状可读性与构筑强度分开结论，保留/调整/关闭由作者确认。

## 每样本空白笔记（复制后填写，未知保留null）

| 字段 | 待填写 |
| --- | --- |
| session_id / 日期时间 / run_id | null / null / null |
| commit / rules_version / rng_protocol / config_hash | null / null / null / null |
| seed / profile / config_id / task / 首测或复测 | null / null / null / null / null |
| 参与者匿名ID / role / 是否参与设计 / 测试顺序 | null / null / null / null |
| 操作前预测坐标 / 预测补棋 / 实际是否正确 | null / null / null |
| 累计说明次数 / 本题额外提示 / 参与者原话 | null / null / null |
| 主动布局或意外触发 / 准备行动 / 未完成计划 | null / null / null |
| 材料干扰 / 净空间与完整行动得分 / 自然遭遇 | null / null / null |
| 能否解释连携 / 愿否再选 / 用途或拒选理由 | null / null / null |
| 实际行动数 / 时长 / 停止原因 / Bug或疲劳 | null / null / null / null |
| 原始JSONL / sidecar / 截图 / 独立人工笔记路径 | null / null / null / null |
| 保留、调整、关闭或证据不足 / 理由 / 作者确认 | null / null / null |

null不等于0、false或失败。自动分数不能推断预测、意愿、提示次数。实际规则观察可为0，但未观察的真人字段不得补0。

## 封存、读盘与报告复现

界面封存后从当次`user://screening_records/`成对复制原始`<run_id>.jsonl`、`<run_id>-screening.json`到新目录；保留原文件字节与SHA-256，不编辑Header、Footer或sidecar人工字段。未封存/损坏/写盘失败保留为无效或不完整，不补Footer。

JSONL Header抄取实际config_hash、seed、initialization、rules_version与rng协议；`build=development`不能唯一标识Git提交，必须另在笔记登记commit/工作树与引擎。当前v44/sl-rng-v1只按本候选精确回放，旧v43保留历史身份；O1后续抽选变更需另建版本与样本，拒绝旧记录不等于旧证据造假。

在实际游戏工程目录，用本机引擎替换`$engine`，`$record`填封存原始文件，输出目录每次新建：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay $record
& $engine --headless --text-driver Dummy --path . -s tools/screening_analysis/report_cli.gd -- $records $newReport
```

逐份精确回放退出0才记技术记录有效；规则/候选/版本不符、缺Footer或报告诊断应单列，不能用结果观看代替精确重算。报告工具产出observations-template.json，保留真实run_id，复制为独立observations.json后只填实际观察，再输出另一新目录：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/screening_analysis/report_cli.gd -- $records $anotherReport $observations
```

三个输出文件不覆盖旧报告；读取范围是目录直接包含的JSONL，sidecar放同目录。自动样本独立分目录并标automated/retest，不混入真人报告。原始记录不变，人工笔记和结论通过独立文件关联run_id。预期无诊断时退出0；退出1/2应保留诊断并处理，不略过。

## 交作者的出口

逐配置给完整覆盖/缺覆盖、原始记录与回放结果、提示次数/预测/用途/意愿原话及保留建议；名单与正式配方由作者确认后再交O1/O3/O4。当前上述真人字段、名单、配方均null，不自动入正式池或关闭#119/#192。
