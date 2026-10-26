# #129 十字与扫线收益实机证据

2026-10-25，Godot4.7.2 Compatibility / NVIDIA RTX2070。真实Game捕获，无裁切/合成/重绘。before_zh_CN_1280.png为相同正式前置、同两张候选尚未登记图标时的画面；对应after为cross_sweep_zh_CN_1280_0_normal.png。

- targeted.log：12/12测试、2184断言，32项映射与Cross/Harvest/Manual真实等级/额度和显示只读。
- integration.log：56脚本328/328测试、10500断言、169.228秒，退出0。保留29条既有Float/Int警告和38个退出StringName诊断，本轮无WAV资源保留报告，不宣称历史根因解决。
- capture.log：中英×明暗×两尺寸×普通/低特效×候选/构筑32组合rule_error为空，工具栏fits=true，无GLES/Shader错误。5张当前代表图及1张接入前图保存在此，全量留.godot/issue129-cross-sweep-icons/captures。
- before.log、import.log：同候选修改前捕获成功，导入解析无脚本错误。
- asset-manifest.json：既有64×64双轴SVG原始来源、工作副本/Git源哈希，CRLF/LF规范化后与起点一致，生产素材未修改。

复用图元不表示三张卡同功能：Cross为十字能力、Harvest为扫线直接收益、Manual为有限主动权限。真实构筑中只有Manual显示剩3次，其他显示等级。源文件名保留，代码常量改中性DUAL_SWEEP，不新增重复贴图。

作者本片辨识/审美未观察，不据截图或自动回归代填。独立Project状态更新记录见docs/quality/project_status_sync_20261025.md，未把其他Project条目正文复制到PR。
