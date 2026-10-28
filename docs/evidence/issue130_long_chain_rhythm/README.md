# #130 长链与异形连携真实记录

2026-10-28，Godot4.7.2/GUT9.6，Compatibility/OpenGL3.3、NVIDIA RTX2070，1280×720桌面DEBUG。分支feature/130-long-chain-rhythm，基于#204合并cc247f1；采集时使用本片代码。固定seed128，不是平衡抽样。

入口tools/chain_rhythm_acceptance/chain_rhythm_acceptance.tscn，非headless、无fixed-fps，加参数`-- --capture-rhythm`。同一进程顺序运行4案例×4模式，每格单次N=1，不是均值或分位数，且当时另有headless回归运行，不能作为性能对照或预算。

16/16 technical_valid，同例四模式规则摘要一致，stderr空。新八样本每例六段，只有一次基础匹配cue、3次blast与2次sweep；不由cue派发断言声音听感清晰。

| 案例 | 模式 | 命令到安全点墙钟ms | 分数 | blast/sweep派发数 |
| --- | --- | ---: | ---: | ---: |
| long_chain | 普通 | 2951.9 | 77 | 3/2 |
| long_chain | 普通＋低特效 | 2677.8 | 77 | 3/2 |
| long_chain | 快速 | 1516.6 | 77 | 3/2 |
| long_chain | 快速＋低特效 | 1358.1 | 77 | 3/2 |
| shape_chain | 普通 | 2971.3 | 111 | 3/2 |
| shape_chain | 普通＋低特效 | 2668.7 | 111 | 3/2 |
| shape_chain | 快速 | 1538.8 | 111 | 3/2 |
| shape_chain | 快速＋低特效 | 1380.9 | 111 | 3/2 |

long_chain：50→5→6→5→6→5=77，恢复棋盘输入。shape_chain：直线＋L命中共10个模板槽位但共享3实体，并集7枚只结算84→5→6→5→6→5=111，链后进入1次奖励等待且棋盘锁定。最终规则摘要包括待奖与已生成候选，四模式一致。

事件at_ms为match_visualized派发时刻；wall_elapsed_ms从命令到play_case协程返回，前三例是恢复输入，异形例是奖励弹窗安全点，不含选卡思考。不是屏幕首次响应、声卡延迟、纯动画等待、GPU帧时间或正式门槛。

真人来源辨识/等待/声音三字段均null。作者曾确认#204短链试玩通过；本次扩大后的长链/异形没有借用该结论，仍待本片真人试玩。无录屏/逐帧视认或听感结论。

未覆盖Composite改色→标记→延迟后代、更多异形组合、长链暂停/取消/重试/略过全模式矩阵与真实设备帧时间；不据此关闭FJ05、#130或O4。
