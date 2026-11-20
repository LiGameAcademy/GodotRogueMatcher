# 最薄粒子插件闭环验证

先运行 `tests/integration/test_particle_graph_runtime.gd`，它会在 `.godot/particle_graph_thin/` 保存共享图和包含轻击、重击两个实例的场景。

随后以独立进程运行：

```powershell
& 'D:\GameMaker\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --disable-vsync --max-fps 60 --resolution 1280x720 --log-file .godot/particle_graph_thin/smoke.log res://tools/particle_graph_thin/particle_graph_thin.tscn
```

场景会重新加载之前保存的图与节点覆盖，截取轻重击对照，再在正式 Game 场景中执行现有爆炸验收行动。要求发出火花通知、最终得分仍为 70、演出完成；低特效清空火花后，规则快照摘要不变。

工具禁用玩家偏好保存、局记录、采集与检查点。它使用正式规则与表现代码，不另算计分。截图和 `smoke.json` 写到上述缓存目录，不进入游戏数据或插件仓库。

无图编辑器，无通用模块增删和连线编辑；本工具也不代表正式发行或导出验收。
