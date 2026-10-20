class_name DemolitionStatEffect
extends ChoiceEffect

## Bumps ExplosionState demolition stats (radius / reward / multiplier / match / blast extra).
enum Stat { RADIUS, REWARD, MULTIPLIER, MATCH_EXTRA, BLAST_EXTRA }

@export var stat: Stat = Stat.RADIUS

func rejection(context: ChoiceEffectContext) -> String:
	if stat in [Stat.RADIUS, Stat.REWARD, Stat.BLAST_EXTRA] and not context.explosion_unlocked:
		return "尚未解锁爆炸"
	return ""

func freeze(context: ChoiceEffectContext, _random: RandomNumberGenerator) -> SkillTarget:
	var target: SkillTarget = SkillTarget.new()
	target.value_before = _level(context)
	target.value_after = target.value_before + 1
	return target

func build(context: ChoiceEffectContext, target: SkillTarget) -> ChoiceEffectRequest:
	var request: ChoiceEffectRequest = ChoiceEffectRequest.new()
	request.kind = ChoiceEffectRequest.Kind.DEMOLITION_STAT
	request.stat = stat
	if _level(context) != target.value_before or target.value_after != target.value_before + 1:
		request.error = "升级目标已失效"
	return request

func _level(context: ChoiceEffectContext) -> int:
	match stat:
		Stat.RADIUS: return context.radius_level
		Stat.REWARD: return context.reward_level
		Stat.MULTIPLIER: return context.multiplier_level
		Stat.MATCH_EXTRA: return context.match_extra_level
		Stat.BLAST_EXTRA: return context.blast_extra_level
	return 0
