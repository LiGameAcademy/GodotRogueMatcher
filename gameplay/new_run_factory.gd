class_name NewRunFactory
extends RefCounted

## Builds an unadopted run before any old checkpoint is invalidated.
static func prepare(rules: BoardRules, stage: StageConfig, source: NewRunSeedSource, candidate: RunController = null, initial: RunStepResult = null, previous_seed: int = -1) -> Dictionary:
	if candidate == null:
		var sampled: Dictionary = source.propose(previous_seed)
		if not sampled.ok: return sampled
		candidate = RunController.new(rules, int(sampled.seed), stage)
	if initial == null: initial = candidate.initialize()
	if not candidate.state.rule_error.is_empty(): return {"ok": false, "reason": "new_run_prepare_failed"}
	return {"ok": true, "reason": "", "run": candidate, "initial": initial}
