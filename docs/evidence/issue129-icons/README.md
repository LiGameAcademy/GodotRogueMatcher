# #129 机制图标实机证据

Godot 4.7.2 / Compatibility / Windows / RTX2070。固定种子129，实际 Game 场景，真实技能安装及奖励选择入口；人工供给候选，不代表自然掉落概率。

保留6张代表截图；完整24张可通过 tools/mechanic_icon_preview 的 capture-icons 参数再生成。文件名包含场景、语言、窗口宽度、主题索引（0明亮/1深色）。

- arrival：爆破、行扫、列扫登场三卡。
- upgrade：爆破补给、行扫范围、列扫范围三卡。
- build：7种机制卡角色与等级，以及留白调色文字/次数回退。

已目视核对代表性大小视口、双语、明暗主题下的横纵方向、可读正文及确认区。尚未观察真人识别速度，不代替作者审美认可；普通/低特效按钮可人工对照。catalog 同一 SkillCard 的布局、图标及纯展示行为由专项回归覆盖。

icon-regression.log 为最终图标专项；integration.log 为本片完整集成回归；capture.log 为24次导出记录，rule_error均为空。原始日志仅去除终端颜色和行尾空白，保留警告及退出诊断。
