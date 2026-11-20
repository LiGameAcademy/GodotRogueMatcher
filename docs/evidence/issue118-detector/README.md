# #118 直线与 L 检测首片证据

2026-10-21，代码 efe7e64802b3d55acd5875ee44e40e57d653f540，基于 ea111675 合并树。Godot 4.7.2、Compatibility、GUT 9.6.0。完整运行固定 60fps，APPDATA/LOCALAPPDATA 隔离在 .godot/issue118，未使用 Dummy 字体驱动运行场景回归。

full-output.log：88 脚本、645/645、22982 断言、220.111 秒，退出 0，无 SCRIPT ERROR/Parse Error。script-results.json 为逐脚本统计，line-counts.json 检查所有自有 gameplay/ui/services/tools/tests 的 gd 文件不超过 500 行。

config-red.log 保留审查发现重复必要格/null 模板问题后的真实失败：10 项中 9 项通过、1 项失败，退出 1。修复后 config-green.log 为 10/10、69 断言、退出 0；错误模板的预期 push_error 由 GUT 消费。RED 日志中的异常不代表修复后状态。

golden-replay.log：现有 docs/evidence/issue135-bst-completion/bot-record.jsonl 的 415 条 v41 记录独立精确回放成功、退出 0。正式路径仍只启用直线，不宣称 L 原型已具备解锁或记录协议。

执行入口为 addons/gut/gut_cmdln.gd（tests 递归完整集）及 tools/bot_testing/batch_cli.gd 的 replay 模式。manifest.json 保存原始证据 SHA256。边界及下一片见 ../../quality/issue118_line_l_detector.md。
