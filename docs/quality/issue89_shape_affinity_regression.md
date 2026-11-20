# #89 异形亲和例外固定回归（首片）

归属 O1-KR5 / #89；复用 #84 已确认「分类 / 触发资格 / 抽卡亲和分离」。本片只钉固定案例，不关闭 #89/#84，不新增正式异形收益卡入池，不宣称整版边界验收完成。

## 本片覆盖

| 口径 | 固定案例 | 状态 |
| --- | --- | --- |
| L 取得不改变 T 解锁卡 related/fills_gap/B/Q/W | `test_fg09_…` 整表比对 | 既有 |
| 同类解锁共享 `mechanisms=shape` 不加 related | L 后评 T：`related=0`，`affinity=[]` | 本片 |
| 明确异形收益卡可获一次温和关联 | fixture `affinity=[shape]`：L 后 `related=1` | 本片（夹具，非生产卡） |
| 多形状不累计亲和 | L+T 后仍 `related=1`，`invested` 仅一条 `shape` | 本片 |
| 通用数量/倍率不叠机制关联 | `score_multiplier` / `match_extra` / `precision_reward` / `longline_reward` 在 L 后仍 `related=0` | 本片 |
| shape_unlock 不得自报 affinity/供给缺口 | traits 校验拒绝 | 本片 |
| 诊断字段分离 | 解释行同时落 `mechanisms` / `affinity` / `roles`，不用笼统 Tag 命中 | 本片核对 |

## 明确未覆盖（仍归 #89/#84/#118 等）

- 正式异形收益/强化卡配方与入池（O2 名单）
- 触发资格 ≠ 已解锁（玩法侧前置；本片只看抽选权重）
- #89 其余 FG/RO/RG 矩阵整表勾完、作者试玩与默认配置说明书收口
- #88 正式校准 / 150 seed（见 [issue88_o1_soft_closeout.md](issue88_o1_soft_closeout.md)）

## 复现

```powershell
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_unified_offers.gd -gexit
```
