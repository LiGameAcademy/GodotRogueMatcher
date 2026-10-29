# O1首批冻结源码验证

受测源码：`8d15bd4860d480a47d03642ca230f9a501a2fa11`；base：`9589563051f845e2c710f9522f4deed76307a265`。后续证据提交只增加本目录和文档链接，不改变受测游戏/工具/测试源码。

- Windows、Godot4.7.2 `ed1daf0bf`、GUT9.6、headless/Dummy、fixed-fps60、隔离APPDATA；138脚本、985/985测试、31,156断言、退出0。测试前后同一HEAD，工作树干净。
- 原始完整stdout/engine日志在本worktree的`.godot/o1-evidence/frozen-*`；本目录保存摘要和原日志SHA256，日志原件不裁改。29条Float/Int比较警告保留。本批不冒充真人、GUI、Web或发行候选接受。
- stderr/engine诊断另外保留：本地系统证书读取错误、非法模板负例日志，以及2条`test_contact_shadow.gd:106 → GUT free_all`的同步信号清理诊断。后者与交接所记历史栈相同，本批未修复，也未据此认定生产崩溃；不把退出0描述为“无诊断”。摘录见[诊断](diagnostics.log)，完整原日志指纹不变。
- 同一提交三局random机器人：三份落盘回放OK、批测实际退出0；telemetry为3局/558事件、0错误、退出0。相同日志复制两份仍1局/186事件；加入坏JSONL保留有效局并退出1。
- 一名只读审查子代理检查代码和后续兼容测试；主种子入口/区间溢出和损坏engine_build类型问题修复后复核APPROVE，最终平台拒绝/唯一目标边界再复核无阻断。该结论是本地审查，不是GitHub批准或远端CI。
- 早期含解析/权限错误、不存在测试路径的启动和中断的旧fixture广回归不计入本目录通过成绩；旧集成成绩也不挪作本提交成绩。最终冻结验证另起目录和进程。

[验证清单](validation.json)包含退出与版本身份；[源码指纹](source-manifest.json)覆盖本批变更的游戏、工具和测试文件；[采集输入指纹](input-manifest.json)覆盖本轮三份新telemetry。[GUT摘要](gut-summary.log)与[批测摘要](batch-summary.log)供review快速核对。

范围与接口见[首批契约](../../quality/o1_first_batch_contract.md)，#87复现事实与未完成出口见[最小复现](../../quality/issue87_minimal_probe.md)。#85完整能力映射/#86统一权重/#88校准/#87大批故障/#160安全存档及Web仍未完成，相关Issue保持开放。
