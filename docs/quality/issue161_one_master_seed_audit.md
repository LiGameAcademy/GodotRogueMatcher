# #161 一局一主种子：现实现核对（2026-11-02）

作者确认：0.0.3 **必须一局一个主种子**；出生/抽卡/补棋等由主种子派生；命名流可多条，但都从该主种子生长。与 #88 a/d 校准分开。

## 已落地（本机核对）

| 能力 | 现状 | 证据 |
| --- | --- | --- |
| 六流协议 `sl-rng-v1` | `RunRandomStreams` 由主种子派生六流初始 seed | `test_run_random_streams.gd` 固定向量 |
| 正式消费者绑定 | spawn_content/position、offer_candidates/order/targets、effect_execution 共有同一 owner | `RunSeedIdentity` + `test_one_master_seed_invariant.gd` |
| 记录 Header | `seed` 与 `rng.master_seed` 均为主种子字符串 | 同上；`RunRecorder` Header |
| 自然新局熵 | `NewRunSeedSource` 独立平台熵；准备成功才 `remember` | `test_new_run_seed_source.gd`、#233 生命周期 |
| 继续挑战 | 同 run / 同主种子，不重新采样 | `test_new_run_lifecycle.gd` |
| 检查点 | payload 含 `master_seed`，恢复校验与 streams 一致 | `RunCheckpointCodec` / restore |
| 机器人策略种子 | `strategy_seed` 仅驱动 bot 决策，不写入玩法六流 | `test_one_master_seed_invariant.gd` |

默认玩法入口不再用全局 `randi()` 作为主种子；菜单预览/熵失败回退仍可用固定 fixture seed=0，且标 `fixture`/`不 remember` 路径，不冒充自然样本。

## 明确缺口（不关闭 #161）

1. **跨环境矩阵**：同主种子跨引擎补丁 / 桌面↔Web 精确复现仍须单独证据；现有 Web 验证是同浏览器生命周期，不扩成跨端保证。
2. **与 #160 联测清单**：安全恢复多步对照、失效备份政策等按 #160/#161 各自出口继续，不因本核对勾完 RF04/RG 全表。
3. **验收表残留**：issue 正文 RS/RF/RC/RG/RB/RO 多项历史勾选仍标未运行；其中大量已由 #209/#211/#233 及专项测试覆盖。证据索引回填见 [issue161_evidence_index.md](issue161_evidence_index.md)；不假装整表关闭。
4. **表现/音效 RNG**：允许独立于六流（作者设计）；不计入主种子缺口。
5. **跨环境实采**：本机已提供 `seed-portable-v1` CLI；桌面↔Web 对照样本仍待采集（见证据索引）。

## 本片交付

- 新增 `RunSeedIdentity`：运行时核对「一主种子 + 六流归属」。
- 新增不变量测试锁定作者前提。
- 不改默认配置、规则版本、派生算法或正式 `situational_gain`。
