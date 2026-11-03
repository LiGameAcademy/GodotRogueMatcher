# #161 可携种子向量桌面↔Web 对照

2026-11-03。协议 `seed-portable-v1`，主种子 `42`，`draws=8`，引擎 Godot **4.7.2** `ed1daf0bf`。

| 样本 | 平台字段 | 文件 |
| --- | --- | --- |
| 桌面 CLI | Windows | `42-desktop.json` |
| Web 探针导出 | Web | `42-web.json` |

比较命令（仅玩法字段）：

```powershell
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . -s tools/seed_vector/compare_vectors.gd -- docs/evidence/issue161-seed-portable/42-desktop.json docs/evidence/issue161-seed-portable/42-web.json
```

本机结果：`mismatch=OK`（`SeedPortableVector.gameplay_mismatch` 空串）。平台字段不同不影响判定。

复现 Web 样本：临时将 `project.godot` 的 `main_scene` 指到 `res://services/run_random/seed_vector_probe.tscn`，导出 Web 至任意目录，浏览器加载后读取 `window.__SEED_PORTABLE_VECTOR__`（或控制台 `SEED_PORTABLE_VECTOR_*` 标记）。导出后必须恢复 `main.tscn`。

不宣称完整玩法回放跨端；不勾 #160 RF04。
