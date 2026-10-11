# 离线参考目标与局内冻结（#19）

本工具只生成供 review 的报告和 `.tres`，不修改运行中的局或工程的目标资源。当前八阶段新增目标仍为 100/150/200/300/400/550/750/1000，升压间隔仍全部为4。目标不足继续升压，R不是死亡期限。

先用已有 Reader 读取 #18 留存的正常池 JSONL，再生成曲线；无需重新跑机器人、导出 Web 或更新 Excel。Python 3.11+，只用标准库。

```powershell
& '<Godot控制台>' --headless --path . --log-file .godot/reference-reader.log `
  -s tools/telemetry_analysis/analysis_cli.gd -- `
  '<批次目录>/telemetry' '.godot/reference/reader'

python tools/telemetry_analysis/target_curve.py '.godot/reference/reader' `
  --profile tools/telemetry_analysis/reference_profiles/greedy_normal_v1.json `
  --replay-report '<批次目录>/pressure_summary.json' `
  --output '.godot/reference/candidate-01'
```

示例 profile 只选择 #18 的历史贪心探索数据（d4c77d9、v15），不是通用配置。新数据必须另建版本化 profile，填写其规则/内容/目标配置/抽选/压力/采集/策略/构建指纹、完整机器人参数与已知提交；不得只换策略名称后混组。`pressure_summary.json` 来自 PR #56：匹配组必须无记录/回放/采集错误，run_id 必须出现在其已验证正常终局、退出或工具截尾清单里。Godot 与 Python 的浮点 JSON 格式不同，报告机器人参数按规范化值比较，事件仍严格匹配原 Godot 指纹。

输出为 `target_curve.json`、`stage_config_candidate.tres`，输出目录必须新建且不能位于运行素材或 Reader 输入目录内。报告保存输入文件/配置/回放报告指纹、各阶段样本数与独立种子数、实际构筑暴露、完整行动产分与空间漂移、达标行动P50/P90和各结束分母。数据指纹绑定 Reader 文件字节、所选事件ID与分组；相同种子不同run_id不会增加独立样本数。

只接受 schema 2、source=bot、initialization=normal、collection_context=bot_batch、stage_challenge，无实验分叉的正常池记录；fixture、真人、另一规则/策略/配置、异常和未回放的局不能充作参考。完整行动含零分；只有对应根行动的 match/explosion/chain_reward/marked_reward 进入μ，选卡即时分和目标完成奖励独立，不重复加入。空间使用真实出生−独占离场，不把清理、额外选卡解释成固定得分倍率。

`T_s = ceil_to_h(R_eff(s) × μ_ref(s) × D)`。计算以整数总分/行动数的精确分数进行，避免浮点误差把刚好整5分的目标多取整一次。R原分段1–3=3、4–10=5、11+=10；平滑候选为4=4、11=7、12=9。D=1、h=5、平滑和每阶段30种子/100完整行动门槛都是试调政策。运行导出最多8阶段，11+只有纯模型边界测试。

任一阶段缺覆盖，就整条回退旧表，不拼接已测前期与猜测后期。真实μ=0保留为0并标明不能生成正目标，未知μ保持null；两者都会保留固定运行表。缺样本是成功产出的诊断结论，不是工具错误。格式/指纹/参数/IO错误退出2，不产出可用曲线。候选通过门槛也只代表可供 review；旧目标下的达标分布不是新曲线模拟，更不是玩家期望行动数，启用前还需完整正常局对照。不能自动复制到运行资源。

`StageState` 在建局时深复制 `StageConfig`，冻结全部阶段T、升压配置及曲线来源。Header的challenge包含曲线版本、参考profile、数据指纹、采样规则版本、来源策略与全部目标，并进入配置哈希。实际分数、carry、压力和选卡不写目标。v16改变记录契约，v15命令记录由其原版本重算；当前版本明确拒绝跨规则重算，旧 telemetry 仍能按 Reader 分组分析、旧结果仍能观看。重试沿用冻结配置，新建局才读取新配置。

本次留存证据：`evidence/issue19-results.json`。100局历史贪心样本的第5阶段只有11个种子，第6–8阶段无样本，因此导出固定回退表；没有宣称完成平衡，也没有更新作者工作簿。600分附近卡点仍待继续观察。
