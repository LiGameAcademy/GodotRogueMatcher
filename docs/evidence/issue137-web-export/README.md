# Web出口修复证据

堆叠base：#212 `98e8479021454518bcc64362b71a253e61bbc0fb`。Godot4.7.2 `ed1daf0bf`，GUT9.6；独立APPDATA沙箱。

- resources.log：新资源与#137消息3脚本14/14、457断言，退出0，无退出资源保留。
- related.log：旧道具隔离/筛选题集/筛选场景3脚本23/23、1220断言，退出0；29条Float/Int warning保留，无退出资源保留。
- 独立代码复审APPROVE，无发现；逐项比较八资源参数/数组顺序、ScreeningConfig代码及UID。非GitHub批准或CI。
- 原失败导出与失败浏览器诊断继续保留在相邻issue137证据，不覆盖。

当前证据不是冻结树全量、真人观察或Web通过；严格Web导出/浏览器结果后续按实际提交和包哈希追加。
