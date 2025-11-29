extends Node2D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var board: Board = $Board

## 道具资源目录路径
const ITEM_DIRECTORY: String = "res://data/item/"

func _ready() -> void:
	# 注册所有道具（游戏开始前）
	register_all_items()
	GameManager.score_changed.connect(
		func(new_score : float): %ScoreLabel.text = "分数：" + str(new_score)
	)
	# 设置赛博辉光效果
	if world_environment:
		setup_glow_effect(world_environment)

## 注册所有道具到 LevelUpSystem
func register_all_items() -> void:
	LevelUpSystem.load_items_from_directory(ITEM_DIRECTORY)

## 设置赛博辉光效果（直接实现，避免 Autoload 依赖）
func setup_glow_effect(world_env_node: WorldEnvironment) -> void:
	if not world_env_node:
		push_error("WorldEnvironment 节点不存在")
		return
	
	var env = Environment.new()
	
	# 启用辉光
	env.glow_enabled = true
	# 5级辉光强度
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.5)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.5)
	env.set_glow_level(4, 2.0)
	env.glow_normalized = true
	env.glow_intensity = 0.8  # 辉光强度
	env.glow_strength = 1.2  # 辉光强度倍数
	env.glow_mix = 0.5  # 混合模式
	env.glow_bloom = 0.3  # 泛光效果
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT  # 混合模式：柔光
	
	# 设置色调映射（增强赛博感）
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	
	# 设置环境光（暗黑风格）
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.1, 0.15, 1.0)  # 深蓝灰色
	env.ambient_light_energy = 0.3
	
	world_env_node.environment = env
