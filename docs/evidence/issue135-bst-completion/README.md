# #135 B/S/T 补齐证据（2026-10-21）

代码实现 827b06d，包含父片 B/T 0a38a96、同步 6f9c187 和固定目标门禁修复 14885fa。规则 run-commands-v41-followup-strength，Godot4.7.2 / Compatibility / GUT9.6.0；进程 APPDATA/LOCALAPPDATA 隔离在 .godot 下。

本次补齐已有规则入口上的 B/S/T 契约，逐项映射见 ../../quality/issue135_composite_boundaries.md。没有新增正式卡、异形模板或存档服务；直线夹具验证时序，不冒充L解锁用例。pending快照只读；重复恢复验证的是完整命令安全前缀重算，不是中间叶快照接管。

审查先后修复：嵌套空门禁、固定过滤后全根空门禁、支付材料遗留染色标记、固定染色单色盘误拒绝、普通爆破故障后继续染色、局部队列和桥接未中断。审查修复后22/22测试、178断言，0.322秒（review-target.log）；最终复审无高置信度未解决问题。后续全量日志另列。

失败历史均保留：red-followup.log为实现前染色三项失败；first-s-target.log含空结果的Typed Array错误和非安全阶段误用restore_prefix；first-review-target.log的最后一项读取了错误trace字段，改用interruption_reason后通过。失败日志不能当成通过证据。

机器人 seed133000/greedy：714分、44行动、3次选卡；v41落盘独立回放415条成功。旧v39记录拒绝，checked_records=0、record_version_mismatch，退出1是预期结果。机器人代码版本827b06d。

复现：先 --headless --editor --path . --quit 导入，再以 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit --fixed-fps 60 跑GUT。独立回放：-s tools/bot_testing/batch_cli.gd -- replay res://docs/evidence/issue135-bst-completion/bot-record.jsonl。

机器日志保留原字节；manifest保存大小/SHA256，line-counts验证修改自有代码≤500行。未执行编辑器人工试玩或Web导出。PR #167/#168保持作者review，不自动合并，#135保持open。

最终全量：86 脚本、632/632 测试、22839 断言、327.115 秒、退出 0。无 SCRIPT ERROR/Parse Error，逐脚本统计与总数一致；退出提示以原日志为准。
