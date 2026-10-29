# #87 有界分析证据

受测代码25297aa0e8ed1acb2e69729e6abc1509518e8010，基线为#211合并提交7d78fd8。后续只有说明/证据更新。Windows Godot 4.7.2.stable.official.ed1daf0bf，headless/Dummy/fixed-fps60，隔离APPDATA。

regression.log：3脚本28/28、622断言、退出0，含实际CLI退出0/1/2、跨父奖励/前缀/重复/冲突、v1/v2覆盖、预算与IO拒绝、Windows身份及精确UTF-8阈值。根证书环境错误和test_write_failure负例警告保留，无SCRIPT ERROR或失败测试。独立只读审查所发现的大小写分片覆盖和预算漏项已修复并复审APPROVE。

bounded-cli.log与input-manifest.json：读取#211既存3份v46/v2自然局埋点，原始共3664699字节，导出3分片、1057事件、7次奖励，退出0。equivalence.log证明runs/events/groups/opportunities/errors与旧两参数模式的真实读取结果结构相等。bounded-summary.json保留完整汇总和预算计量；内部3592ms、进程墙钟8392ms，仅为本机小样。全局精简事实14条43426字节、账本5155字节不代表RSS；完整事件在各分片七表。

原始输入绝对路径/SHA256在清单中，未改写。运行输出与未规范化原日志在独立树`.godot/o1-bounded/`，本目录日志副本只去掉行末空格。validation.json记录源文件哈希及精确提交/时间/范围。原450样本在已检查登记位置未找到，较宽扫描遇访问限制后停止；没有450自然局重跑、原故障复现或整条#87验收结论。

该模式的预算是输入和紧凑序列化保留账本上限，60秒为协作式期限；不是RSS硬上限或OS强杀。根目录不是原扁平七表导入目录。详细命令、处理范围及剩余出口见docs/quality/issue87_bounded_analysis.md及工具README。后续PR留作者review。

创建PR前纳入最新849d4d8（#137/Web），组合受测提交3d69183139b36e57c362cb0b672078daa1cd9dda：本批4个GDScript与25297aa逐字一致，补2脚本15/15、515断言、退出0；实际3文件CLI再次退出0，五项汇总仍与原模式完全相等。combined-regression.log、combined-cli.log和combined-equivalence.log保留结果。没有将原28项成绩标为组合树新28项全量。
