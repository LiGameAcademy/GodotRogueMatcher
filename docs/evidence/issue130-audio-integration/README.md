# #130 音效整合验证证据

2026-10-26，Godot4.7.2 Compatibility / NVIDIA RTX2070，固定#128真实Game样例。作者原音效提交9657639以58b281a整合，未修改WAV或音乐文件。首次19项证据保留原docs/evidence/nut_audio，不冒充本轮最终树成绩。

- premerge198.log：#198合并前12/12、2184断言。
- targeted.log、pause-targeted.log：新真暂停测试在修复前复现暂停棋盘声被奖励声复用，包含使用独占循环副本排除短音效自然结束时序的复验；原素材不改。
- targeted-final.log：最终3脚本22/22、507断言，包括真暂停、自然结束释放、场景退役和借用模式/音高归还。
- capture-first.log：新工具首轮typed array条件表达式运行错误，修正明确初始化/assign后重跑，失败未隐藏。
- capture-final.log、audio-cases.json：真实渲染的3盘面×四模式12组合，规则错误空、分数50/61/16、各盘面跨模式快照一致，必要cue存在；没有录音，不等于声音均衡/听感通过。
- hash-check.json：清单中12个运行WAV及引用原料共25文件SHA256核对通过；保留作者来源/许可/编辑链。
- line-counts.json：改动相关脚本小于500行。
- project-status.json：gh CLI将#130待开发→开发中，回读验证；未关闭issue。

代表PNG为真实Game运行后截图，无合成或重绘，只证明界面和规则结果；完整12张留.godot/issue130-audio-validation/captures。主作者工作区、音效参数、素材字节和可选本地音乐保持原状；没有复制私有音乐或执行成品导出。

integration-first.log保留首轮3个池模式断言失败及combined等待中止；修正测试起点隔离后，integration-final.log为57脚本337/337、10590断言、349.178s、退出0。29条Float/Int比较警告及verbose退出38个unclaimed StringName诊断保留；等待中止第二轮未复现，根因未独立定位。coordination-targeted.log为18/18、158断言；最终定向22/22、507断言、44.67s。灯光/环境、棋子形变、UI动画及更多听觉层次仍是后续切片，#130/O4不关闭。
