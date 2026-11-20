# 三张固定转化卡说明

2026-10-30香港时间。基线448cbc9，受测源码/翻译0017aa4fba22da6c0e111c4950bb3c52dbc34ea8；后续只增加证据。独立clone保留，无本地清理。

三张正式TransformMaterialEffect卡（爆壳改装、横扫改装、纵扫改装）读取Resource的count/content_id生成完整双语句式。候选随机冻结至多数量的未附能力普通棋；不足时部分转化，无目标不可用；保留身份/位置/颜色，固定身份失效整批拒绝、不补选。不解锁自然供给或主动权限。Atomic、动态、嵌套及非法配置仍明确回退。未改规则、目标、RNG、核心或菜单。实际52项Resource全目录审计为19生成、33回退，无限升级旧配置只审一级。

| 记录 | 结果 |
| --- | --- |
| transform-regression.log | 冻结源码5脚本25/25、1081断言、exit0；新说明/改count/动态非法回退/只读快照，实际转化与动态预检既有行为测试，全目录覆盖及旧说明回归 |
| transform-gpu.log | 真实Compatibility GPU 1脚本1/1、89断言、exit0；正式Resource三卡真实冻结候选，双语1024×640/1280×720，4图逐张目检无裁切/遮挡，选择及确认区可达，显示前后快照/配置不变 |
| transform-gpu-initial-failure.log | 首版英语过长导致1024×640弹窗越界，88/89断言；精简完整英语句式后修复，不改布局或规则，失败原始日志保留 |

每份日志附原始gzip；可读版只移除ANSI与行尾空白。manifest记录受测身份与提交blob哈希、行数。Godot4.7.2 ed1daf0bf/GUT9.6，RTX2070 NVIDIA610.88 OpenGL3.3 Compatibility，独立临时APPDATA/LOCALAPPDATA=o4-transform-review。最终运行只有已知沙箱root certificate诊断，无脚本解析失败或泄漏退出警告；GPU已退出。导入日志保留，不称零警告。

复现：初始化锁定CoreSystem子模块并editor导入后，运行GUT指定test_transform_rule_descriptions、test_special_conversion、test_dynamic_transform_preflight、test_skill_description_coverage、test_skill_rule_description；GUI指定test_transform_rule_description_ui，设置O4_TRANSFORM_CAPTURE=1可输出截图。未重复无关整库，未声称性能/主题穷举/真人体验通过。

独立复审对照实际Effect/执行器，静态无阻断；最终身份另核。按B交集成核验，#129继续部分OPEN，作者读感和整体真人体验均null。覆盖19/52不代表O4整体验收。

最终权限措辞修正：00bbd810c7fbdd0e9fd56b88c628a0b04e596714将英语改为“Unlocks no supply or manual use”，明确不授予而非禁止已有权限。相对0017仅英语翻译/对应断言变化，最终定向规则+真实GPU两脚本2/2、163断言、exit0。4图已刷新，英语两图重新目检无越界；最终身份见final-manifest.json，原0017成绩保持其身份，不伪记整批重跑。
