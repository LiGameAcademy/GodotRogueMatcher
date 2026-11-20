# 桌面续局证据索引

结论与限制见 `../../quality/issue160_desktop_continue.md`。受测基线 `448cbc98211e7a737caa7d8cc0b8b6c453bc24a2`，全部变更源码逐文件 SHA256 见 `tested-source-sha256.json`；提交前只追加文档与拷贝日志，生产源码未再改动。Godot4.7.2 ed1daf0bf / GUT9.6 / Windows；隔离 APPDATA。

## 最终相关回归

`desktop-verified-output.log`：13脚本109/109、2715断言、48.503秒、退出0，无SCRIPT ERROR/Parse Error/ObjectDB/resources still in use。verbose保留未认领StringName输出及系统根证书等诊断。

```powershell
$env:APPDATA=Join-Path (Get-Location) '.godot/desktop-verified-sandbox'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --verbose --path . --fixed-fps 60 --log-file .godot/desktop-verified.log -s addons/gut/gut_cmdln.gd '-gtest=res://tests/rules/test_run_checkpoint_codec.gd,res://tests/rules/test_checkpoint_store.gd,res://tests/rules/test_commands_replay.gd,res://tests/rules/test_run_random_streams.gd,res://tests/rules/test_shape_unlock_replay.gd,res://tests/rules/test_checkpoint_job.gd,res://tests/integration/test_desktop_checkpoint_flow.gd,res://tests/integration/test_release_flow.gd,res://tests/integration/test_reward_coordination.gd,res://tests/integration/test_reward_presentation.gd,res://tests/integration/test_input_buffer.gd,res://tests/integration/test_localization.gd,res://tests/integration/test_hud_status_flow.gd' -gexit *> .godot/desktop-verified-output.log
```

`desktop-final-combination-output.log`为较早109/109、2711断言/40.793秒及2对象1资源保留；`desktop-legacy-leak-output.log`为相关旧6脚本38/38、827断言/20.464秒，命名保留为生成音效WAV/Playback；`desktop-leak-isolation-output.log`为新增2脚本11/11、134断言，未见此资源保留。后两份均verbose。不能据此声称已修复资源缺陷或基线版本已获验证。

`desktop-flow-first-output.log.gz`保留初次冻结候选等待不足失败；`desktop-related-output.log.gz`保留新局初始化等待竞争失败。两份原始失败日志含终端尾空格，以gzip原样保留。修正用例等待后最终通过，没有改计分/目标绕过。manifest的SHA256对应受测工作区原始字节，git_blob对应Git按仓库LF规范化后的同一受测文本；已逐项核对index与受测文件的Git对象相等。

## 性能

- `checkpoint-benchmark-output.log`：原默认2秒接受门槛的真实正常局失败/成本；不是桌面性能通过。
- `checkpoint-benchmark-desktop-v2-output.log`：四个正常mode/seed自然终局长度及worker数据。
- `checkpoint-benchmark-desktop-long-before-cache.{json,log}`：无私有增量缓存的95行动冻结成本。
- `checkpoint-benchmark-cache-long-output.log`与`checkpoint-benchmark-desktop-long.json`：当前增量缓存正常局，逐点0/25/50/75/90/95行动、自然终局97行动；约10.38MB、95点冻结8.656ms、保存8.792秒、重建5.672秒。全安全点冻结最大25.041ms。
- `checkpoint-profile-baseline.json`与`checkpoint-profile-baseline-output.log`：早期无缓存读/解析/前缀等分项，不是当前缓存最终性能。

可复现工具`tools/checkpoint_benchmark/checkpoint_benchmark.gd`：隔离APPDATA，`--headless --path . -s tools/checkpoint_benchmark/checkpoint_benchmark.gd -- --desktop --budget-us=10000000 --long-only`。未指定long-only时运行四个mode/seed；需预算足够，每样本自然结束或90秒上限，不保证达到200行动。所有保存均测试私有路径。

## GPU

`desktop-gpu-probe.log`、`desktop-gpu-report.json`与四张PNG：正式GPU实际场景、viewport控件输入，取消、join、重新读取95行动887records、完整快照相同、旧局退役与正常退出。`gpu-probe-stderr.log`保留stderr（为空也保留）。启动使用隔离`.godot/gpu-probe-sandbox`，只拷贝先前正常benchmark的primary/previous到该私有`user://run_checkpoint`，GUI Compatibility 1280×720，运行`-s tools/checkpoint_benchmark/desktop_gpu_probe.gd`并自行退出。

首次任务207.039ms最大帧间隔包含同步截图，不可归因；第二次6.717秒/405帧最大17.333ms，不包含中途截图。`desktop-gpu.log`是先前独立窗口的62/89ms观察，保留而不计作无人黑盒/作者反馈。freeze字段为当时最新冻结值，可能来自排队快照，不做job因果归属。

## 独立审查

`/root/review_status` code-reviewer最终增量只读复审：**APPROVE**。复核busy反馈、GPU探针、取消后worker/Store串行、私有只读历史缓存及当前manifest；原HIGH（取消释放worker导致竞争）修正仍有效。相关源码≤500行，diff check通过。审查未修改文件或运行引擎。明确保留freeze字段诊断限制、音效资源保留范围，不替代完整SV/Web/发行验收。

未测：完整跨进程关闭/写中强杀、Web刷新与无Thread路径、正式恢复session/高水位、跨重启失效失败意图、规则级损坏自动回备。#160/O5保持未完成。
