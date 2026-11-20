# #129 首批机制图标接入

基于 develop/0.0.3 的 f90a39f（已合并 #187）；本片只接入爆破、行扫、列扫，#129 保持开放。新 PR 留给作者 review，不自动合并。

| 稳定ID | 图元 | 构筑角色 |
| --- | --- | --- |
| core_drop | 爆破 | 登场 |
| core_supply_up | 爆破 | 补给 |
| core_radius | 爆破 | 范围 |
| line_row_drop | 横向扫线 | 登场 |
| line_row_span | 横向扫线 | 范围 |
| line_column_drop | 纵向扫线 | 登场 |
| line_column_span | 纵向扫线 | 范围 |

三选一、技能池及构筑栏复用显示侧 SkillMechanicIcons 清单。完整卡保留名称、规则、预览和状态；构筑用角色小字及等级区分同族卡。未登记卡保留原有文字/缩写，不按宽泛Tag猜图标。不增加技能权限、规则字段、随机调用或存档迁移。

图片沿用 assets/textures/ui 的 icon_ability_explosion.png（79×64）和 icon_ability_sweep.png（85×42），只读共享。来源为教程工作区 art/samples/ui_icons_v01 的既有生成图切片，完整来源、处理和哈希在该目录 README 与 slice_manifest.json；本片未引入新外来素材或修改原图。列扫旋转作用于独立节点，不改纹理。首批只维护2个图元、7项显示映射，无逐卡插画或状态组合整图。

实机发现容器会重置其直接子图标旋转；现由独立 Control 承接布局，内层 TextureRect 保持方向。回归等待布局完成后核对三选一/技能池/构筑，覆盖两语言两主题；同时检查未登记回退、实例隔离、输入穿透及显示不改变局面/配置摘要。

验证结果与限制见本目录交付记录及 docs/evidence/issue129-icons。截图覆盖1280×720、1024×640，中英、明暗和登场/强化/构筑24组合；图标为辅助识别，24像素下箭头线较细，名称和规则始终保留。真人辨识速度与美学认可仍待作者试玩，不能据截图宣称通过。

后续仍需按作者确认清单推进其余机制图标及主题命名/规则文案表达；本片不关闭 #129 或 O4。试玩入口和步骤见 tools/mechanic_icon_preview/README.md。

## 素材来源核对

源基线 gameplay_material_baseline.png 为本项目既有 image_gen 生成素材；本片仅引用已入库导出，不新增第三方授权依赖。保持彩色alpha：爆破提取红黄像素，扫线提取青色轮廓并填白芯，裁紧后四边加4源像素透明留白；未放大或改图。

| 资源 | SHA-256（工程副本与原导出一致） |
| --- | --- |
| icon_ability_explosion.png | 87e8ee1912a5a920f794413ba34d5f3daf439af2c96c2818a50fa45f523a7fd1 |
| icon_ability_sweep.png | 36c2f013281aa580f3b550d02b9ec3bb7fc84984dc66d88173da1056d3f48054 |

## 最终验证（2026-10-24）

- Godot 4.7.2，GUT 9.6，完整 tests/integration：56脚本，318/318测试，8683断言，450.561秒，退出0。
- 最终图标专项：3/3测试、382断言，包含布局等待后的方向和卡池重配置。
- 实际渲染24组合，所有 rule_error 为空；代表截图见 evidence。只运行过Windows Compatibility，不外推其他平台。
- 集成日志有29条既有 Float/Int 比较警告，本次最终运行未报告脚本错误或退出资源保留。截图/专项日志一并保留。
- 最终独立复审 APPROVE，无剩余发现；相关自有代码均低于500行，diff空白检查通过。

PR保留作者 review；本片真人审美/辨识验收仍未填写为通过。

交付可视试玩窗口（最终提交版本）能够启动并响应，但其stderr出现 GLES shader initialize 的 err != OK 错误；原样保留于 evidence/issue129-icons/playtest-startup.log。此前截图导出已完成，不能据此宣称这些启动错误完全无影响，需作者观察当前窗口；不外推跨驱动表现。
