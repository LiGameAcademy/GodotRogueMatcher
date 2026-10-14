# 组合技能修复约定

## 清色后无可染目标（#77）

“清色后染”的染色叶子显式配置 allow_empty_targets。前序清色后仅剩零或一种普通棋子颜色时，染色为空结果，仍正常完成取得、扣除一次奖励并结算延后的引信爆炸。独立即时染色保留至少两种普通棋子颜色的限制。参数错误和仍有可染材料的无效目标不会因此被忽略。

规则版本：run-commands-v22-composite-empty-dye；旧记录继续保留用于分析，不使用新规则重放旧版本。

## 保留卡牌预告颜色（#78）

后续 ChoiceEffect 通过 refresh_after_previous 刷新目标，默认沿用当前棋盘重选。ColorWeightEffect 保留预告颜色，只刷新该颜色的权重前后值，不再次消耗目标随机流；DyeMaterialEffect 仍在清色提交后重新选存活材料。原始冻结预览不被修改。

规则版本：run-commands-v23-composite-preview。
