class_name CommandCodec
extends RefCounted

static func encode(command: RunCommand) -> Dictionary:
	var result: Dictionary = {"run_id": command.run_id, "command_id": str(command.command_id), "expected_action_id": str(command.expected_action_id), "source": command.source, "buffered": command.buffered, "buffered_wait_ms": str(command.buffered_wait_ms)}
	if command is MovePieceCommand:
		var move: MovePieceCommand = command as MovePieceCommand
		result.merge({"type": "move", "piece_id": str(move.piece_id), "target": [str(move.target.x), str(move.target.y)]})
	elif command is ChooseSkillCommand:
		var choice: ChooseSkillCommand = command as ChooseSkillCommand
		result.merge({"type": "choose", "offer_id": str(choice.offer_id), "reward_id": str(choice.reward_id), "skill_id": String(choice.skill_id)})
	else: result["type"] = "unknown"
	return result

static func valid_integer(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(value.to_int()) == value

static func decode(data: Dictionary) -> RunCommand:
	for key: String in ["command_id", "expected_action_id", "buffered_wait_ms"]:
		if not valid_integer(data.get(key)): return null
	if not data.get("run_id") is String or not data.get("source") is String or not data.get("buffered") is bool: return null
	var command: RunCommand
	match data.get("type"):
		"move":
			var target: Variant = data.get("target")
			if not valid_integer(data.get("piece_id")) or not target is Array or target.size() != 2: return null
			if not valid_integer(target[0]) or not valid_integer(target[1]): return null
			for coordinate: String in target:
				if coordinate.to_int() < -1000000 or coordinate.to_int() > 1000000: return null
			var move: MovePieceCommand = MovePieceCommand.new()
			move.piece_id = data.piece_id.to_int()
			move.target = Vector2i(target[0].to_int(), target[1].to_int())
			command = move
		"choose":
			if not valid_integer(data.get("offer_id")) or not valid_integer(data.get("reward_id")) or not data.get("skill_id") is String: return null
			var choice: ChooseSkillCommand = ChooseSkillCommand.new()
			choice.offer_id = data.offer_id.to_int()
			choice.reward_id = data.reward_id.to_int()
			choice.skill_id = StringName(data.skill_id)
			command = choice
		_: return null
	command.run_id = data.run_id
	command.command_id = data.command_id.to_int()
	command.expected_action_id = data.expected_action_id.to_int()
	command.source = data.source
	command.buffered = data.buffered
	command.buffered_wait_ms = data.buffered_wait_ms.to_int()
	if command.command_id <= 0 or command.expected_action_id < 0 or command.buffered_wait_ms < 0: return null
	return command
