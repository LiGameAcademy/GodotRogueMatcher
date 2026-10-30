# 失效失败与规则回备证据

结论见 `../../quality/issue160_failure_recovery.md`，基线3710131。`tested-source-sha256.json`记录受测文件原始SHA256及仓库LF规范化Git blob；逐项核对index与受测文件相同，测试后不再改生产源码。

## 最终回归

`recovery-final-output.log`：7脚本73/73、1428断言、34.999秒、退出0。

```powershell
$env:APPDATA=Join-Path (Get-Location) '.godot/recovery-final-sandbox'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 --log-file .godot/recovery-final.log -s addons/gut/gut_cmdln.gd '-gtest=res://tests/rules/test_checkpoint_recovery.gd,res://tests/rules/test_checkpoint_store.gd,res://tests/rules/test_run_checkpoint_codec.gd,res://tests/rules/test_checkpoint_job.gd,res://tests/integration/test_desktop_checkpoint_flow.gd,res://tests/integration/test_localization.gd,res://tests/integration/test_hud_status_flow.gd' -gexit *> .godot/recovery-final-output.log
```

首次RED、header RED、终局RED与新局等待竞争失败原始日志以`.log.gz`保留；首次GREEN25/25与中间61/61也保留。终局RED中的已释放测试对象错误与新局等待错误已经修正，不归因生产规则。

## 六进程

工具`tools/checkpoint_benchmark/checkpoint_recovery_process.gd`，APPDATA `.godot/recovery-process-sandbox`，每次执行独立Godot进程。命令共同前缀：`--headless --path . -s tools/checkpoint_benchmark/checkpoint_recovery_process.gd --`，后缀依次为：

1. `prepare_pending user://checkpoint-recovery-process/pending`
2. `inspect_pending user://checkpoint-recovery-process/pending`
3. `retry_pending user://checkpoint-recovery-process/pending`
4. `prepare_bad_pair user://checkpoint-recovery-process/bad-pair`
5. `recover_bad_pair user://checkpoint-recovery-process/bad-pair`
6. `reopen_repaired user://checkpoint-recovery-process/bad-pair`

每个`checkpoint-process-<mode>.json`保存PID与逐项结果，对应`-output.log`保留进程输出（每个退出0）。两组目录仅本探针使用，不触碰作者存档。工具的expectation文件只记录测试预期，不是产品存储协议。普通退出不能代替强杀/断电/Web刷新。

## 审查

`/root/review_status`独立只读code-reviewer：最终APPROVE，已补齐其提出的已知初始状态/随机流坏回备缺口；未知协议/配置/预算仍拒绝。终局失败重试、pending新局确认、待继续挑战退出、跨进程工具均审查。相关源码≤500行，diff check通过。未修改或运行引擎，不外推完整SV/发行。
