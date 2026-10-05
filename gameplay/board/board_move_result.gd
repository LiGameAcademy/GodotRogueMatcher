class_name BoardMoveResult
extends RefCounted

enum Failure { NONE, INVALID_PIECE, OUT_OF_BOUNDS, SAME_CELL, TARGET_OCCUPIED, NO_PATH, BUSY }

var failure: Failure = Failure.NONE
var piece_id: int = 0
var path: Array[Vector2i] = []

func is_valid() -> bool:
	return failure == Failure.NONE
