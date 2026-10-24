class_name ScreeningWindow
extends RefCounted

## Pure observation policy. An in-flight action/reward must reach a safe boundary.
static func reason(run: RunController, settings: ScreeningConfig, fixed: bool, elapsed_ms: int, ready: bool) -> String:
	if not run.state.rule_error.is_empty(): return "rule_error"
	if run.state.is_game_over: return "natural_end"
	if not ready: return ""
	var actions: int = run.state.valid_moves + run.state.activations
	if fixed: return "fixed_complete" if actions >= 1 else ""
	if elapsed_ms >= settings.time_limit_seconds * 1000: return "time_limit"
	if actions >= settings.action_limit: return "action_limit"
	return ""
