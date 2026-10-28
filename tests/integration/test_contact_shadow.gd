extends GutTest

## Verifies static body-alpha shadows consume theme configuration without rule writes.
const PIECE: PackedScene = preload("res://gameplay/board/piece/chess_piece.tscn")
var _first: ChessPiece
var _second: ChessPiece

func before_each() -> void:
	_first = PIECE.instantiate() as ChessPiece
	_second = PIECE.instantiate() as ChessPiece
	add_child_autofree(_first)
	add_child_autofree(_second)
	_first.apply_game_theme(GameThemes.ALL[0].board)
	_second.apply_game_theme(GameThemes.ALL[0].board)

func _shadow(piece: ChessPiece) -> Sprite2D:
	var shadow: Sprite2D = piece.get_node_or_null("ContactShadow") as Sprite2D
	assert_not_null(shadow, "Nut body must consume the existing contact-shadow palette")
	return shadow

func test_all_five_bodies_use_their_own_alpha_without_face_textures() -> void:
	var shadow: Sprite2D = _shadow(_first)
	if shadow == null: return
	for index: int in range(5):
		_first.piece_type = index
		assert_same(shadow.texture, NutVisual.BODIES[index])
		assert_true(shadow.visible)
		assert_eq(shadow.position, GameThemes.ALL[0].board.shadow_offset)
		assert_eq((shadow.material as ShaderMaterial).get_shader_parameter("shadow_color"), GameThemes.ALL[0].board.piece_shadow)

func test_theme_and_material_are_instance_local_and_template_stays_unchanged() -> void:
	var first: Sprite2D = _shadow(_first)
	var second: Sprite2D = _shadow(_second)
	if first == null or second == null: return
	var template: ChessPiece = PIECE.instantiate() as ChessPiece
	autofree(template)
	var original: ShaderMaterial = (template.get_node("ContactShadow") as Sprite2D).material as ShaderMaterial
	var initial: Variant = original.get_shader_parameter("shadow_color")
	assert_ne(first.material, second.material)
	assert_ne(first.material, original)
	_first.apply_game_theme(GameThemes.ALL[1].board)
	assert_eq(first.position, GameThemes.ALL[1].board.shadow_offset)
	assert_eq(second.position, GameThemes.ALL[0].board.shadow_offset)
	assert_eq((second.material as ShaderMaterial).get_shader_parameter("shadow_color"), GameThemes.ALL[0].board.piece_shadow)
	assert_eq(original.get_shader_parameter("shadow_color"), initial)

func test_low_effects_and_selection_keep_static_shadow_without_changing_hit_bounds() -> void:
	var shadow: Sprite2D = _shadow(_first)
	if shadow == null: return
	var bounds: Rect2 = _first.tooltip_region.get_rect()
	var offset: Vector2 = shadow.position
	_first.set_low_effects(true)
	_first.selected()
	await wait_process_frames(10)
	assert_true(shadow.visible)
	assert_eq(shadow.position, offset)
	assert_eq(_first.tooltip_region.get_rect(), bounds)
	assert_same(shadow.texture, NutVisual.BODIES[0])

func test_zero_alpha_is_an_explicit_off_state_and_does_not_mutate_shared_palette() -> void:
	var shadow: Sprite2D = _shadow(_first)
	if shadow == null: return
	var appearance: BoardAppearance = GameThemes.ALL[0].board.duplicate() as BoardAppearance
	appearance.piece_shadow.a = 0.0
	_first.apply_game_theme(appearance)
	assert_eq((shadow.material as ShaderMaterial).get_shader_parameter("shadow_color").a, 0.0)
	assert_gt(GameThemes.ALL[0].board.piece_shadow.a, 0.0)
	assert_gt(((_second.get_node("ContactShadow") as Sprite2D).material as ShaderMaterial).get_shader_parameter("shadow_color").a, 0.0)

func test_item_roundtrip_hides_old_shadow_and_ghost_keeps_parent_opacity() -> void:
	var shadow: Sprite2D = _shadow(_first)
	if shadow == null: return
	var item: ItemData = ItemData.new()
	item.icon = NutVisual.BODIES[1]
	_first.initialize_item(item)
	assert_false(shadow.visible)
	_first.item_data = null
	_first.update_visual()
	assert_true(shadow.visible)
	_first.is_ghost = true
	_first.reset()
	assert_eq(_first.modulate.a, 0.5)
	assert_same(shadow.get_parent(), _first)

func test_real_game_theme_and_four_mode_changes_preserve_run_snapshot() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var game: Node2D = preload("res://gameplay/game.tscn").instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	game.set("show_start_menu", false)
	add_child_autofree(game)
	var board: Board = game.get_node("Board") as Board
	await board.initialized
	var before: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	for fast: bool in [false, true]:
		game.call("_set_fast", fast, false)
		for reduced: bool in [false, true]:
			game.call("_set_low_effects", reduced, false)
			for preset: GameTheme in GameThemes.ALL:
				game.call("_set_theme", preset.theme_id, false)
				assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), before)
				var state: PieceState = board.rules.state.get_snapshot()[0]
				var shadow: Sprite2D = board.view.get_piece(state.piece_id).get_node("ContactShadow") as Sprite2D
				assert_eq(shadow.position, preset.board.shadow_offset)
				assert_true(shadow.visible)
