extends RefCounted

## Debug-only scene commands; never used as a production checkpoint or balance sample.
static func handle(board: Board, hud: Hud, event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo: return
	match key.physical_keycode:
		KEY_F6: await board.load_explosion_demo()
		KEY_F7: board.open_skill_demo()
		KEY_F10:
			if await board.load_explosion_demo("fixture_dye"): hud.show_status("hud.status.demo_dye")
		KEY_F11:
			var mode: String = "fixture_manual_limit" if key.alt_pressed else ("fixture_line_score" if key.shift_pressed and key.ctrl_pressed else ("fixture_line_cross" if key.ctrl_pressed else ("fixture_line_span" if key.shift_pressed else "fixture_line")))
			if await board.load_explosion_demo(mode):
				var id: StringName = &"demo_limit" if key.alt_pressed else (&"demo_score" if key.shift_pressed and key.ctrl_pressed else (&"demo_cross" if key.ctrl_pressed else (&"demo_span" if key.shift_pressed else &"demo_line")))
				hud.show_status(StringName("hud.status." + String(id)))
		KEY_F12:
			if await board.load_explosion_demo("fixture_transform"):
				hud.show_status("hud.status.demo_transform")
				var active: RunController = board.run
				board.can_selected = false
				await BoardRunFlow.continue_run(board, active)
				if board.run == active: board.can_selected = not board.hold_at_checkpoint and not active.state.is_game_over and active.state.rule_error.is_empty()
