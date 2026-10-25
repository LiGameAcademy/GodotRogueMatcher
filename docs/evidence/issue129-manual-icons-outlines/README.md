# #129 主动图标与轮廓实机证据

Godot4.7.2 Compatibility / NVIDIA RTX2070，2026-10-25。原始捕获来自真实Game，未合成、裁切或重绘。before为相同工具夹具、旧shader、图标未登记的低特效盘面；对应after为manual_build同语言/尺寸/主题的low图，比较棋盘轮廓。五种普通坚果在第4行，对照的引信坚果在第5行，核心/行扫/列扫由正式技能放入。连续轮廓是核心，分段轮廓是引信。

- capture-final.log：32个组合，各rule_error为空，工具栏在1024×640内；保存6张当前代表图，全部原图留工程.godot/issue129-manual-icons-outlines/captures。
- before-capture.log：修改前16组合及工具栏，保留2张同盘面比较图；其余修改前原图留.godot/issue129-manual-icons-outlines/before。
- targeted.log：4脚本22/22测试、1779断言。
- integration.log：56脚本325/325测试、9929断言、141.363秒，退出0。29条既有Float/Int比较警告；本轮未报告WAV/播放对象资源保留，仍有38个退出StringName诊断，不宣称历史音频根因已解决。
- import-final.log：最终导入解析检查。新增SVG首次导入前曾有依赖预加载错误，导入完成后复验无解析错误，实际运行与测试通过。
- asset-manifest.json：现有爆破PNG、新原创双轴SVG及修改后shader源的字节与SHA256。

本轮捕获没有GLES初始化错误。PNG证明已实际运行，不等于作者真人认可新分段轮廓或图标辨识效率；作者体验数据保持未观察。试玩入口和H收起工具说明见tools/mechanic_icon_preview/README.md。
