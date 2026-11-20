# O1 降范围收口（0.0.3 可玩门禁 · 2026-11-02）

作者当日目标：**争取将 O1 收口**，口径仍是「试调默认可玩 + 缺口明列 + 不宣称校准完成」，不是原文 KR4 数值最优与 150 新 seed。

## 结论

| Issue | 处置 | 说明 |
| --- | --- | --- |
| #85 / #86 / #87 | 已关闭 | KR1～KR3 工程交付 |
| #88 | **降范围关闭** | 可玩试调 a=d=0.25、s=0；完整校准另开 |
| #89 | **降范围关闭** | FG/RO 固定回归与版本化试调身份；RO10/#160 外置 |
| #84 O1 父项 | **降范围关闭** | 温和引导抽选可玩落地；可解释校准未完成 |
| #161 | 保持 open | 跨环境/联测不在 O1 软门禁内勾完 |

**禁止对外说法**：O1 数值已校准、稀有曲线已定、明显连携已验收、0.0.3 平衡完成。

## 钉住的可玩默认

见 [issue88_o1_soft_closeout.md](issue88_o1_soft_closeout.md) 第一节。运行身份：`offer-unified-trial-v2` / `gentle_guidance_trial` / `parameter_status=trial_unvalidated` / `acceptance=null`。

## 子项证据入口

- 参数试验与成对窗口：[issue88_paired_trial_binding.md](issue88_paired_trial_binding.md)
- #88 软清单：[issue88_o1_soft_closeout.md](issue88_o1_soft_closeout.md)
- #89 边界矩阵：[issue89_boundary_soft_closeout.md](issue89_boundary_soft_closeout.md)
- 异形亲和固定回归：[issue89_shape_affinity_regression.md](issue89_shape_affinity_regression.md)

## 完整校准延期（须另开 Issue）

建议标题方向：`[0.0.3+][O1-followup] 接受线冻结、稀有/高压试验与正式参数回写`。至少包含：

1. 接受线数字（相关槽/选中、同族上限、均分/满盘）
2. 冻结后新 seed 复核（原 150 口径可重议样本上限）
3. s>0 / 高 k / B_r(k) 覆盖
4. 「明显连携」作者数值口径（与 O3 交叉）
5. 参数标正式并回写模型/Excel 权威

## 作者拍板记录

- 早间：软收口 1/2 + Issue 方案 C（暂不动）
- 傍晚：确认继续 4.7.2，并 **争取今日 O1 收口** → 工程按本清单关闭 #88/#89/#84，校准另开，不关 #161
