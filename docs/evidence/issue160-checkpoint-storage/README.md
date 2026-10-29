# #160存储底座证据

base：e3e3f978ad0ae9f0555756475c7392862c594036；代码清单SHA256见source-sha256.json，提交前受测工作树与交付代码一致。

- io-delivery.log：最终20/20、308断言、退出0，无退出资源保留。Godot4.7.2 `ed1daf0bf`、GUT9.6，0.469秒。
- 命令：`--headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_checkpoint_store.gd -gexit`，APPDATA指向本工作树`.godot/io-sandbox`。
- 内存故障矩阵之外，有真实隔离目录的主备读取/复制/rename失败/未完成提交恢复/失效marker失败与重试；不访问真实作者存档，不进行真实进程强杀或断电。
- 唯一环境ERROR为根证书读取；没有把期望的IO错误变成引擎异常。独立复审APPROVE，无阻断，不是远端CI或GitHub批准。
- 失效marker未持久成功时旧checkpoint在新实例仍可能可读，但新身份begin仍拒绝；调用方必须先确认持久失效才开始新局。完整跨重启终局失败意图/正式恢复/SV/Web不在本片。

具体契约及验证边界见`docs/quality/issue160_checkpoint_storage.md`。不是冻结树全量、真人或发行证据。
