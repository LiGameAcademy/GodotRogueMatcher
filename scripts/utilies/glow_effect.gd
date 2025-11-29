## 赛博辉光效果工具类
## 用于在场景中设置全局辉光效果

extends Node

## 创建全局辉光效果
## 需要在场景根节点添加 WorldEnvironment 节点
static func setup_glow_effect(world_env: WorldEnvironment) -> void:
	if not world_env:
		push_error("WorldEnvironment 节点不存在")
		return
	
	var env = Environment.new()
	
	# 启用辉光
	env.glow_enabled = true
	env.glow_levels = [0.0, 0.5, 1.0, 1.5, 2.0]  # 5级辉光强度
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
	
	world_env.environment = env

## 为节点添加局部辉光效果（使用 CanvasModulate 或自定义 Shader）
static func add_node_glow(node: Node2D, color: Color, intensity: float = 1.0) -> void:
	# 使用 modulate 属性增强颜色
	node.modulate = color * intensity
	
	# 如果节点有 modulate 属性，可以通过 Shader 实现更复杂的辉光
	# 这里使用简单的 modulate 方法
