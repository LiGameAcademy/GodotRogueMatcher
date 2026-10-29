# Web出口修复证据

堆叠base：#212 `98e8479021454518bcc64362b71a253e61bbc0fb`。Godot4.7.2 `ed1daf0bf`，GUT9.6；独立APPDATA沙箱。

- resources.log：新资源与#137消息3脚本14/14、457断言，退出0，无退出资源保留。
- related.log：旧道具隔离/筛选题集/筛选场景3脚本23/23、1220断言，退出0；29条Float/Int warning保留，无退出资源保留。
- 独立代码复审APPROVE，无发现；逐项比较八资源参数/数组顺序、ScreeningConfig代码及UID。非GitHub批准或CI。
- 原失败导出与失败浏览器诊断继续保留在相邻issue137证据，不覆盖。

当前证据不是冻结树全量、真人观察或Web通过；严格Web导出/浏览器结果后续按实际提交和包哈希追加。

## 最终组合追加

- v46-combination.log：3b71b9d，5脚本31/31、1206断言、退出0。
- tooltip-combination.log：3e5de0a，2脚本10/10、305断言、退出0，无退出资源保留。
- web-final-export.log / web-final-build.json：3e5de0a干净源码，严格脚本退出0、无ERROR/SCRIPT ERROR；含真实ZIP/PCK SHA256、引擎/规则/子模块与配置身份。
- invalid-cache-start.log：parent同步O1后未先import造成的无效启动，6项失败保留；之后完成import且没有修改规则源码，7/7消息专项通过，见继承的issue137/status-hover-verified.log。无效启动不是验收通过。
- 实际浏览器：1280×720，英文Paused正文+可见悬浮，切中文两者“已暂停”，切回英文两者Paused；回合1/行动0/空位76及暂停保持。console error/warn=[]。鼠标停留不按下取得工具截图，点击会清tooltip；详细限制见质量记录。没有作者/非设计者新样本。

后续证据提交不改变以上受测代码。原文待验证状态为历史，不覆盖原失败记录；最终仅本片技术Web出口通过，不代表整版发行通过。无新全量。
