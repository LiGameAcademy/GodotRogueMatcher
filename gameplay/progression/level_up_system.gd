extends Node

## 升级系统（单例）
## 进度只读兼容查询；旧道具注册/抽取已退出，正式奖励由本局和Game处理。



## 当前等级
var current_level: int:
	get: return GameManager.run.state.progression.level
var pending_rewards: int:
	get:
		return GameManager.run.state.pending_rewards

## 下一个里程碑分数
var next_milestone: int:
	get: return GameManager.run.state.progression.next_milestone

const CONFIG: ProgressionConfig = preload("res://gameplay/progression/content/progression_config.tres")
var previous_milestone: int:
	get: return GameManager.run.state.progression.previous_milestone

## 获取当前等级
## [return: int] 当前等级
func get_current_level() -> int:
	return current_level

## 获取下一个里程碑
## [return: int] 下一个里程碑分数
func get_next_milestone() -> int:
	return next_milestone

## 获取升级进度（0.0 - 1.0）
## [param current_score: int] 当前分数
## [return: float] 升级进度
func get_level_progress(current_score: int) -> float:
	var progress: float = float(current_score - previous_milestone) / float(next_milestone - previous_milestone)
	return clamp(progress, 0.0, 1.0)
