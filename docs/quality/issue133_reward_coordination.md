# #133 · 奖励等待与Game协调

本片基于`develop/0.0.3`的`89e05d3`（#164已审查并合并）。实现提交`b92aeae`，输入缓冲回归稳定性提交`550aacb`，审查后的候选前置校验`d86775a`；PR保留作者review，不自动合并、不自动关闭issue。

## 交付边界

| 位置 | 职责与变化 |
| --- | --- |
| RunController / RewardState | 唯一奖励等待、身份、修复次数与continuation；命令重校验，成功消费，重复命令返回原结果 |
| RewardOfferRules / SkillOfferGenerator | 部分失效保留原组；全失效同reward最多成功重建一次，记录替代offer；临时三流冻结成功后才提交；合法1/2张支持，零池及二次失效ERROR |
| Board / BoardRunFlow | 向Game发出reward_requested；按规则步骤恢复，不因closed自行补棋或解锁输入 |
| Game / GameRewardFlow | 等待必要表现、绑定原run/reward/offer和界面代次、提交同ChooseSkillCommand；负责弹窗与暂停生命周期 |
| PopupSkillChoice / HUD | 隔离的冻结目标快照；普通关闭不消费且不自动重开，HUD继续选卡恢复；不可用卡禁用 |
| LevelUpSystem | 退出正式弹窗循环和本局写入口；保留旧道具池初始化/查询与进度只读兼容，剩余兼容迁移属#134 |

规则版本更新为`run-commands-v35-reward-coordination`，快照记录repair_used与替代offer。旧版本记录明确拒绝跨版本回放。本片不实现#160磁盘存档恢复、#161六流生命周期、异形解锁新内容或后续Composite/Resolver迁移；因此不把RW08及L01～L08标为已完成。

## 回归与审查

最终代码`d86775a`完整回归：78脚本、574测试，573通过、1失败，20018/20434断言通过，229.147秒，退出1。唯一失败为#132基线已记录的`test_all_skill_descriptions_fit_card_and_popup_at_base_viewport`，仍为416项卡片操作提示/稀有度包含关系断言；没有新增失败、没有脚本解析错误。完整回归并非全绿，不将该布局问题标为解决。原始输出及逐脚本统计已归档。

新增规则测试覆盖部分/全部失效、第二次全失效、生成失败不提交随机流/身份、零池、1/2张、嵌套目标隔离和成功命令幂等。新增真实场景测试覆盖普通关闭/显式恢复、同局旧回调、无全局暂停时规则门禁、连续奖励四种播放设置，以及卸载Game释放暂停。旧核心循环继续覆盖换局旧回调，目标交互覆盖选色拒绝与返回，阶段/继续挑战、跳过、回放沿现有回归执行。

审查沿状态写入口→规则命令→候选提交→场景回调→退出清理检查。发现并修正选卡时销毁Game留下全局暂停的问题：子Board离树后不能再通过Board取得SceneTree，协调器保存取得暂停时的树引用，并在退出时释放自己的暂停；新增用例先复现失败，修复后通过。

首轮完整回归572项中567通过、5失败：一个#132已知布局失败，另外四项为旧版本断言、弹窗对象共享和空冻结组不重建的旧约定。已更新为显式验证新版本、目标快照隔离及同reward替代链，未删减已知布局断言。第二次完整运行在输入缓冲测试等待随机候选选择时中止；该案例原本盲选第0张并无限等待turn_started，随机选色卡可能需要额外输入。现固定非选色候选、等待表现完成并断言只消费一次，独立6/6通过。最终完整运行结果见证据目录。

最终定向回归：5脚本54/54测试、991断言通过，42.566秒，退出0。输入缓冲6/6、23断言通过，6.532秒，退出0。实际CLI阶段模式seed133000、greedy策略、上限65行动，44行动后满盘结束，714分、成功选卡3次；落盘读回回放OK，独立复放415条记录通过、退出0。该单样本不作为通关或平衡结论。

补充审查将“候选不可用”检查落实到SkillRules提交之前，无UI调用同样受约束；增加过期冻结等级案例，除登记拒绝命令身份外，规则快照/随机/奖励保持。补充规则8/8、54断言通过，0.053秒，退出0，最终完整回归包含此修改。v34归档记录实测返回record_version_mismatch、checked_records=0、退出1，符合拒绝跨版本回放的预期。

机器环境为Godot`4.7.2.stable.official.ed1daf0bf`、Compatibility、GUT9.6.0。测试使用各自APPDATA沙箱，不接触正常玩家配置。原始日志保留系统证书读取错误、受控失败诊断及退出资源提示；不宣称引擎日志零错误。编辑器人工视觉/操作与Web未运行，留给作者review/试玩。

## RW验收映射

| 契约 | 本片证据与限制 |
| --- | --- |
| RW01 / RW02 | 新场景关闭/重开快照、目标隔离及一张确认；既有目标UI与技能池语言切换回归 |
| RW03 / RW04 | 新规则七项 + 连续奖励四播放模式；失败不耗正式随机和身份、成功选择后重置修复机会 |
| RW05 | 新同局旧回调及规则重复命令；旧核心循环换局旧回调 |
| RW06 / RW07 | 现有核心、阶段、继续挑战、无UI规则与精确回放；保留原推进安全点，未扩写中途出生恢复协议 |
| RW08 | 快照字段包含冻结身份和修复状态；完整磁盘保存/恢复由#160验证，未验收 |
| RW09 / RW10 | 四播放模式、旧跳过/重试、Game卸载暂停修复；现有预算/提交后ERROR测试继续执行；未宣称全部未来Composite异常已覆盖 |

## 复现

在实际游戏仓库运行PowerShell；把APPDATA指向独立沙箱。完整测试：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/issue133/reproduce-sandbox'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

定向测试将目录参数替换为`-gtest=res://tests/integration/test_reward_coordination.gd,res://tests/rules/test_reward_waiting_rules.gd,res://tests/test_core_loop.gd,res://tests/integration/test_reward_presentation.gd,res://tests/integration/test_skill_target_ux.gd`。输入缓冲单测使用`-gtest=res://tests/integration/test_input_buffer.gd`。

CLI与独立复放：

```powershell
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- --count=1 --seed=133000 --moves=65 --strategy=greedy --output=res://.godot/issue133/reproduce-bot --record-output=res://.godot/issue133/reproduce-bot/records --telemetry-output=res://.godot/issue133/reproduce-bot/telemetry --commit=b92aeae
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay res://docs/evidence/issue133/bot-record.jsonl
```

原始结果、完整统计与SHA256清单见[证据目录](../evidence/issue133/README.md)。
