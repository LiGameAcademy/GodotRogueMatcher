class_name PresentationStep
extends RefCounted

enum Kind { MOVE, SPAWN, REMOVE, MATCHES }
var kind: Kind = Kind.MATCHES
var movement: BoardMoveResult
var duration: float = 0.0
var pieces: Array[PieceState] = []
var matches: Array[MatchResult] = []
