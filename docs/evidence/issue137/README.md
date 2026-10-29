# #137 技术证据

实现提交：`4d42c07048e2bf685ba760c74f1264615e3342d2`；base：`1a03cb19d7cde1570edfecbc56e1fd3bfa878407`。后续仅证据提交不改变受测生产/测试源码。

- `baseline-probe.log`：受控加载base原Hud脚本，英文终局→中文仍英文。非历史Web唯一根因结论。
- `status-focused.log`：最终2脚本11/11、313断言、退出0，无退出资源保留。故意注入缺键/坏参/坏目录的HUD warning是验收诊断，不是静默通过。
- `status-regression.log`：既有4脚本23/23、573断言、退出0；有8对象/4资源退出保留，尚未定位归因，不能冒称零诊断或生产崩溃。
- 根证书读取失败是本机headless环境诊断，未隐藏。首次工作树导入的缺缓存/编辑器设置权限启动日志不计游戏验收通过。
- 独立复审最终APPROVE，无阻断发现；不是GitHub批准或CI。

Godot 4.7.2 `ed1daf0bf`，GUT9.6，独立APPDATA；详细调用清单和限制见`docs/quality/issue137_status_messages.md`。无冻结树全量或真人接受结论。Web候选另列实际包和观察，不用本文件的桌面结果替代。
