# #119 O1 合入后筛选工具重验

2026-11-03。O1 降范围收口后（`develop/0.0.3`），按试玩说明要求重验单形状筛选入口与报告读盘，再开正式真人排期。不执行真人筛选、不生成保留名单、不关闭 #119。

## 本片

1. Godot **4.7.2** 复跑筛选规则/场景/报告相关回归。
2. 修复 `ScreeningRecordReader`：损坏的 `metadata` 在回放前报 `invalid_metadata`，避免被回放侧 `configuration_mismatch` 吞掉诊断。
3. 记录当前可开测身份：`screening-free-v1` / `screening-fixed-v1`；试调抽选仍 `offer-unified-trial-v2`（见 O1 软收口）。旧 A3/v43 样本不改写、不宣称跨协议精确重算。

## 验证

2026-11-03 本机复跑上述 5 脚本：**43/43** 通过、1523 断言、退出 0（含 Float/Int 既有警告，不新增阻断）。

```powershell
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd "-gtest=res://tests/rules/test_screening_deck.gd,res://tests/rules/test_screening_annotations.gd,res://tests/rules/test_screening_report_reader.gd,res://tests/integration/test_screening_report_cli.gd,res://tests/integration/test_screening_playground.gd" -gexit
```

## 下一步（作者）

按 [issue119_session_checklist.md](../playtesting/issue119_session_checklist.md) 登记 commit、设备、匿名参与者与时段；先作者走查当前树，再约至少 2 位非设计者。#192 鼠标返回已合入，仍须真人实机勾选。U/环/方块与双形状仍依单形状结果另排。
