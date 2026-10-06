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
