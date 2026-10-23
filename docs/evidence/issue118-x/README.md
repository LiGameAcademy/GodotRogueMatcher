# ×模板切片验收证据

2026-10-23。基线为 #174 提交 ed49753f82226b14c53709c46db4fbdd9596f346；受测代码 62759dd6201bdf7224825a70eea714421a6e3f9d。

Godot 4.7.2 / Compatibility，GUT 9.6.0。无界面、固定 60 FPS，使用 .godot/issue118-x/ 下进程级 APPDATA/LOCALAPPDATA 隔离目录。

- `full-output.log`：完整回归103脚本、753/753、24018断言、213.747秒，退出0，无新增解析错误或Resource/ObjectDB泄漏；`summary.json` 为脚本/测试/断言/时间/退出码及受测身份汇总，`script-results.json` 为逐脚本统计。
- `target.log`：专项 23/23、204 断言；`import.log`：编辑器导入检查。
- `line-counts.json`：自有 GDScript 行数清单（每个不超过500行）。
- 三份实际新记录：`x-unlock-record.jsonl` 13 条、`order-l-x.jsonl` 17 条、`order-x-l.jsonl` 17 条，分别在独立进程回放；对应 replay 日志成功。
- 六份旧 v43 记录：../issue118-plus/ 与 ../issue118-t/ 中的单形状及两种 L 混合取得顺序，各自13/17/17条，分别由独立进程精确回放成功。summary 中列出每份原始记录路径及 SHA256。
- `manifest.json` 保存证据字节数与 SHA256，README 本身不纳入。原始日志/JSON/JSONL 禁用换行转换，保证提交后可复核。

完整测试命令：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加 `-gselect=x_template`。每次 CLI 回放均启动新进程、使用独立数据目录：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

只读 code review 结论 APPROVE，无阻断项；核对权威模板、不允许45度旋转、对角长臂并集7/104、L/×并集7、三×传递并集11、真实统一入口及配置/类型/行数。完整回归与独立回放由主 agent 另行完成，以原始日志和 summary 为准。

本片只接入×共享模板和显式验收解锁配置，生产池不变。规则仍 v43，不代表 v42 可跨版本精确重算；自动正确性不代表真人体验通过。开发基于 #174；作者已合并 #173/#174，本片直接面向 develop/0.0.3，作者保留 review/合并权；下一片为 Z/S。详见 ../../quality/issue118_x_template.md。
