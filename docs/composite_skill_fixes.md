# 组合技能修复约定

## 清色后无可染目标（#77）

“清色后染”的染色叶子显式配置 allow_empty_targets。前序清色后仅剩零或一种普通棋子颜色时，染色为空结果，仍正常完成取得、扣除一次奖励并结算延后的引信爆炸。独立即时染色保留至少两种普通棋子颜色的限制。参数错误和仍有可染材料的无效目标不会因此被忽略。

规则版本：run-commands-v22-composite-empty-dye；旧记录继续保留用于分析，不使用新规则重放旧版本。

## 保留卡牌预告颜色（#78）

后续 ChoiceEffect 通过 refresh_after_previous 刷新目标，默认沿用当前棋盘重选。ColorWeightEffect 保留预告颜色，只刷新该颜色的权重前后值，不再次消耗目标随机流；DyeMaterialEffect 仍在清色提交后重新选存活材料。原始冻结预览不被修改。

规则版本：run-commands-v23-composite-preview。

## 保留组合全部得分事件（#79）

染色与核心投放的 MatchResult 均追加到共享结果中，保留此前叶子的事件顺序；清色及延后爆炸继续沿用追加方式。计分仍由 ScoreLedger 提交，不重复记分。表现和 RunRecorder 消费同一份完整结果。

规则版本：run-commands-v24-composite-score-events；旧记录中的缺失事件不回填，不与新规则混用精确回放。

## 全技能测试入口收口（本次 debug 附加验收）

运行目录42卡（35张直接 Effect、7张分级能力）均通过 SkillRules.freeze_target → SkillRules/ChooseSkillCommand → AbilityEffectRunner。保留叶子单元测试及故意非法目标案例，移除取得测试对 choice_effect 字段的假设、空升级目标和重复手写冻结逻辑。

新增目录级命令与所有声明升级级别回归，检查配置不变、实例保留、重复提交幂等，以及记录事件合计等于权威账本。演出夹具先冻结合法目标，再为具体出生五连明确设置落点和颜色；不依赖旧版核心默认绿色。循环 Resource 测试在验证后主动断开自身引用。

最终验证：Godot 4.7.2，完整 `res://tests`（含子目录）57个脚本、422项测试、11709条断言全部通过，约502秒。初轮393项中暴露的3项旧夹具失败，以及单独根目录测试暴露的2项旧夹具失败均已修正；原行为断言保留。日志位于隔离修复工程 `.godot/skill-full-regression-final.log`。退出不再出现循环测试引起的资源保留警告；写失败、非法配置等负向测试仍有预期诊断。不包含作者原目录的未提交扫线手改动，不导出Web。
