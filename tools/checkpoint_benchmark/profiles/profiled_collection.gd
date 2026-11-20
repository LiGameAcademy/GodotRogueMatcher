extends RunCollection

## Times actual collection setup/binding/flush calls; does not replace their implementation.
var profile: Dictionary = {}

func configure(context: String, destination: TelemetryFactory = null, recover_existing: bool = true) -> void:
	var started: int = Time.get_ticks_usec()
	super.configure(context, destination, recover_existing)
	profile["configure_usec"] = Time.get_ticks_usec() - started

func resume(context: String, active: RunController, checkpoint: Dictionary, record_file: bool) -> TelemetryProjector:
	var started: int = Time.get_ticks_usec()
	var result: TelemetryProjector = super.resume(context, active, checkpoint, record_file)
	profile["resume_usec"] = Time.get_ticks_usec() - started
	return result

func bind(value: RunController) -> void:
	var started: int = Time.get_ticks_usec()
	super.bind(value)
	profile["bind_usec"] = int(profile.get("bind_usec", 0)) + Time.get_ticks_usec() - started

func flush(force: bool = true) -> void:
	var started: int = Time.get_ticks_usec()
	super.flush(force)
	profile["flush_usec"] = int(profile.get("flush_usec", 0)) + Time.get_ticks_usec() - started
