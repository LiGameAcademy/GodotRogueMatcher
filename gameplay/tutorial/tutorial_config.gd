class_name TutorialConfig
extends Resource

## 独立练习盘的固定布局；正式局规则和技能参数仍来自运行配置。
@export var dimensions: Vector2i = Vector2i(5, 5)
@export var seed: int = 101
@export var line_color: int = 1
@export var line: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
@export var source: Vector2i = Vector2i(4, 3)
@export var target: Vector2i = Vector2i(4, 2)
@export var spare: Vector2i = Vector2i(0, 4)
@export var refill_target: Vector2i = Vector2i(1, 4)
@export var core: Vector2i = Vector2i(2, 2)
@export var titles: Array[String] = ["移动与五连", "没有消除时会补棋", "得分带来技能", "主动激活特殊棋子"]
@export var instructions: Array[String] = ["点击右下方高亮的绿色方块，再点击它上方的高亮空格。\n横、竖、斜方向同色五连即可消除。", "点击左下角的红色圆棋子，再点击右侧高亮空格。\n这次没有五连，观察真实补入的 3 枚棋子。", "再完成一次绿色五连。累计达到 100 分后，选择一张技能卡。\n正式局会先完成消除与得分演出，再打开技能选择。", "本练习已安装「主动爆破」。双击中间标有「爆」的棋子。\n爆破会清理周围棋子；主动爆破占用一次行动，之后通常会补棋。"]
