# O3-KR1 · 构筑验证清单与测量口径基线

2026-11-03。Refs #122（父目标 #115）。本片只固化作者已确认的六路线、四指标与工程入口，并登记已有 fixture / 身份 / 遥测缺口；不是自然采样、参数校准、真人验收或 O3 整体通过。

## 身份

| 项 | 值 |
| --- | --- |
| 受测树 | 当前工作树；固定盘既有证据仍指向专项提交 `0c6829d`（见 [issue122_fixed_builds.md](issue122_fixed_builds.md)） |
| Godot | 4.7.2 stable `ed1daf0bf`，GUT 9.6.0，Windows/headless |
| 规则版本 | `run-commands-v46-unified-offer-audit` |
| 抽选配置 | `offer-unified-trial-v2`，`a=d=0.25`，`s=0`，参数仍为 trial_unvalidated |
| 正式目录 | `SkillOfferGenerator.CATALOG` 52 项 |
| 工程入口 | `tools/o3_builds/build_routes.gd`（`O3BuildRoutes`） |
| 守卫测试 | `tests/rules/test_o3_build_routes.gd` |
| 固定盘专项 | `tests/rules/test_o3_fixed_builds.gd` + [issue122_fixed_builds.md](issue122_fixed_builds.md) |

O1 可玩门禁已软收口；本基线依赖其抽选身份稳定，但不复述 O1 平衡结论。O2 正式保留名单未补入；异形随 O2 交付后再扩路线。

## 六路线（作者确认顺序）

机器可读副本见 `O3BuildRoutes.routes()`。箭头是成长测试步骤，不保证自然抽卡顺序，不要求全套到齐才成型。

| 编号 | 标题 | 发动机 | 成长样本 | fixture 覆盖 |
| --- | --- | --- | --- | --- |
| B1 | 爆破基础兑现 | `core_drop` | `core_supply_up` / `blast_radius` / `blast_reward` / `blast_extra` | partial：F-P 准备六连代价（非完整 B1 取得链） |
| L1 | 单轴扫线 | `line_row_drop` / `line_column_drop` | `line_row_span` / `line_column_span` / `line_clear_score` | `line_clear_score` 成对对照 + RuleReplay |
| B2 | 引信连锁 | `core_drop` / `assign_fuse` | `core_fuse_payload` / `fuse_relay` / `marked_reward` / `fuse_capacity` / `fuse_match_plant` | `fuse_chain`：有效/空爆分诊（见 [o3_b2l2_fixed_chains.md](o3_b2l2_fixed_chains.md)） |
| L2 | 十字扫线 | 任一行列登场 | `line_cross_upgrade` + 合法跨度/收获 | `cross_pair`：成对独占轴 + `fixture_line_cross` 回放 |
| M1 | 爆破启动扫线 | 爆壳 + 任一行列 | 范围 / 跨度 | `blast_starts_line`：命中/未命中分诊（见 [o3_m1m2_fixed_chains.md](o3_m1m2_fixed_chains.md)） |
| M2 | 扫线启动爆破 | 行列 + 核心/引信 | `core_fuse_payload` / `blast_radius` / `fuse_relay` | `line_starts_blast`：有效/空爆分诊 |

顺序：B1 → L1 → B2 → L2 → M1 → M2。主动爆破/扫线及终幕余震作第二批分支；有限主动不代替固有持续作用。

## 四项测量口径

机器键名：`startup` / `sustain` / `synergy` / `upgrade`（`O3BuildRoutes.MEASURES`）。语义与 #122 一致，缺字段记 null，不填 0。

| 键 | 白话 | 不得混淆 |
| --- | --- | --- |
| startup | 取得 → 载体出现 → 首次有效作用；取得后按有效玩家行动等待；即时赠送可记 0 但须证据 | 持有 ≠ 启动；空命中不算有效 |
| sustain | 首次赠送/即时与后续补给、重复作用分开；有限主动分次数内兑现与耗尽后固有 | 不要求无限持续 |
| synergy | fixture 证明有因果的触发链；正常池记形成/利用机会 | 持有两卡或总分高 ≠ 协同 |
| upgrade | 合法升级存在、实际候选、成功取得、作用变化、意愿分开 | 配置存在/满级 fixture ≠ 自然成长 |

B1/L1 试验参考窗（非正式门槛）：首次 4/8 行动、后续 10 行动、成长 3 次奖励；完整窗口比例才谈 70%/60%/60%，截尾与未取得必须并列。B2/L2 沿用观察窗与同级预算，暂不套上述比例线。M1/M2 窗口/预算仍为试验起点。

## 已有技术证据与缺口

| 资产 | 身份 | 结论边界 |
| --- | --- | --- |
| F-P 固定盘（seed 23/77 + 通路反例） | fixture/automated | 开放盘可合法准备六连并付真实代价；非自然成功率 |
| L1 `line_clear_score` 成对盘 | fixture + 磁盘 RuleReplay | 同目标 +4 归因；非持续供给/自然选卡 |
| `O3BuildRoutes` + 守卫测试 | 只读清单 | 防目录漂移；不采样 |
| 自然扫描 / H=20 主窗 | 未开跑 | 待 O1 测量基线与工具就绪后另登记 |
| 遥测 `capabilities.all_ability_attempts` | **false**（`telemetry_projector.gd`） | 完整能力机会率与父因果采集缺口保留；缺字段不当 0 |
| B2/L2 固定因果盘 | 已建（[o3_b2l2_fixed_chains.md](o3_b2l2_fixed_chains.md)） | 正确性分诊；非自然成型 |
| M1/M2 固定因果盘 | 已建（[o3_m1m2_fixed_chains.md](o3_m1m2_fixed_chains.md)） | 跨系触发分诊；非自然混搭 |
| 真人 2×路线片段 | 未安排 | 不与机器人证据混用 |

## 验证（本片）

隔离 `APPDATA` 后复跑：

```powershell
$godot = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path (Get-Location) '.godot/o3-sandbox'
& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_o3_fixed_builds.gd -gexit
& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_o3_build_routes.gd -gexit
```

本机复跑（2026-11-03）：固定盘 3/3、69 断言；路线守卫 3/3、48 断言；均退出 0。未跑整库、无 GUI/性能结论。封存证据目录未覆盖；本片复跑仅作当前树冒烟。

## 出口与剩余

本片交付：六路线机器入口、四指标键名、身份钉死、fixture 覆盖表、遥测缺口明示。不关闭 #122，不定正式门槛，不改生产规则/Resource/抽选参数，不宣称路线达标。

下一步（另片授权）：每路线烟测 10 → 自然取得探索批；埋点缺口核定后再报机会率。#34 专色与 #38 方向收益仍外置。
