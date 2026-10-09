extends GutTest

const GAME: PackedScene = preload("res://gameplay/game.tscn")
var viewport: SubViewport
var game: Node2D
var board: Board
var hud: Hud

func before_each() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	UIManager.close_popup()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_2d = World2D.new()
	add_child_autofree(viewport)
	game = GAME.instantiate() as Node2D
	game.set("persist_preferences", false)
	game.set("record_runs", false)
	game.set("collect_telemetry", false)
	viewport.add_child(game)
	board = game.get_node("Board") as Board
	hud = game.get_node("UILayer/HUD") as Hud
	await board.initialized
	await wait_process_frames(3)

func after_each() -> void:
	get_tree().paused = false
	UIManager.close_popup()
	await wait_process_frames(2)

func test_real_board_edges_fit_ui_area_at_multiple_window_sizes() -> void:
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 640), Vector2i(1600, 720)]:
		viewport.size = resolution
		await wait_process_frames(5)
		var displayed: Rect2 = board.get_global_transform_with_canvas() * board.view.get_display_rect()
		var area: Rect2 = hud.get_board_area()
		assert_true(area.grow(0.1).encloses(displayed), str(resolution))
		assert_almost_eq(displayed.get_center().x, area.get_center().x, 0.1)
		assert_almost_eq(displayed.get_center().y, area.get_center().y, 0.1)
		assert_false(displayed.intersects((hud.get_node("%Left") as Control).get_global_rect()))
		assert_false(displayed.intersects((hud.get_node("%Right") as Control).get_global_rect()))
		assert_false(displayed.intersects((hud.get_node("Margin/Rows/Header") as Control).get_global_rect()))
		assert_false(displayed.intersects((hud.get_node("Margin/Rows/Footer") as Control).get_global_rect()))
		# 直接验证场景中的首尾碰撞格，避免只检查理想化的原点。
		for coordinate: Vector2i in [Vector2i.ZERO, Vector2i(8, 8)]:
			var cell: Cell = board.get_cell(coordinate)
			var physical: Rect2 = cell.get_global_transform_with_canvas() * Rect2(Vector2(-32, -32), Vector2(64, 64))
			assert_true(area.encloses(physical), str(coordinate))
		assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline)

func test_scaled_corner_picking_and_move_use_same_grid_coordinates() -> void:
	viewport.size = Vector2i(1024, 640)
	await wait_process_frames(4)
	await wait_physics_frames(2)
	for coordinate: Vector2i in [Vector2i.ZERO, Vector2i(8, 8)]:
		var cell: Cell = board.get_cell(coordinate)
		var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
		query.position = cell.global_position
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hits: Array[Dictionary] = board.get_world_2d().direct_space_state.intersect_point(query)
		assert_eq(hits.size(), 1)
		if not hits.is_empty(): assert_same(hits[0].collider, cell.area_2d)
	var command: MovePieceCommand = RandomLegalBot.new(19).choose(board.run) as MovePieceCommand
	assert_not_null(command)
	board.selected_piece = board.view.get_piece(command.piece_id)
	assert_true(await board.move_selected_piece(board.get_cell(command.target), 0.01))
	assert_eq(board.rules.state.get_piece(command.piece_id).coordinate, command.target)
	assert_eq(board.view.get_piece(command.piece_id).global_position, board.get_cell(command.target).global_position)

func test_mode_menu_fits_supported_viewport_in_both_languages() -> void:
	var old_locale: String = TranslationServer.get_locale()
	var menu: ReleaseMenu = game.get_node("MenuLayer/ReleaseMenu") as ReleaseMenu
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		menu.open(true, true, false)
		menu.collection_controls.show_status("记录已保存到本机 · 不上传", true, true)
		menu.mode_button.select(0)
		menu.mode_button.item_selected.emit(0)
		await wait_process_frames(3)
		var panel_rect: Rect2 = (menu.get_node("Home/Panel") as Control).get_global_rect()
		assert_true(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(panel_rect), "%s %s" % [locale, panel_rect])
		assert_true(panel_rect.encloses(menu.collection_controls.get_global_rect()), locale)
	TranslationServer.set_locale(old_locale)
	menu.close()

func test_six_piece_preview_fits_panel_at_supported_sizes_in_both_languages() -> void:
	var old_locale: String = TranslationServer.get_locale()
	board.run.state.stage.used_actions = 12
	board.run.prepare_spawn_plan()
	var baseline: String = RunSnapshot.digest(RunSnapshot.capture(board.run))
	for locale: String in ["zh_CN", "en_US"]:
		TranslationServer.set_locale(locale)
		for resolution: Vector2i in [Vector2i(1024, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			viewport.size = resolution
			hud.show_run(board.run)
			await wait_process_frames(5)
			var preview: SpawnPreview = hud.spawn_preview
			var bounds: Rect2 = Rect2(Vector2.ZERO, preview.size)
			assert_eq(preview._tokens.size(), 6)
			# 与实际画出的32像素槽位对应，捕获固定面板只容纳五枚的溢出。
			for index: int in range(6):
				var slot: Rect2 = Rect2(Vector2(2 + index * 36, 21), Vector2(32, 32))
				assert_true(bounds.encloses(slot), "%s %s slot %d" % [locale, resolution, index + 1])
			assert_true(bounds.encloses(preview.title.get_rect()))
			assert_true(bounds.encloses(preview.hint.get_rect()))
			assert_lte(preview.title.get_minimum_size().x, preview.title.size.x)
			assert_lte(preview.hint.get_minimum_size().x, preview.hint.size.x)
			var frame: Control = hud.get_node("Margin/Rows/Header/Progress/PreviewFrame") as Control
			var growth: Control = hud.get_node("Margin/Rows/Header/Progress/GrowthFrame") as Control
			assert_lte(frame.get_global_rect().end.x, growth.get_global_rect().position.x)
			assert_true(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(frame.get_global_rect()), "%s %s preview %s" % [locale, resolution, frame.get_global_rect()])
			assert_true(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(growth.get_global_rect()), "%s %s growth %s" % [locale, resolution, growth.get_global_rect()])
			assert_eq(RunSnapshot.digest(RunSnapshot.capture(board.run)), baseline)
	TranslationServer.set_locale(old_locale)
