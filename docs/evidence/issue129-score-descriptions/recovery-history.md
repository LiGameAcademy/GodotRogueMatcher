# O4四张计分描述批：恢复边界

2026-10-29，基线a9e5ebb8cfbc0b4a3c0af654d19363f60528c393。

原work/o4-score-rule-descriptions及第二次work/o4-score-active曾成功创建，但随后.git登记、分支或大部分文件消失，Git根查询落入课程总仓库。此对话未执行删除/清理，也未在落入外层仓库后提交。原因待协调定位，不推测责任。

首次开发树曾输出5脚本46/46、1121断言，日志随后随目录消失；该成绩不能作为恢复树的验收证据。界面检查曾因addons/gut/gut_cmdln.gd已消失而无法启动，不能记通过。

现已将四份生产/覆盖源码、两个专项测试及恢复diff备份至课程工作区o4_score_recovery；新游戏worktree位于非work路径o4_score_active，分支feature/129-score-description-recovery。开始恢复前持续核对实际git根及HEAD；恢复源码提交后重新执行本批相关回归、双语GUI和最终身份复审。

静态恢复补丁独立复审通过，不等同于运行验收或作者读感确认。#129为部分交付，保持OPEN，真人观察仍为空。
