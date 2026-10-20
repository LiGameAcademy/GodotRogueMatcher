# 本地数据采集 · #13 首片

桌面/编辑器的 Game 默认开启 collect_telemetry；record_runs 独立控制精确回放文件。F1 菜单及结算页提供保存状态、记录目录、导出 ZIP，正常桌面入口还可“保存并退出”。文件仅写本机、不上传。Web 暂不承诺桌面文件/导出入口，发行验证归 #10。

- user://telemetry/<run_id>.jsonl：schema 2 观察与规则事实。
- 同路径 .summary.json：正常终局/已知退出的唯一单局汇总。
- 同路径 .recovered.summary.json：已确认停止后的持久前缀恢复，不修改原文件。
- user://telemetry/sessions/：独立会话事件，含终局后的页面停留。
- user://run_records/：run-jsonl-v1 精确回放；当前玩法规则为 run-commands-v15-goal-score-bonus。旧记录保留，当前规则拒绝跨版本精确重算。

RunCollection 是 Game 的自包含服务子场景。它向 Board 注入 TelemetryFactory，消费绑定的 RunController 生命周期，并在下一可用帧批量刷新。2秒候选心跳在暂停时也处理；最终退出、切模式、重开与导出排空。TelemetryProjector 只消费 Recorder 的冻结值记录，BoardObservation 提供真实曝光/输入/互斥观察时间。它们不推进规则、不调用UI、不消耗游戏RNG。

完整有效移动/主动爆破在尾结算、实际补棋与阶段凭证产生后只有一条 action_resolved。途中退出的摘要 complete=false；选卡独立 reward 批次，不能充当新行动或重复叠入动作收益。stage_goal_completed、offer_generated、offer_presented、skill_acquired 分开；实际曝光不能由生成候选替代。v2不再产生 turn_resolved，离线 Reader 保留v1兼容，CSV turns 表按版本选择唯一来源。

整数为十进制字符串，未知为null/unknown；模式、source/collection_context、配置、规则/内容/候选/压力版本分别分组。编辑器标 editor_playtest，嵌套测试标 automated_integration，fixture与bot另组。提交未知不冒用版本号；编辑器可只读 Git HEAD（未提交工作加+dirty），导出包从 application/config/commit_id 注入。没有提供真实父事件链时 parent_event_id=null。

#16首片只实现过关嘉奖：目标结果记录goal_bonus_score、奖励前score_total、奖励后score_after_goal及goal_score账目，rule_fact以goal:<stage_id>独立批次保存，root_action_id=null。action_resolved的得分截在目标奖励前；目标奖励不冒充玩家有效行动。stage_goal_completed保存奖励前后真实P和已安装构筑，implemented_goal_effects只列goal_score_bonus。清半盘和额外选卡尚未实现，尚不补收益估值或Excel回填。

观察包括 UI、阶段/T/carry/u/q、n/empty/L/P、构筑/offer、最近成功命令/选卡、完整根边界及UTC/单调时间。α=0.7只是压力观察试调，不改变抽卡权重。观察时间按 inactive > pause > choice > busy > input 互斥，心跳不重复记账或复制全棋盘。

字节队列上限4MiB，accepted_seq与persisted_seq分别报告。编码必要事实后整批store_buffer/flush，不每子事件flush。保存失败标记录不完整，游戏可继续。正常summary与会话退出唯一；窗口请求、quit_button、restart、mode_switch、scene_closed等原因分开。强停/Stop无法保证回调：Windows启动时检查现存PID，只对已确认停止的局校验前缀并恢复，原因unknown，不当成主动流失。其它平台/无法确认时保留待确认文件。

本片性能尚未验收：冻结事实的131次普通/20次连锁诊断有明显CPU和IO长尾，不等同60FPS额外帧耗时。保留同步批量，后续先补真实成对帧测再优化。目标能力/救场权重/目标曲线/全能力尝试追踪的capabilities为false，相关未知收益不能填0或用于Excel估值。#17自动回填与#18新批测策略尚未接入。

分析入口见[工具说明](../../tools/telemetry_analysis/README.md)。测试为 tests/rules/test_collection_batches.gd、test_collection_lifecycle.gd、test_telemetry.gd 与 tests/integration/test_telemetry_scene.gd。collection_probe.tscn支持独立受控进程恢复验证，collection_benchmark.tscn输出冻结事实诊断；两者都不是真人样本。
