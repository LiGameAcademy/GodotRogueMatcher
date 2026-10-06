class_name PlaybackPlanBuilder
extends RefCounted

## 入队前复制规则结果；播放期间不再读取活棋盘或随机状态。
static func move(result: BoardMoveResult, duration: float) -> Array[PresentationStep]:
	var step: PresentationStep = PresentationStep.new()
	step.kind = PresentationStep.Kind.MOVE
	step.duration = maxf(0.0, duration)
	step.movement = BoardMoveResult.new()
	step.movement.piece_id = result.piece_id
	step.movement.failure = result.failure
	step.movement.path = result.path.duplicate()
	return [step]

static func matches(results: Array[MatchResult]) -> Array[PresentationStep]:
	var steps: Array[PresentationStep] = []
	for result: MatchResult in results:
		# 同代同时显示；下一代只在本代必需动画完成后派发。
		if steps.is_empty() or steps.back().matches.back().generation != result.generation:
			steps.append(PresentationStep.new())
		var frozen: MatchResult = MatchResult.new()
		frozen.cause = result.cause
		frozen.source_id = result.source_id
		frozen.center = result.center
		frozen.radius = result.radius
		frozen.generation = result.generation
		frozen.score_entry = result.score_entry.copy()
		for piece: PieceState in result.removed: frozen.removed.append(piece.copy())
		steps.back().matches.append(frozen)
	return steps

static func spawns(results: Array[SpawnResult], duration: float) -> Array[PresentationStep]:
	var steps: Array[PresentationStep] = []
	for result: SpawnResult in results:
		var step: PresentationStep = PresentationStep.new()
		step.kind = PresentationStep.Kind.SPAWN
		step.duration = maxf(0.0, duration)
		step.pieces.append(result.piece.copy())
		steps.append(step)
		steps.append_array(matches(result.matches))
	return steps

static func skill(result: SkillApplyResult, duration: float) -> Array[PresentationStep]:
	var steps: Array[PresentationStep] = []
	for piece: PieceState in result.created:
		var step: PresentationStep = PresentationStep.new()
		step.kind = PresentationStep.Kind.SPAWN
		step.duration = maxf(0.0, duration)
		step.pieces.append(piece.copy())
		steps.append(step)
	if not result.removed.is_empty():
		var step: PresentationStep = PresentationStep.new()
		step.kind = PresentationStep.Kind.REMOVE
		for piece: PieceState in result.removed: step.pieces.append(piece.copy())
		steps.append(step)
	steps.append_array(matches(result.matches))
	return steps
