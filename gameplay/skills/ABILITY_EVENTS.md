# O4 / #60：局内事件与条件

目标分支 `feature/skill-refactor`，独立分支 `feat/issue-60-ability-events`。
迁移现有核心/引信离场爆破；保留40项运行目录、数值、匹配及补棋规则。

## 配置与状态

AbilityDefinition使用event_type、conditions、max_triggers和consume_on_empty。
on_eliminated_explosion.tres配置piece_eliminated，原因允许match/explosion/skill_clear/consume，最多一次。
RemovalCauseCondition限制consume只对核心成立；cleanup和重试不引爆。
已移除AbilityDefinition.trigger及GameplayTrigger执行路径，不再提前增加trigger_count。

条件继续复用CoreSystem的只读TriggerCondition契约，但不激活GameplayTrigger或连接TriggerManager。
支持AlwaysAbilityCondition、事件类型、离场原因及CompositeTriggerCondition组合：
AND对应全部满足，OR对应任一满足，单子项NOR对应否定。固定配置顺序短路求值。
空条件数组表示无附加条件；空组合、缺失子项、循环、嵌套超过8层、负次数、未知事件/原因/条件明确拒绝。
概率、时间等插件条件未接入，拒绝它们，避免共享计数与全局随机数影响规则。

## 分发与应用

RunState拥有AbilityEvents；调用者从权威运行实例集合提供本批订阅者，不另存注册表。
棋子整批离场后冻结来源快照并分发，再交已有爆炸队列执行，不递归执行Effect。
事件按世代/来源ID/事件ID排序，订阅者按拥有者ID/安装序/能力ID排序；不同实例身份重复时拒绝。
已有爆炸队列仍按世代/来源ID处理后代；装填、布雷、余震和染色的原结算边界不变。

AbilityEvent携本局唯一事件ID、局ID、根行动、世代、原因、来源快照及可用的父事件/来源能力ID。
离场事件ID与ScoreLedger的计分事件ID分别编号，不能混用；分发顺序由上述规则决定。
首代匹配/清理的parent_event_id为0；爆炸造成的后代引用其离场触发事件。
合成余震尚未迁移为普通能力事件，因此不虚构它的离场父事件，来源能力标记仍保留。

dispatch只生成AbilityActivation票据并保留pending_event_id，不消费次数。
Resolver提交效果后调用complete：拒绝不扣次数，合法空结果按consume_on_empty决定。
既有爆破配置保留consume_on_empty=true；空爆炸仍0分，主动空爆破仍消耗核心及一次行动。
重复事件、重复票据提交不会再次执行/消费；已排队的同实例能力不能重复排队。
预检发生在占格/计分提交前；提交后的内部错误显式进入ERROR，不承诺任意回滚。

重试关闭旧AbilityEvents并建立新实例；本局身份令牌使旧事件及未完成票据失效。
定义只读，计数按AbilityInstance独占，分发器不保留跨局订阅或场景节点。

## 记录、范围与验收

规则版本升级为run-commands-v18-ability-events，记录条件配置、消费政策、事件编号/去重状态及待执行编号。
v17及更早命令不跨版本重算；历史采集文件保留。当前记录仍可精确回放，不要求重跑旧试玩。
取得/升级能力沿用#59定向ChoiceEffect流程；本片不广播取得事实，不增加新技能或全量时机。
通用叶子请求、有序Effect组合归#61；全部技能迁移归#62；详细触发分析工具归#63。

核心验收脚本：tests/rules/test_ability_events.gd、test_ability_triggers.gd、test_explosion_rules.gd。
Godot 4.7.2相关13脚本112测试/2283断言通过，日志`.godot/issue60-regression.log`。
覆盖重复事件/票据、合法空结果与失败消费、快照、稳定排序、All/Any/Not、非法配置、重试隔离、真实主动空爆破，以及原爆破/阶段/预告/机器人窗口/回放/卡片回归。
脚本及Resource导入通过；没有导出Web或做数值分析，编辑器真人试玩待作者review。
作者可用编辑器试玩核心五连、引信连锁、主动空爆破与重开；新局不继承引信、强化或旧票据。
可review AbilityDefinition → AbilityTriggerAdapter（纯查询）→ AbilityEvents（分发与消费）→ AbilityResolver（规则提交）。
