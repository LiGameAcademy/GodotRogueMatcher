# 技能卡布局回归修正 · PR #165

修正提交`7dd6bda`。只修改`tests/integration/test_skill_cards.gd`（155物理行）；运行场景、卡片动画、字号和布局均不变。Godot4.7.2 / Compatibility / GUT9.6.0，独立APPDATA沙箱。

## 根因与修正

原用例在show_offer后的第3帧测量矩形，此时翻牌隐藏Content，子容器尚未排版。诊断样本在第3帧scale.x=0.52，卡片y=152、隐藏操作提示/稀有度y=-249；第30帧scale=1，操作提示y=468、稀有度y=245，均在352像素高卡片范围。见[原始诊断输出](probe-output.log)。此前416项失败的原始输出仍保留在上级full-output.log。

测试改为等待每张卡实际翻牌finished信号（2秒上限），再等两帧容器排版。全部原有包含关系/摘要/弹窗边界断言保留，增加Content可见和scale=Vector2.ONE检查，并将完整目录扩展为中英文×两分辨率×正常/低特效的8种组合。没有跳过失败用例或增大容差。

## 实际验证

完整自有回归78脚本、574/574测试、22378断言全部通过，264.838秒、退出0；未发现脚本解析错误。技能卡、选卡协调、表现/模式切换、技能池、规则、机器人及精确回放均在此套内。逐脚本统计提取78项，各项passed=total。

技能卡独立回归5/5测试、3140断言通过，2.485秒、退出0，见[cards-output.log](cards-output.log)。完整回归结果和逐脚本统计见本目录full-output.log及script-results.json。

检查diff确认仅更正测试观察时点、增加覆盖；等待设置上限，后续可见/scale断言确保超时不会被当成布局成功。变更文件155行，代码及文档diff检查通过。没有执行编辑器人工视觉验收或Web导出；根证书读取错误及其他引擎提示保留原样。

## 复现

在实际游戏仓库运行PowerShell：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/issue133/layout-reproduce-sandbox'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_skill_cards.gd -gexit
```

完整回归将`-gtest=...`替换为`-gdir=res://tests -ginclude_subdirs`，使用另一个APPDATA沙箱。本目录manifest记录原始机器产物字节数和SHA256，不包含本README和manifest自身；继承上级保留原始日志字节的属性。
