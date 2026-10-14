extends Node

@onready var ui: GrowthChoiceUI = $GrowthChoiceUI

func _ready() -> void:
	ui.choice_confirmed.connect(func(id: StringName): print("Growth choice UI preview confirmed: ", id))
	ui.cancelled.connect(func(): print("Growth choice UI preview cancelled"))
	ui.present_choices.call_deferred(ui.preview_options)
