# #129 爆破收益图标证据

2026-10-25，Godot4.7.2 Compatibility / Windows / RTX2070，真实Game场景、固定种子129的人工奖励。先用正式核心/引信技能满足资格，不代表自然掉落概率。

保留4张代表候选/构筑图及1张小视口工具栏图。16组合（中英×明暗×两尺寸×候选/构筑）及工具栏可由 tools/mechanic_icon_preview 的 --capture-icons 重建。构筑为真实爆破收益Lv.2/3/1，含原有核心、五连补分加号和色彩聚焦回退。

代表图已核对世代/阈值正文、确认区、角色/等级、爆破图元与五连加号区分及未触发留白时无临时次数。工具栏可见且尺寸检查true；读卡前H收起面板。真人辨识速度和美学待作者。

icons.log：8/8、1455断言。integration.log：56脚本323/323、9756断言、137.416秒、退出0，保留29条既有Float/Int比较警告。

集成退出报告4对象/2资源保留，verbose明确为2 AudioStreamWAV、2 AudioStreamPlaybackWAV和match.tres/reward.tres，与前期#187质量记录的类型/资源一致；本片未改音频、不声称根因解决。测试通过不等于全环境退出无诊断。

capture.log：16次导出rule_error为空，加1张工具栏，未报告GLES初始化错误；import.log：导入/脚本扫描。仅去日志终端颜色和行尾空白，退出诊断原样保留。

asset-manifest.json：复用PNG的源说明/尺寸/哈希，与基线字节一致，无新增或改动生产图像。
