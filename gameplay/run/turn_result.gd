class_name TurnResult
extends RefCounted

var removed: Array[PieceState] = []

var move: BoardMoveResult
var matches: Array[MatchResult] = []
var direct_match: bool = false
