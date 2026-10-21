# #118 真实解锁、立即扫描及空盘恢复证据

2026-10-21。基线 be0b01e（#171 复审后合并）。主体实现与完整回归代码 86e48965a419c536c7cff599cd37707951a966c6；最终代码 59152450fec1cee877cc27c71d51aa963cc33af8 只收紧测试初始化白名单，随后复验相关回放/场景入口。Godot 4.7.2、Compatibility、GUT 9.6.0，APPDATA/LOCALAPPDATA 隔离于 .godot/issue118-unlock；完整集固定 60fps，场景使用正常字体驱动。

## 最终通过

- full-output.log：94 脚本、687/687、23389 断言、212.346 秒，退出 0；无 SCRIPT ERROR/Parse Error 或 ObjectDB/Resource 泄漏提示。新增 30 项：25 项规则和 5 项真实场景。
- final-whitelist-scene.log：最终白名单收口后，2 脚本、7/7、74 断言、退出 0。覆盖坏模式名拒绝、解锁/恢复回放、四模式弹窗及恢复演出中重试；本次没有把它冒称第二次完整集。
- continuous-rewards.log：恢复专项 10/10、140 断言。显式 200 分夹具和实际恢复匹配跨越 100/250，两个真实 ChooseSkillCommand 均保留 batch 1；最终夹具清盘后诊断停止，仍为 3 枚出生，不再启动第二批。
- rules3.log / rules4.log：恢复独立 root 与连锁收束、固定失效/动态选择、阶段新行动和通关继续等逐步收口。
- scene2.log：普通、快放、低特效、组合及恢复中重试通过。最终相同场景在完整集和白名单专项再次运行。
- import-final.log：编辑器解析/导入通过，新增脚本 UID 由引擎生成。

## 真实记录与版本

规则 run-commands-v42-shape-unlock-recovery。unlock-record.jsonl 为最终代码专项中实际写盘的 13 条记录，独立 CLI 重放见 unlock-replay.log，success=true、checked_records=13、退出 0；含真实发牌/解锁、50 分立即匹配、一次恢复及输入返回，支持安全命令前缀重建。

bot-record.jsonl / bot-output.log：新 v42 正式直线基线，seed 133000、greedy、上限 65；714 分、44 行动、415 条落盘精确重放成功，退出 0。未启用解锁验收 profile，不是形状平衡样本。

v41-rejection.log：对 #136 的实际 v41 记录验证，明确 record_version_mismatch；引擎预期退出 1，未当成成功回放或意外测试失败。旧版本不能精确重算，未实现通用续局存档。

## 保留的失败与夹具边界

recovery-budget-red.log 是行为失败：9 项中 1 项失败，错误地第二次恢复（batch 2、6 枚出生）。修复使过程预算一直保留到真正输入边界，rules4.log 与 continuous-rewards.log 为对应 GREEN。

lifecycle1.log 保留初始类加载循环；lifecycle5.log 保留把拒选历史系数误当形状亲和的夹具期望；rules2.log 保留未通过真实阶段结算就伪造继续条件的夹具失败及闭包持有导致的退出泄漏；scene1.log 保留场景夹具的错误信号签名/不存在方法。均已修复，最终集未降低正式资格、前置或错误门槛。

R06/R07/R08 的最终清盘、首枚出生前锚点、注入 200 分是显式定向夹具；真实逐枚出生/匹配/爆破/奖励/命令仍走规则路径。不得将其当成自然出现率或真人体验；没有声称故障与四模式的全部组合均已覆盖。

script-results.json、line-counts.json 和 summary.json 可复核逐脚本与两个代码版本的执行范围；331 个自有 gd 文件最高 474 行。manifest.json 保存原始证据 SHA256。职责和遗留边界见 ../../quality/issue118_shape_unlock_recovery.md。
