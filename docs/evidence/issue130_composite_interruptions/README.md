# #130 Composite标记边界中断实机记录

2026-10-28，基于#206合并ecb0df8，feature/130-composite-interruptions。Godot4.7.2/GUT9.6、Compatibility/OpenGL3.3、NVIDIA RTX2070、1280×720桌面DEBUG。无headless、无fixed-fps；同时有headless回归，非性能统计。固定seed145、配方/规则与#206一致，本片不改生产脚本、场景、素材、配置或参数。

入口：Godot `-s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_composite_interruptions.gd -gexit`。每个中断样本先运行同模式正常播放取得摘要，再重载同初态执行中断；8个中断样本＋8次基线，单进程顺序运行，每格N=1。GUT共2/2、226断言通过（含4个写盘断言），stderr为空。

pause：在正式fuses_visualized边界经Game暂停，等待30个process frame，验证hold Tween elapsed不变、当前仍为MARK、无后代派发、输入仍锁及规则摘要不变；暂停期Game略过请求被拒，再经Game恢复。30帧在headless fixed60约0.5秒，实机不把帧数换算成固定秒数，冻结证据以Tween进度不变为准。

skip：在同一必需MARK经Game请求略过，当前MARK仍保留，不提前开放输入；其后两代爆破走step_skip_requested而非match_visualized。因此events只有dye/match两笔是正确政策，不将正常播放工具的“四笔事件”校验套用到略过样本。最终HUD精确60、消费一次、无待奖、实际规则和存活视图对应、导演/视图空闲。

| 注入 | 模式 | 正常视觉事件 | 略过后代 | 命令到恢复输入ms |
| --- | --- | ---: | ---: | ---: |
| pause | 普通 | 4 | 0 | 2086.0 |
| pause | 普通＋低特效 | 4 | 0 | 1695.5 |
| pause | 快速 | 4 | 0 | 1359.2 |
| pause | 快速＋低特效 | 4 | 0 | 1075.0 |
| skip | 普通 | 2 | 2 | 544.9 |
| skip | 普通＋低特效 | 2 | 2 | 419.2 |
| skip | 快速 | 2 | 2 | 284.3 |
| skip | 快速＋低特效 | 2 | 2 | 191.4 |

8样本与对应正常播放baseline_digest完全一致，盘面/账本/事件/RNG及奖励身份均包含在摘要。暂停恢复正常派发两代；略过只派发两代爆破的skip，不重发标记或规则。

墙钟包含暂停观测与既有演出/HUD过程，不等于纯动画、首像素、音频延迟或帧时间，不是均值/分位数/正式预算。author_readable/author_wait_acceptable/author_audio_clear均null，自动实机通过不等于真人体验。

本片只验证Composite的MARK边界暂停/略过；其它叶/来源/命中/收束点、长链/异形中断、全部重试矩阵、实际成本未由这8样本覆盖，#130/O4仍未收口。
