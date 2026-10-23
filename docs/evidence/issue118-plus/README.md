# ＋模板切片验收证据

2026-10-23。基线为 #173 待审查提交 e3e06104b86093f3e068b061e1ca8d2dd72fd19c；受测代码 a4b51ed4695fbecac0da9261055eea27991b8010。

Godot 4.7.2 / Compatibility，GUT 9.6.0。无界面、固定 60 FPS，使用本项目 .godot/issue118-plus/ 下进程级 APPDATA/LOCALAPPDATA 隔离目录。

- `full-output.log`：完整回归 100 脚本、730/730、23814 断言、200.808 秒，退出 0；没有脚本解析错误或 Resource/ObjectDB 泄漏。
- `target.log`：首轮专项 20/20；`target2.log`：补充 profile 隔离和拒绝路径后 22/22、202 断言。`import.log` 为编辑器导入检查。
- `script-results.json` 为完整回归逐脚本统计；`line-counts.json`：339 个自有 GDScript，最大 474 行。
- 三份实际 v43 新记录分别由独立进程回放：`plus-unlock-record.jsonl` 13 条、`order-l-plus.jsonl` 17 条、`order-plus-l.jsonl` 17 条；对应 replay 日志均成功。
- `replay-old-t.log`、`replay-old-l-t.log`、`replay-old-t-l.log`：独立进程分别精确回放 ../issue118-t/ 中同名含义旧记录（13/17/17 条）。旧 profile 和候选指纹保持不变；并不表示 v42 兼容。
- `summary.json` 汇总受测身份、运行结果及每次独立回放的来源与哈希；`manifest.json` 覆盖证据字节数/SHA256，README 本身不纳入。

完整测试命令：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加 `-gselect=plus_template`。每次 CLI 回放使用新进程及隔离目录：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

只读 code review 结论 APPROVE，无阻断项。Review 核对固定模板、生产池隔离、profile/配置指纹、v43 边界、统一流程与类型/行数；其后主 agent 完成上述完整回归及六次独立回放。

本片不关闭 #118，不代表真人体验通过；只提供＋共享模板与显式验收解锁配置。新 PR 依赖待审查 #173，暂叠在 feature/118-t-template；作者合并 #173 后再改目标至 develop/0.0.3。本片不自动合并。详细结论见 ../../quality/issue118_plus_template.md。
