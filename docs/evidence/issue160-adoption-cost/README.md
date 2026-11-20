# 接管分项证据

基线0442d86；结论见`../../quality/issue160_adoption_cost.md`。`tested-source-sha256.json`记录修改后受测源与规范化Git blob。修改前生产源码就是基线，计时wrapper调用相同super；修改后仅Game两处去重与Flow只读getter。

- `before.json`/`before.log`：GPU PID43400，95行动887records，主接管234.497ms、完整窗口最大339.651ms。
- `after.json`/`after.log`/`restored.png`：GPU PID44600，完全相同原存档另一个APPDATA，主接管147.515ms、完整窗口最大205.537ms、snapshot相等、旧局退役、正常保存退出。变差分项见原JSON。
- `regression.log`：3脚本19/19、261断言、23.368秒，退出0。命令为Godot headless/GUT，`-gtest=res://tests/integration/test_resume_collection_flow.gd,res://tests/integration/test_desktop_checkpoint_flow.gd,res://tests/integration/test_game_themes.gd -gexit`，APPDATA `.godot/adoption-optimization-sandbox`。
- `headless-initial.log`/`headless-initial.json`保留工具误用headless导致菜单超时；正式GPU模式通过。更新后工具遇headless直接报告gpu_required，不把未跑写成通过。

复现GPU：在独立APPDATA的`Godot/app_userdata/技能连珠/run_checkpoint/`放入正常benchmark95点的primary/previous，使用GUI Godot `--path <工程> --resolution 1280x720 --max-fps 60 -s tools/checkpoint_benchmark/checkpoint_adoption_profile.gd`。工具动态注入`profiles/`中的4个只计时wrapper，使用实际super方法；按恢复菜单信号启动，自动保存退出。源码数据不是生产绑定。所有截图在计时结果冻结后读回。

独立审查最终APPROVE，未改文件/未运行引擎；不代替19项和GPU实际证据。没有硬帧预算、任意长局、真人、强杀或Web通过声明。
