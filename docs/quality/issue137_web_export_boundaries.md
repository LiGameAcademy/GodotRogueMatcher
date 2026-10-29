# #137关联：Web出口资源修复

本片堆叠在#212 `98e8479021454518bcc64362b71a253e61bbc0fb`之上，只修该候选实际暴露的Web出口。原失败导出96条ERROR和浏览器ScreeningConfig解析错误仍保留在`docs/evidence/issue137/`，不能回写成成功。

## 修改与保留

- 同一ScreeningConfig脚本及原UID `uid://c48mymffeh848`由tools移到`gameplay/skills/debug/`，6份工具配置只同步Script路径。常驻ScreeningDeck解析不再依赖被Web排除的tools类型；配置仍在tools，不新增正式profile/候选池，不复制类型或迁移六份配置位置。
- `ui/item_widget.tscn`的缺失icon.svg改为实际icon.png及其正确UID，popup_level_up复用该修正，其布局和行为不变。
- 8份`data/item/effects/*_effect.tres`改为原生Resource子项＋显式Script，修正load_steps；旧自定义类脚本存在，原错误不是类被删除。space_compressor没有这些子项，不修改。保留全部旧参数、conditions/effects数组及顺序，不恢复旧写入口。
- 未改RunController/RuleReplay、规则/随机、采集、插件、project.godot或export_presets；继续严格拒绝任何导出ERROR。

## 验证与限制

- `test_web_export_resources`对8份原序列化意图fixture逐字段比对运行时类型/参数/数组；核同一ScreeningConfig UID、六配置读取及旧弹窗/正式Game场景实例化。fixture是基线意图的回归样本，不是另一份运行配置来源。
- 新资源＋#137消息专项：3脚本14/14、457断言，退出0，无退出资源保留；故意坏消息warning及本机根证书读取诊断保留。
- 旧道具隔离/筛选固定题/筛选场景相关回归：3脚本23/23，1220断言，退出0；29条既有Float/Int比较warning，无退出资源保留。
- 独立只读复审APPROVE，无CRITICAL/HIGH/MEDIUM/LOW；审阅者逐份比对旧参数及代码/UID，不是GitHub批准或CI。
- 严格Web导出及真实浏览器：待O4释放运行时段。本片尚未因此宣布Web或#137整体通过。

所有变更自有脚本≤500行。只跑受影响专项，不跑最终冻结树全量，不改变作者/非设计者未观察字段。按#212→本片顺序review，最终合入develop/0.0.3仍需作者授权，不自动合并/关闭Issue/发布。#160纯值底座及正式恢复均未在本片实施。
