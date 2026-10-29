# #211 再次复审与增量修复

复审基点 e9c74e1456497dd8c528158f626c8aa1b8ea7965；修复受测提交 **6fe3d0e07cade51bfb2ae985cc8bbccbea9d7b5d**。原目录中的1005项全量结果仍属于旧版本59e8ef3，不是这次v46源码的全量结果。

发现并修复两项P2：

1. 旧schema只验证上报候选子集的算术，截短三槽为一槽并同步展示集合，或者删掉首槽合法成员再重算分母/采样仍可通过。v2冻结utility_pick事实，按H=1、已选和工具配额重建每槽完整剩余池，精确核对候选、配额排除、槽序和耗尽终止；同时核对未截断权重。没有改抽样算法或试调参数。
2. 旧合法skill_acquired事件可无reward_id，旧聚合将其回退为offer键，无法匹配生成事件的reward键，成功取得被计0且误记未消费。现在先收集offer→reward，再关联缺reward_id的取得；payload为null时允许回退信封reward_id。失败选择仍不计取得，同父奖励不重复统计。恢复来源测试仅为合成事件关联验证，不是#160实际恢复验收。

先加真实负例再修复：旧代码6测4过2失败、7断言失败，退出1（red.log）。修复后冻结提交的20脚本专项 **183/183通过、3525断言、退出0**（regression.log）；覆盖统一池、配额-1/0/1/2及1/2/3张组、非法截短/缺项、记录/回放、六随机流、Composite生命周期、奖励等待、旧版兼容、screening读取与实际报告CLI。Windows Godot 4.7.2.stable.official.ed1daf0bf，headless/Dummy/fixed-fps60，隔离APPDATA。日志包含根证书环境错误与故意写入失败的负例警告，无SCRIPT ERROR或失败测试。独立授权只读审查在两项修复后APPROVE。

规则版本为 **run-commands-v46-unified-offer-audit**，抽选版本为 **offer-unified-trial-v2**，因为冻结记录新增配置事实而递增。实际旧v45命令文件replay返回record_version_mismatch、退出1；原JSONL不改写，原输入清单SHA256复核一致。v1埋点仍按旧基本校验读取，但不具备v2完整池保证。summary.opportunities.pool_audit新增complete_rewards、legacy_rewards、complete_rate；没有生成奖励时比率为null，不从当前配置猜补历史utility事实。

同受测提交重新运行自然greedy-v1种子1000～1002、每局最多60步：3局全部落盘回放成功，奖励3/2/2，共7次；分析3文件、3局、0错误，pool_audit为complete=7/legacy=0。原v1埋点重新分析3文件、3局、0错误，complete=0/legacy=7。得分629/300/250及步数43/34/31与原样本一致，只用于链路与版本验证，不用于参数校准或450局故障复现。

validation.json列明受测身份、源文件与新原始输入SHA256；原始新JSONL在独立工作树`.godot/o1-rereview/batch/{records,telemetry}`保留，本目录归档bot-runs.csv与CLI日志。日志副本仅去行末空格，原输出留在`.godot/o1-rereview/`。本轮所有引擎进程验证结束后退出；PR继续留作者review，不自动合并。
