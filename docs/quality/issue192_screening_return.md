# #192 测试工具返回选择避让

2026-10-29。base `9589563051f845e2c710f9522f4deed76307a265`；受测源码SHA-256、锁定依赖、四样本config_hash见[manifest](../evidence/issue192/manifest.json)。技术修复候选已验证，作者review与真人实机接受待完成；不自动关闭Issue或合并。

## 变化与边界

`ScreeningPlayground`每帧在loading/board提前返回之前读取有效选卡弹窗的公开viewing_board状态，仅隐藏Tools/Panel；返回、关闭/销毁弹窗时恢复，load_fixture开始显式show。节点继续PROCESS_MODE_ALWAYS，墙钟/记录/停止检查保持运行。生产UIManager、PopupSkillChoice、随机/回放协议、正式池均未修改。

1024×640原Panel仍覆盖“查看棋盘”按钮左部；自动鼠标点击其右侧95%位置进入查看，返回按钮则点击中心。返回完整可见且可点已验证，不能据此宣称全部工具布局无遮挡。该入口局限在试玩说明明确告知，作者可据此决定正式准备工具是否接受；未扩成通用浮窗或生产布局修改。

## R1～R6证据

| 条件 | 当前证据与限制 |
| --- | --- |
| R1 | 真实OpenGL渲染，Input.parse_input_event派发motion/left press/release，经GUI命中路由进入/返回；没有调用返回方法或使用Return键。截图view/returned各四份，见证据目录。属于automated/retest，真人接受null。 |
| R2 | 1280×720、1024×640各普通/低特效；1280普通查看期间切至1024再返回1280，Panel保持隐藏且返回按钮在viewport内。系统缩放未独立测量，manifest为null，不宣称任意DPI/设备。 |
| R3 | 选择后查看/返回，完整RunSnapshot与offer_data逐字相等，覆盖run/reward/offer、顺序/冻结目标及当前四RNG状态；确认文字/可确认状态保留，计时增长。 |
| R4 | 四份独立JSONL+sidecar：126分、只余远绿、无普通出生；SkillAcquired=1、consumed=choices=1、pending=0、offer空、continuation=idle、规则/记录错误空、fixed_complete；各文件RuleReplay精确回放通过。此题无剩余普通出生义务。 |
| R5 | 返回后鼠标点击Reset生成新局；销毁弹窗/隐藏期间程序化切题与初始化恢复有新增用例；原playground测试覆盖配置选择、菜单重试、奖励等待切题和旧局隔离，相关选卡/协调/布局回归通过。 |
| R6 | 四份最终GUI样本保留原字节，participant/predictions/selection_decision均null，外部manifest标automated/retest；原f90a39f作者六题未修改。日志、图像、源码及证据hash独立归档。 |

## 验证与复审

- Godot 4.7.2 `ed1daf0bf`、GUT9.6；依赖 `4ba6dda22ef8fad2e9864438073306adf0747c17`。
- 新增GUI专项：2/2、156断言、退出0，[日志](../evidence/issue192/gui.log)。截图中的右侧GUT运行面板是测试器界面，不是生产工具层；未处理/裁剪原图。
- 相关4脚本screening_playground / skill_card_selection / reward_coordination / choice_visual_layout：29/29、1008断言、退出0，[日志](../evidence/issue192/regression.log)。保留29条Float/Int比较警告。两次启动均有证书仓读取诊断；无脚本解析错误、退出资源保留诊断。未跑整库。
- 初轮headless/GUI各1/2失败、118/124断言：1024点击View中心被原工具截获。保留两份初轮日志；改为露出区域真实鼠标后最终通过。未以键盘绕行掩盖失败。
- 独立code-reviewer两次只读复审无阻断；最终复核含补齐的单次取得/消费与封存断言、试玩说明。不是GitHub批准或远端CI。
- 代码行数修改前playground148行，修改后156行；新增测试163行；git diff --check通过。

本轮投入未可靠计量主动工时，不按测试墙钟扣预算。正式参与者、时段和设备待作者安排；复用既有空白表与汇总工具，不联系真人、不填预测或保留名单。

## O1整合依赖

本批基于旧v43协议及当前四RNG，不能冒充O1六流新协议验收。O1先合并时按实际差异更新本分支并重跑受影响的GUI/封存/回放，保留旧样本与版本，不改旧日志重算。O1独占的reader/annotations/CLI及新synthetic支持文件均未编辑。

## 作者复验入口

运行本分支的`tools/screening_playground/screening_playground.tscn`，选直线＋T、固定题3；将第4行2列移至第3行2列。奖励选唯一留白，查看棋盘，再用鼠标点返回选择；检查面板恢复和选中保留，再确认一次。1024宽进入查看需点按钮右侧露出部分。普通/低特效、两尺寸的作者结果仍待记录；本轮不会将自动结果计入正式非设计者筛选。
