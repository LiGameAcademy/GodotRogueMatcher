# 四张计分卡规则说明证据

2026-10-30，香港时间。受测源码及导入翻译为`64f468b199b96c76292dfcb0891662441ca83dcc`，基线`a9e5ebb8cfbc0b4a3c0af654d19363f60528c393`。后续提交仅增加证据与质量说明；不把旧工作树成绩当成本树验收。

| 记录 | 恢复后实际结果 |
| --- | --- |
| score-regression.log | 5脚本45/45、1098断言，exit0；实际计分、描述、全池覆盖、扫线与爆破构筑 |
| ui-regression.log | 4脚本14/14、3936断言，exit0；本批真实取得/冻结候选、当前构筑/卡池、满级，既有卡面/构筑与全池只读语境 |
| gpu.log | Compatibility GPU 1脚本2/2、243断言，exit0；8截图已逐张目检，正文/预览/选择状态及确认区未见裁切或遮挡 |
| coverage.json | 读取52个正式Resource、实际Effect树与声明等级：16生成、36人工回退。无限升级旧路径仅审一级配置，不宣称穷举无限等级 |
| import.log | 独立clone首次导入，exit0；最初缺少字体导入缓存，随后导入完成。保留初始诊断，不隐藏它们 |

每份日志同时保存原始字节`.gz`和去ANSI/行尾空白的可读版。环境、结果、产物哈希见validation.json；受测路径、工作副本与提交blob哈希、相关代码行数见source-manifest.json。

图片为真实PopupSkillChoice，采用正式Resource并通过现有取得入口先取得一级，再用真实冻结候选展示Lv.1→2。group0为连珠补分/爆破补分/余震奖励；group1以扫线收获替换首卡。EN/ZH × 1024×640/1280×720 × 两组，共8图。有限GUI检查用普通明亮主题与低特效，未宣称穷举主题、所有等级或完成真人读感验收。相关旧卡面测试另覆盖普通/低特效与全52卡。

Godot4.7.2 ed1daf0bf / GUT9.6，Windows，NVIDIA RTX2070、610.88、OpenGL3.3 Compatibility；APPDATA/LOCALAPPDATA隔离到临时目录`o4-score-independent-review`。最终三个运行日志仅有已知沙箱root certificate store错误及可选设置不存在的默认提示，无脚本/解析失败或资源泄漏退出警告。GPU进程正常退出；没有性能或弱机结论。

## 恢复与复现

旧worktree两次消失，历史见recovery-history.md；来源仍未知。作者随后授权从远端完整独立clone继续，当前Git根为`execution/o4-score-independent`，`.git`是独立目录，没有commondir/alternates，也不共享原worktree登记。原备份和异常现场保留。旧46/46成绩及缺文件导致未启动的UI检查均不计入本次结果。

从本PR检出、初始化锁定子模块并完成Godot editor导入后，可分别运行：

```powershell
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path $env:TEMP 'o4-score-independent-review'
$env:LOCALAPPDATA = $env:APPDATA
& $engine --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_score_rule_descriptions.gd,res://tests/rules/test_skill_description_coverage.gd,res://tests/rules/test_skill_rule_description.gd,res://tests/rules/test_line_clear_removal.gd,res://tests/rules/test_demolition_build.gd -gexit
& $engine --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_score_rule_description_ui.gd,res://tests/integration/test_skill_pool_rule_context.gd,res://tests/integration/test_skill_cards.gd,res://tests/integration/test_build_cards.gd -gexit
$env:O4_SCORE_CAPTURE = '1'
& $engine --path . -s addons/gut/gut_cmdln.gd -gopacity=0 -gtest=res://tests/integration/test_score_rule_description_ui.gd -gexit
```

#129仍为部分交付OPEN，作者读感、非设计者和整体真人体验均null。按B交集成核验，合入develop不等于整体验收或发行通过。
