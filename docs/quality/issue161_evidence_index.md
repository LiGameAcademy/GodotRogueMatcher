# #161 验收表证据索引（回填；Issue 已降范围软关）

2026-11-03。配合 [一局一主种子核对](issue161_one_master_seed_audit.md) 与 [软收口](issue161_soft_closeout.md)。本页只把**已有工程证据**对照 Issue 历史勾选；未勾完 RF04/#160 与完整玩法跨端回放。#161 按可玩门禁关闭，不宣称整表通过。

## 新增本片：可携种子向量

- 协议：`seed-portable-v1`（`SeedPortableVector`）
- 锁定：同主种子下六流初始 seed + 各流前 N 次 `randi()`（十进制字符串）
- 桌面导出：

```powershell
$engine = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $engine --headless --path . -s tools/seed_vector/seed_vector_cli.gd -- 42 8 > .godot/seed-vector-42-desktop.json
```

Web/其他引擎补丁用同一 CLI 参数出 JSON 后，仅比较 `rng_scheme_version` / `master_seed` / `draws` / `streams` / `first_draws`（`SeedPortableVector.gameplay_mismatch`）。平台字段仅信息性。

**2026-11-03 桌面↔Web 对照**：主种子 42 / draws 8，同引擎 4.7.2，`gameplay_mismatch=OK`。样本与复现见 [issue161-seed-portable](../evidence/issue161-seed-portable/README.md)。RF01 同版本跨端抽签向量闭合；仍不宣称完整玩法回放或 #160 RF04。

## 对照摘要

| 组 | 工程状态 | 主要证据 |
| --- | --- | --- |
| RS01～RS05 新局生命周期 | **大部覆盖** | `test_new_run_seed_source` / `test_new_run_lifecycle` / [161-new-run-lifecycle.md](../validation/161-new-run-lifecycle.md) |
| RF01 同端同种子确定性 | **覆盖**；跨端抽签向量 **已对照** | 六流固定向量 + portable vector；桌面↔Web `mismatch=OK`（完整玩法回放仍外置） |
| RF02 表现不推进玩法流 | **覆盖** | 六流隔离用例；表现 RNG 独立于六流（设计允许） |
| RF03 规则不变目标重选 | **部分** | 奖励/目标流绑定；完整目标叶矩阵归既有 RC |
| RF04 #160 恢复多步 | **外置** | #160；不因本索引勾完 |
| RF05 协议拒绝 | **覆盖** | `RunRandomStreams.from_data` / replay 拒绝未知协议 |
| RP01～RP06 派生与载荷 | **覆盖** | `test_run_random_streams`（含 .NET 对照向量） |
| RC01～RC10 候选冻结 | **大部归 O1/#89** | `test_unified_offers` / `test_reward_waiting_rules` / `test_snapshot_safe_points` |
| RG01～RG07 熵与碰撞 | **大部覆盖** | 新局熵源 + Web 同浏览器生命周期验证；非跨补丁 |
| RB01～RB06 字节载荷 | **覆盖** | 有符号 64 位十进制 roundtrip / 非法拒绝 |
| RO01～RO10 奖励续行 | **大部归 #89** | 见 [issue89_boundary_soft_closeout.md](issue89_boundary_soft_closeout.md)；RO10→#160 |

## 明确仍开

1. 其他引擎补丁 / 非 4.7.2 的跨补丁矩阵（本片仅同版本桌面↔Web）
2. #160 联测清单（RF04/RO10）
3. Issue 正文历史勾选框不在本片批量改写 GitHub 正文（以免伪称整表通过）
4. 完整玩法命令前缀跨端精确回放（超出 portable 抽签向量）
