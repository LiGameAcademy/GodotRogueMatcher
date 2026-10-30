# Particle Graph E0：原生粒子验证

仅用于验证 Godot 4.7.2 / Compatibility 下的原生粒子能力，不安装插件，不修改正式游戏场景、计分或演出屏障。

## 运行

在本 Godot 工程根目录执行，替换成本机控制台版引擎路径：

```powershell
& 'D:\GameMaker\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --disable-vsync --max-fps 60 --resolution 1280x720 --log-file .godot/particle_graph_e0/run.log res://tools/particle_graph_e0/particle_graph_e0.tscn
python tools/particle_graph_e0/analyze_captures.py .godot/particle_graph_e0
```

需要真实图形窗口，不能用 headless 结果证明粒子渲染。Python 检查器依赖 Pillow。场景默认约数秒后自行结束；退出码和日志、像素检查都应成功。可用 `-- --e0-output=<绝对目录>` 指定另一输出目录，同时相应调整 log-file 和检查器目录。

运行前确保输出目录存在。首轮可能有 Shader 编译开销，帧编号不直接代表精确的模拟秒数；报告同时保存墙钟时间，位移按截图之间的时间差检查。

## 内容与判定

- 固定速率 100 / 250 / 400，对应长度 4 / 8 / 12 像素，宽度 2；允许边缘栅格化造成 1 像素长度误差。
- 同速率有阻尼与无阻尼对照，确认缩短来自当前运动变化；记录真实截图位移。
- 保持 RGB 为白色、仅 alpha 变化的行验证淡出，事件火花另行验证暖色渐变。
- 重力行检查轨迹和沿速度方向对齐。
- 生成材质保存重读，与原始行并排渲染；检查嵌套曲线复制隔离。
- 实例化正式 BoardView，调用其 remove_piece，接收真实 piece_removing 信号并在显示位置播放火花。只消费显示快照，不执行正式规则行动；不计作 E9 正式玩法接入。

4.7.2 原生按 `speed / (max - min)` 采样，不减去 min。为表达作者速度区间 100～400，原生 min/max 使用 0/400，Y 曲线使用 `(0,1)、(0.25,1)、(1,3)`；X/Z 保持 1。这里生成的全部是原生资源，没有自定义粒子 Shader。

输出含三张分帧截图、事件截图、原生材质、运行报告和像素报告；检查器要求本轮成功结束标记，拒绝不完整运行遗留的旧产物。正式可审阅证据与结论维护在课程总仓库 `projects/godot-particle-graph/docs/e0_validation.md`，不在此复制结论正文。
