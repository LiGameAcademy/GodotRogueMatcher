class_name RunConfig
extends Resource

## 普通开局的生成数量；回合补棋仍由已有批次规则处理。
@export_range(1, 81, 1) var initial_piece_count: int = 5
