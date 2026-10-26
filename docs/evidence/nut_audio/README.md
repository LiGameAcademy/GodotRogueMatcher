# 坚果音效首次接入验证

2026-10-26。分支feature/nut-audio-integration。Godot 4.7.2 stable / GUT 9.6.0，3脚本、19/19项测试、485断言，83.495秒、退出0。结构化结果见summary.json。

在引擎工程根执行：

```powershell
& '<Godot 4.7.2 console>' --headless --path . --fixed-fps 60 --log-file .godot/audio_tests_final.log -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_nut_audio.gd,res://tests/integration/test_feedback_settings.gd,res://tests/integration/test_manual_line_scene.gd -gexit
```

覆盖12个运行WAV路径、11类cue、真实扫线与爆破区分、同类去重和静音、播放器自然结束/重借/取消归还、消除变体轮换与音高封顶、合法移动落位、拒绝与空白点击、缺失音乐、音乐循环资源实例隔离，以及正常/快速表现与独立规则/精确回放一致性。原料与运行文件哈希核验通过，Git同时忽略本地音乐和.import旁文件。

首轮16/18通过，旧测试把初始化结束当成无借用声音并只断言最后一个反馈信号；新增补棋声后不成立。已隔离测试起点并检查完整cue列表，再新增明确拒绝/空白点击测试。未靠修改规则或关闭声音使测试通过。

导入有本机外部文本编辑器启动失败的提示，但脚本解析及上述运行测试通过；不据此修改全局编辑器设置。没有导出Web/含音乐成品，没有真人混音验收。当前公开导出预设排除local_audio/*，私有音乐C没有复制或提交。
