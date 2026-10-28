# #130 接触阴影同盘对比

入口：`res://tools/contact_shadow_preview/contact_shadow_preview.tscn`。真实Game，固定五种坚果盘面，关闭偏好写入、遥测、记录与背景流动；非平衡样本。S键仅在本夹具中切换接触阴影开/关，不改运行配置或真实规则。主题/低特效切换后可再次按S刷新当前对比状态。

1. 按S同盘比较：是否更容易区分身体与棋盘，阴影是否克制、未投出眼嘴或PNG矩形。
2. F1切换明暗主题，分别比较深核桃、开心果开口、边角与相邻棋子。棋子颜色、表情、标记与UI应保持原样。
3. 分别尝试普通/快速/低特效/组合及暂停/恢复。静态阴影仍在，不脉冲、不加入演出等待。
4. 选择/移动/消除、重试，检查旧阴影清理；再用F6固定能力盘核对描边、方向与身体未混淆。

阴影复用现有BoardAppearance参数，未新增Light2D、WorldEnvironment或全屏效果。Windows启动使用短临时APPDATA/LOCALAPPDATA。`-- --capture-shadow` 保存两主题×低特效开关×阴影开关共8张真实渲染截图并校验规则摘要，输出本地`.godot/issue130-contact-shadow/captures/`；不代表真人审美或性能验收通过。
