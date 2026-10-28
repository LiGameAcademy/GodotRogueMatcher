class_name SkillMarkResult
extends RefCounted

## Committed fuse identities and geometry, inserted after this many acquire match results.
## Data only: no live board lookup or presentation dependency.
var after_match_count: int = 0
var pieces: Array[PieceState] = []
