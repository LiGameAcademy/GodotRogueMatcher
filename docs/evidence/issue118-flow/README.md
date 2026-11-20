# #118 移动、出生与批量改色接入证据

2026-10-21，代码 5f37e67b3acc78ced03bf5c9485ef033ba78452f，基于 #169→#170 依序合并后的 3e4cc2b。Godot 4.7.2、Compatibility、GUT 9.6.0；APPDATA/LOCALAPPDATA 隔离于 .godot/issue118-flow，完整集固定 60fps，场景回归使用正常字体驱动。

- full-output.log：89 脚本、657/657、23078 断言、198.788 秒，退出 0；无 SCRIPT ERROR/Parse Error 或 ObjectDB/Resource 泄漏提示。
- development-6.log：最终 12 项新增流程测试、96 断言，退出 0。development-1～5 为实际开发历史：数组夹具类型错误、自定义测试卡被正式目录校验拒绝、未配置正式染色卡前置；修正夹具后通过。不把这些测试准备失败伪装成规则 RED，也未删除或降低正式目录/前置门槛。
- golden-replay.log：#136 合并树的 415 条 v41 记录独立精确回放，退出 0。
- prototype-record.jsonl / prototype-probe.log：沿 fixture_dye 三次真实移动完成 L，30 条记录落盘重读精确回放成功，含 1 个模板匹配事件。此为固定原型规则样本，不能作为平衡或真人试玩结论。
- import.log：编辑器解析/导入检查，退出 0；为新测试生成 UID。
- script-results.json、line-counts.json、summary.json：逐脚本结果、321 个自有 gd 文件物理行数（最高 474）及统计；manifest.json 保存 SHA256。

完整集入口 addons/gut/gut_cmdln.gd，递归 tests；专项入口 tests/rules/test_shape_flow_integration.gd。独立回放入口 tools/bot_testing/batch_cli.gd 的 replay 模式。记录不包含异形正式解锁状态；范围与后续门槛见 ../../quality/issue118_shape_flow_integration.md。
