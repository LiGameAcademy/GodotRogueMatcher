# O3-KR1 降范围收口（构筑验证基线可开测 · 2026-11-04）

作者当日同意：**软收 #122**。口径对齐 O1/O2：**六路线清单 + 测量入口 + 机器人基线证据可开测 + 缺口明列**，不是正式门槛通过，不是 O3 父目标完成。

## 结论（作者 2026-11-04 同意）

| Issue | 处置 | 说明 |
| --- | --- | --- |
| #122 O3-KR1 | **降范围关闭** | 清单/固定链/烟测/自然取得/三窗观察/齐备覆盖已落盘；`pass_line=null` |
| #123 O3-KR2 | **保持 open** · 板状态改回「待开发」 | 断点诊断尚未开工 |
| #124 O3-KR3 | **保持 open** · 板状态改回「待开发」 | 连携/边际尚未开工 |
| #125 / #126 | **保持 open** · 「待开发」 | 调参与独立复核未启动 |
| #115 O3 父项 | **保持 open** · 「开发中」 | KR1 软收不等于 O3 完成 |

**禁止对外说法**：六路线已达 70%/60%/60%、构筑平衡完成、synergy/机会率已验收、O3 数值调参完成、真人构筑体验已通过。

## 一、本门禁钉住的工程默认（可开测）

| 能力 | 现状 | 身份 / 证据 |
| --- | --- | --- |
| 六路线机器入口 | `O3BuildRoutes` | [o3_kr1_baseline.md](o3_kr1_baseline.md)；守卫 `test_o3_build_routes` |
| B1/L1/B2/L2/M1/M2 固定因果 | fixture | [issue122_fixed_builds.md](issue122_fixed_builds.md)、[o3_b2l2_fixed_chains.md](o3_b2l2_fixed_chains.md)、[o3_m1m2_fixed_chains.md](o3_m1m2_fixed_chains.md) |
| 每路线烟测 10 | 预装发动机；仅 `rule_error` 门禁 | [o3_route_smoke.md](o3_route_smoke.md) |
| 自然取得探索 | 目标 30 / 上限 100 | [o3_route_explore.md](o3_route_explore.md) |
| 取得后观察窗 | startup/sustain/upgrade；`pass_line=null` | [o3_route_observe.md](o3_route_observe.md) |
| board_full 齐备覆盖 | `--target-resolved` 条件化样本 | 同上 + `route-observe-resolved.json` |
| 抽选身份 | 与 O1 试调一致 | `offer-unified-trial-v2` / `trial_unvalidated` |

## 二、明确不做 / 本门禁不勾

- [ ] 宣布 B1/L1 正式通过 70%/60%/60%（或缺正式门槛数字）
- [ ] 填满 `synergy` / 完整能力机会率（`all_ability_attempts` 仍为 false）
- [ ] H=20 成对主窗全量结论
- [ ] 真人 2×路线片段
- [ ] #123 断点表、#124 边际收益、#125 调参、#126 独立复核
- [ ] 关闭 #115 或宣称 O3 整体完成

## 三、缺口明列（交给后续 KR）

| 缺口 | 说明 | 建议归属 |
| --- | --- | --- |
| 机会埋点 / synergy | `capabilities.all_ability_attempts=false`；缺字段不当 0 | #123 / #124 前置 |
| H=20 成对主窗 | 基线登记未开跑 | #124（与取得率分开） |
| B1 齐备覆盖 | `--target-resolved` 扫 300 仅 9/10 | 观察复测或 #123 覆盖诊断 |
| 正式 pass_line | 仍待作者讨论 | #122 follow-up / #126 前冻结 |
| 真人片段 | 参与者未安排 | 外置；不与 bot 混用 |
| 调参与复核 | 无整版数值结论 | #125 → #126 |

## 四、作者拍板

1. [x] 同意 0.0.3 **O3-KR1 可开测门禁**：清单与机器人基线可用，接受「正式门槛未定」。
2. [x] 同意 **不**宣称路线达标、synergy 完成或 O3 父目标完成。
3. [x] Issue：**关 #122**；#115/#123～#126 保持 open；板：#122→完成，#123/#124→待开发，#115 保持开发中。

## 五、本轮工程出口

| 项 | 状态 |
| --- | --- |
| 软清单本文 | 已生效 |
| 关键提交 | `2be39d2`…`ea1ca47`（清单→观察→齐备覆盖） |
| 守卫 / 批跑 | 观察守卫 7/7；完整窗 / resolved 批 `failures=0` |
| Issue / Project | #122 降范围关闭；板状态按第四节更新 |
