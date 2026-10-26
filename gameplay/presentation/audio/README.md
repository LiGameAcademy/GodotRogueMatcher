# 坚果音效接入 · 2026-10-26

当前GameFeedback通过插件AudioManager的SFX池播放本目录十二个CC0 WAV。来源/哈希/处理链在manifest.json，原料在Godot忽略的sources/，许可在LICENSE.md、NOTICE.md、licenses/。音效资产与项目代码分开许可。旧select/match/blast/reward/finish.tres保留为历史原型，当前配置不再引用。

nut_audio.tres是声音路径、消除变体、四档音高、70ms同类去重、最大六声音效和0.65播放增益的权威配置。音效不调用规则，不加入演出完成屏障；快速/低特效不改变声音时长和播放增益。消除两变体按表现计数交替，不消耗规则随机流；按已经冻结的MatchResult.generation取[1,1.03,1.06,1.09]并封顶，不无限升高。

事件映射：select=真实选中；land=移动表现完成；spawn=每个非空补棋批次一次；reject=权威行动明确拒绝；match=非能力消除；blast=explosion；sweep=line_clear（横竖共用）；reward=技能候选整组打开；acquire=实际选卡提交后；confirm=暂停/设置/技能池入口；finish=失败结束，challenge_completed不播放失败声。染色专属声、阶段达成和胜利声不在本次交付内。

奖励/获得/按钮/失败可在弹窗暂停时播放，其余棋盘音效随暂停。finished和cancel均恢复借用播放器的process_mode和pitch_scale；重试只停止本适配器持有的音效。旧合成原型不再作为当前播放源。音量滑杆仍控制Master，并未新增两套音量UI。

音乐由独立GameMusic场景持有，默认读取课程私有仓库中、公开子模块之外的../local_audio/gameplay.mp3，缺失时无音乐运行；本次没有复制音乐C。课程仓库忽略*.mp3，公开导出仍排除项目内local_audio/*。接入说明见../../../local_audio/README.md。版权署名UI和循环接缝须在含音乐发布前完成。

这是首次实机接入，技术回归不替代听感验收；在Godot编辑器中检查正常/快速演出、暂停、重试和高密度连携的音量与重复疲劳。
