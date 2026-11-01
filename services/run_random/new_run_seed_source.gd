class_name NewRunSeedSource
extends RefCounted

## Application-only entropy. Preparing a seed never advances gameplay RNGs or commits identity.
const MAX_SEED: int = 9223372036854775807
const WEB_BYTES: String = "(()=>{try{const c=globalThis.crypto;if(!c||typeof c.getRandomValues!=='function')return null;return c.getRandomValues(new Uint8Array(8)).buffer;}catch(e){return null;}})()"
var entropy_provider: Callable
var _crypto: Crypto
var _last_started: int = -1

func propose(previous_seed: int = -1) -> Dictionary:
	var sampled: Variant = entropy_provider.call() if entropy_provider.is_valid() else _platform_bytes()
	if not sampled is PackedByteArray or sampled.size() != 8:
		return {"ok": false, "reason": "new_run_entropy_failed"}
	var bytes: PackedByteArray = sampled
	var seed_value: int = int(bytes[0]) & 0x7f
	for index: int in range(1, 8): seed_value = (seed_value << 8) | int(bytes[index])
	var previous: int = _last_started if _last_started >= 0 else previous_seed
	if seed_value == previous: seed_value = 0 if seed_value == MAX_SEED else seed_value + 1
	return {"ok": true, "reason": "", "seed": seed_value}

## Called only after actual adoption; cancelled or failed candidates must not call this.
func remember(seed_value: int) -> void:
	assert(seed_value >= 0)
	_last_started = seed_value

func last_started() -> int:
	return _last_started

func _platform_bytes() -> PackedByteArray:
	if OS.has_feature("web"):
		var result: Variant = JavaScriptBridge.eval(WEB_BYTES, true)
		return result if result is PackedByteArray else PackedByteArray()
	if _crypto == null: _crypto = Crypto.new()
	return _crypto.generate_random_bytes(8) if _crypto != null else PackedByteArray()
