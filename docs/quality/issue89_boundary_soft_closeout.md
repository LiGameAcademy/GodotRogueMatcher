# #89 边界回归降范围收口（0.0.3 可玩门禁）

作者 2026-11-02 要求今日争取 O1 收口。本清单把 #89 收到与 [#88 软收口](issue88_o1_soft_closeout.md) 同级的 **可玩门禁**：固定案例与版本化试调配置可解释，**不**宣称完整平衡/真人验收/150 seed。

引擎：Godot **4.7.2**（`ed1daf0bf`）。

## 一、验收项对照（工程已覆盖 / 明确外置）

| #89 验收白话 | 证据 | 本门禁 |
| --- | --- | --- |
| 门禁、多 Tag 一次、供给/强化、满级/一次历史、空盘不丢永久资格 | FG01–10 + `test_unified_offers.gd` | 通过（固定案例） |
| 异形亲和例外（L≠T 加权、多形状不累计、收益一次关联） | FG09 + `test_shape_affinity_exception_…`；[issue89_shape_affinity_regression.md](issue89_shape_affinity_regression.md) | 通过（夹具；正式异形收益卡入池仍归 O2） |
| k 只随成功取得；冻结目标；确认失败保留；不足三张政策 | RO01–06：`test_reward_waiting_rules.gd` | 通过 |
| 工具配额/保底/救场不恢复子池 | 配额用例 + `test_pressure_offers`（startup/rescue 默认关） | 通过（默认关） |
| 固定输入与版本回放；禁止静默旧版重算 | `test_offer_trial_config` / `test_offer_measurements` / JSONL 浮点片 [89-json-transport.md](../validation/89-json-transport.md) | 通过 |
| 每正式参数有版本与证据；未决仍试调 | `offer-unified-trial-v2` / `gentle_guidance_trial` / `parameter_status=trial_unvalidated`；见下表 | 通过（全部试调） |
| 默认配置与使用说明 | `offer_config.tres` + [tools/bot_testing/README.md](../../tools/bot_testing/README.md) 试验入口 | 本片同步软收口指针 |
| RO07 存档身份 | `test_ro07_snapshot_…` | 通过（当前状态快照口径） |
| RO08 失效边界细项 | 部分由等待规则/未知定义拒绝覆盖 | **部分**；坏档/忙碌交叉归 #160 |
| RO10 失败保存强杀分支 | O5/#160 职责 | **外置**，不本门禁勾完 |
| 作者试玩与 review | Web 试玩「暂时没什么问题」支撑可玩；非整版体验签收 | **可玩**，非体验完整验收 |

## 二、试调参数身份（与 #88 一致）

| 参数 | 值 | status |
| --- | --- | --- |
| a / d / s | 0.25 / 0.25 / 0 | trial_unvalidated |
| Q / V / 限幅 / 工具配额 | 1 / 1 / 1～2 / 最多 1 | trial |
| B 稀有档 | 平坦对照曲线 | 待测·高 k |
| acceptance | null | 禁止标正式最优 |

## 三、本门禁明确不勾

- 完整平衡验收、300/150 局通过叙事
- 正式异形收益卡入生产池与 O2 名单筛选
- RO10 与跨环境存档联测（#160/#161）
- 真人体验接受区间定稿

## 四、复现命令（本机 4.7.2）

```powershell
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd "-gtest=res://tests/rules/test_unified_offers.gd,res://tests/rules/test_reward_waiting_rules.gd,res://tests/rules/test_snapshot_safe_points.gd,res://tests/rules/test_offer_measurements.gd,res://tests/rules/test_offer_trial_config.gd,res://tests/rules/test_pressure_offers.gd" -gexit
```

2026-11-02 本机复跑：6 脚本 **61/61** 通过、1831 断言、退出 0（APPDATA 沙箱 `.godot/io-sandbox-o1`）。
