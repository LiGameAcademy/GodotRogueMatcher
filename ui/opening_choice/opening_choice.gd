extends ConfirmationDialog

## Presents one provisional opening selection before a new stage run is prepared.
signal decided(opening: StringName)

@onready var _line: CheckBox = $Options/RowSweep
@onready var _standard: CheckBox = $Options/Standard
@onready var _details: Label = $Options/Details

func _ready() -> void:
	confirmed.connect(func() -> void: decided.emit(&"row_sweep" if _line.button_pressed else &"standard"))
	canceled.connect(func() -> void: decided.emit(&""))

func choose(unlocked: bool, selected: StringName = &"standard") -> StringName:
	if unlocked and selected == &"row_sweep": _line.button_pressed = true
	else: _standard.button_pressed = true
	_line.disabled = not unlocked
	_details.text = tr("opening.description" if unlocked else "opening.requirements")
	popup_centered()
	return await decided
