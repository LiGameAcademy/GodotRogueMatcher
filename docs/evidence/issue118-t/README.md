# #118 T 模板验收证据

2026-10-21。基础合并提交 `3c4c414326f53aa1a085b692f8f854cf92122afd`（PR #172），受测代码提交 `b910374ab5374e9f0fe6df84cf31e2670e83a01d`。

Godot 4.7.2 / Compatibility，GUT 9.6.0，固定 60 FPS，无界面运行，进程级独立 APPDATA/LOCALAPPDATA。完整回归 97 脚本、708/708、23612 断言、190.371 秒，进程退出 0；未出现脚本解析错误、资源或对象泄漏。新增专项 21/21、220 断言。

- `full-output.log`：完整回归；`script-results.json`：逐脚本统计；`summary.json`：汇总。
- `target-green.log`：最终专项；`import.log`：编辑器导入检查。
- `target1.log`：首轮夹具数组类型错误，不作为规则行为 RED；`target2.log`：混合身份排序失败；`target3.log`：中间修复结果。
- `target-final.log`、`leak.log`：专项断言通过但退出仍有音频实例；最终在场景测试清理时停止播放并等待释放，最终专项与完整回归均无该提示。
- 三份实际 v43 记录分别由独立进程回放：`t-unlock-record.jsonl` 13 条、`order-l-t.jsonl` 17 条、`order-t-l.jsonl` 17 条；对应 replay 日志验证成功。
- `v42-rejection.log`：旧 v42 记录按预期返回 `record_version_mismatch`，引擎退出 1；不是跨版本精确重放成功。
- `line-counts.json`：335 个自有 GDScript，最大 474 行。
- `manifest.json`：原始证据字节数与 SHA256；README 不计入清单。

本片只接入 T 共享模板及显式验收解锁配方，生产技能池不变。复审通过；数量奖励与自动回归不能替代真人体验验收。详见 `../../quality/issue118_t_template.md`。
