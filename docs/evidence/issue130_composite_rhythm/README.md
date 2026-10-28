# #130 Composite连携实机记录

2026-10-28，Godot4.7.2、Compatibility/OpenGL3.3、NVIDIA RTX2070，1280×720桌面DEBUG；feature/130-composite-rhythm，基于#205合并92d4d27。采集时使用本片实现。无headless/无fixed-fps，另有headless回归并行运行，不作为性能统计。

入口tools/chain_rhythm_acceptance/chain_rhythm_acceptance.tscn，参数`-- --capture-rhythm`。前四例seed128，Composite seed145；固定种子经挑选确保能观察指定链，不是自然抽选/平衡样本。配方使用正式DyeMaterialEffect和AssignFuseEffect、嵌套Composite；内部RecipeRun仅覆盖本工具目录，沿正式Generator/prepare/revalidate/ChooseSkillCommand/PopupSkillChoice执行，没有塞冻结目标或冒用正式技能ID。

20/20技术有效，五例各四模式摘要相同，stderr为空；每格N=1。Composite四例均0分改色事件→50分五连→引信标记→5分爆破→5分爆破=60。引信新标记在改色和匹配时均不可见，MARK时两目标[6,8]实际可见，(3,2)先爆破后(3,3)继续；结尾输入恢复、奖励恰消费一次，声音cue记录两次blast。

| 模式 | 匹配派发ms | 标记可见派发ms | 爆破1派发ms | 爆破2派发ms | 命令到恢复输入ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 普通 | 15.2 | 130.4 | 447.0 | 830.7 | 1514.5 |
| 普通＋低特效 | 10.4 | 98.5 | 399.7 | 782.6 | 1182.7 |
| 快速 | 18.4 | 104.8 | 271.9 | 471.8 | 838.4 |
| 快速＋低特效 | 10.2 | 16.6 | 151.4 | 351.0 | 567.5 |

标记短保留复用PresentationConfig.spawn_duration当前0.3秒，随快速压缩到0.15秒；低特效保留必要标记。是现有参数在新必要步骤的用途，不是本轮确认的全局等待预算。其它生产节奏/音效/强度未调。

JSON包含实际CommandAttempt accepted、SkillAcquired标记/消费及RuleResult：completed_leaves=[0.0,1]、两代已提交来源/强度/归因；规则在命令中同步完成，表现回调只记录。事件at_ms为派发墙钟，不是规则提交之间的等待；从这些数值不能推断规则等动画才运行。wall_elapsed_ms从选卡确认命令到安全点，不包含选卡思考、首像素或声卡延迟，不是GPU帧时间、均值/分位数或正式门槛。

author_source_readable/author_wait_acceptable/author_audio_clear均null。#205作者试玩通过不代替本片体验；本轮无真人读盘/听感或录像结论。头四案例复测亦保持真人字段空，历史通过在此前PR记录保留。

本片还有标记边界四模式切局自动回归，不等于全部叶边界、暂停/略过/重试全矩阵。更复杂叶组合/异形混合、成本与完整FJ05/FI仍待后续，不关闭#130/O4。
