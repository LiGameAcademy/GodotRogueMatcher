# #129 机制图标试玩

运行 `godot --path . tools/mechanic_icon_preview/mechanic_icon_preview.tscn`。

- 默认“供给与倍率”：留白一手、加速播种、计分倍率。供给分别用−/+，倍率用×，保留完整规则与变化预览。可选卡确认，查看正式构筑刷新。
- “供给构筑”：同时装有两种临时供给、倍率与未登记的连珠补分。供给显示剩余3次，倍率显示Lv.1；两种供给同时生效相抵，但各自次数独立消耗。正常移动并触发实际补棋，检查3→2→1→消失；成功五连免补棋不扣次数。
- 原有“登场三卡”“强化三卡”“构筑与回退”继续保留。行扫横向、列扫纵向；同族用登场/补给/范围及等级区分，回退样例改为连珠补分。
- 支持中文/English、明亮/深色、普通/低特效；H隐藏或显示工具按钮。
- “查看技能池”核对同一图元；“查看棋盘”暂收选卡后查看构筑，再返回选择。

入口使用真实Game、SkillRules和奖励命令。固定种子129，供给样例从第4次奖励起以满足中期候选条件；只提供本片代表候选，不代表自然掉落或平衡验收。不保存玩家设置、不记录回放、不收集真人数据。

追加 `-- --capture-icons` 可导出两语言×两主题×两尺寸×供给候选/构筑，共16张至 `.godot/issue129-economy-icons/captures/`。

Windows本机验证时，原隔离用户目录曾出现GLES初始化错误及白棋盘。改用工程内短目录后捕获和再次启动正常。可在当前启动终端临时设置（仅影响该终端及子进程，不改系统设置）：

```powershell
$env:APPDATA = Join-Path $PWD '.godot/icon_user'
$env:LOCALAPPDATA = $env:APPDATA
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
godot --path . tools/mechanic_icon_preview/mechanic_icon_preview.tscn
```

这只是本机可复现的隔离办法，尚未证明引擎根因；原诊断保留在 evidence，遇到渲染异常不能据规则测试宣称可视验收通过。
