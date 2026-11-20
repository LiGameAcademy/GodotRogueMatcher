extends BoardView

## Test-only wrappers; node creation and resource behavior remain in the production view.
var profile: Dictionary = {}

func configure(columns: int, rows: int, cell_size: Vector2, gap: Vector2) -> void:
	var started: int = Time.get_ticks_usec()
	super.configure(columns, rows, cell_size, gap)
	profile["configure_usec"] = Time.get_ticks_usec() - started

func rebuild(snapshot: Array[PieceState]) -> void:
	var started: int = Time.get_ticks_usec()
	super.rebuild(snapshot)
	profile["rebuild_usec"] = Time.get_ticks_usec() - started

func refresh_piece_details(snapshot: Array[PieceState], explosion: ExplosionState, config: ExplosionConfig, line_clear: LineClearState = null, manual_uses_used: Dictionary[StringName, int] = {}) -> void:
	var started: int = Time.get_ticks_usec()
	super.refresh_piece_details(snapshot, explosion, config, line_clear, manual_uses_used)
	profile["details_usec"] = int(profile.get("details_usec", 0)) + Time.get_ticks_usec() - started

func apply_game_theme(preset: GameTheme) -> void:
	var started: int = Time.get_ticks_usec()
	super.apply_game_theme(preset)
	profile["theme_usec"] = Time.get_ticks_usec() - started
