class_name PresentationStep
extends RefCounted

enum Kind { MOVE, SPAWN, REMOVE, MATCHES, ALIGN }
enum Policy { SKIPPABLE, COMPLETE_REQUIRED, FIXED_REQUIRED }
var kind: Kind = Kind.MATCHES
var policy: Policy = Policy.SKIPPABLE
var movement: BoardMoveResult
var duration: float = 0.0
var pieces: Array[PieceState] = []
var matches: Array[MatchResult] = []
