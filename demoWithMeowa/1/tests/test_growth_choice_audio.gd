extends SceneTree
## Event/stream checks only; no audio audition, rendering or player settings writes.
var checks := 0
var failures := 0
var cues: Array[StringName] = []
var ui: GrowthChoiceUI

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func expect(expected: Array, label: String) -> void:
	check(cues == expected, label + " (received " + str(cues) + ")")
	cues.clear()

func option(id: StringName, epic := false, enabled := true) -> GrowthChoiceOption:
	var value := GrowthChoiceOption.new()
	value.id = id
	value.epic = epic
	value.enabled = enabled
	return value

func motion(button: BaseButton) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2.ONE
	button.gui_input.emit(event)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	ui._input(event)

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	ui = load("res://scenes/ui/growth_choice_ui.tscn").instantiate()
	ui.ink_style = true
	ui.open_duration = 0.0
	ui.hover_duration = 0.0
	ui.get_node("UIAudio").sounds = load("res://data/audio/ui_sounds.tres").duplicate() as UISoundBank
	ui.get_node("UIAudio").repeat_interval = 0.0
	root.add_child(ui)
	ui._audio.cue_played.connect(func(cue: StringName): cues.append(cue))
	await process_frame
	expect([], "Construction is silent")
	var cards: Array[GrowthChoiceOption] = [option(&"ordinary"), option(&"epic", true), option(&"locked", false, false)]
	ui._audio.sounds.actions[&"open"] = &"page_turn"
	check(ui.present_choices(cards), "Actual shared choice component opens")
	expect([&"page_turn"], "Opening uses the current semantic UI sound mapping")
	ui._cards[0].mouse_entered.emit()
	expect([], "Appearing beneath a stationary pointer does not produce navigation audio")
	motion(ui._cards[0])
	expect([&"select"], "Pointer movement onto an ordinary card uses navigation feedback")
	check(ui.selected_index == -1 and ui._confirm.disabled, "Hover does not choose or confirm a reward")
	motion(ui._cards[0])
	expect([], "Motion within one card does not repeat hover feedback")
	ui._cards[0].mouse_exited.emit()
	motion(ui._cards[0])
	expect([&"select"], "A deliberate return to the same card gives one new navigation cue")
	ui._cards[0].mouse_exited.emit()
	motion(ui._cards[1])
	expect([&"select"], "Epic cards use the same shared navigation channel")
	motion(ui._cards[2])
	motion(ui._confirm)
	expect([], "Unavailable rewards and disabled confirmation stay silent")
	ui._audio.sounds.actions[&"choice"] = &"equip"
	ui._cards[1].pressed.emit()
	expect([&"equip"], "Card clicks use semantic choice and do not add a generic button confirmation")
	ui._cards[1].pressed.emit()
	expect([], "Clicking the already selected card is silent")
	key(KEY_1)
	expect([&"equip"], "Number selection uses the same action as a card click")
	key(KEY_RIGHT)
	expect([&"equip"], "Directional selection uses the same action and skips unavailable cards")
	motion(ui._confirm)
	expect([&"select"], "Enabled confirmation gets one hover cue")
	ui._confirm.pressed.emit()
	expect([&"confirm"], "Mouse confirmation produces exactly one result cue")
	ui.confirm_selection()
	motion(ui._cards[1])
	expect([], "Closed choices do not play interaction sounds")
	ui._audio.sounds.actions[&"open"] = &"journal_open"
	ui._audio.sounds.actions[&"choice"] = &"select"
	ui.present_choices(cards)
	cues.clear()
	ui.set_draw_status(3, true)
	ui._reroll.mouse_entered.emit()
	expect([], "Programmatic availability changes are silent")
	motion(ui._reroll)
	expect([&"select"], "An enabled redraw button has navigation feedback")
	var redrawn: Array[bool] = []
	ui.cards_redrawn.connect(func(): redrawn.append(true))
	ui.reroll_requested.connect(func(): ui.present_choices([cards[1], cards[0]]))
	ui._reroll.pressed.emit()
	expect([], "Successful redraw does not reopen the screen or add generic button confirmation")
	check(redrawn.size() == 1 and ui.selected_index == -1, "The existing success event and explicit choice requirement remain")
	ui.set_draw_status(0, false)
	ui.request_reroll()
	check(redrawn.size() == 1, "Unavailable redraw does not emit success")
	expect([], "Unavailable redraw stays silent")
	ui._audio.sounds.actions[&"close"] = &"journal_close"
	key(KEY_ESCAPE)
	expect([&"journal_close"], "Esc cancellation uses the shared close mapping")
	ui.open_duration = 0.3
	ui.present_choices(cards)
	cues.clear()
	motion(ui._cards[0])
	ui.select_option(&"ordinary")
	expect([], "Dealing cards cannot play navigation or selection sounds")
	ui.reveal_now()
	ui.select_option(&"ordinary")
	expect([&"select"], "Reveal resumes the original input/audio lifecycle")
	ui._audio.enabled = false
	ui._cards[0].mouse_exited.emit()
	motion(ui._cards[1])
	ui.select_option(&"epic")
	ui.confirm_selection()
	expect([], "The existing per-component sound switch covers the entire choice flow")
	ui._audio.enabled = true
	ui.open_duration = 0.0
	ui.present_choices(cards)
	cues.clear()
	paused = true
	ui.select_option(&"ordinary")
	key(KEY_ENTER)
	expect([&"select", &"confirm"], "Choice audio continues during externally paused combat")
	paused = false
	ui.present_choices(cards)
	cues.clear()
	ui._audio.repeat_interval = 0.2
	ui._audio._last_played.clear()
	motion(ui._cards[0])
	ui._cards[0].mouse_exited.emit()
	motion(ui._cards[1])
	expect([&"select"], "Rapid card crossings inherit the shared UI sound throttle")
	check(ui._audio._voices.size() == 6 and ui._audio.audio_bus == &"UI", "Growth interaction reuses the bounded shared UI channel")
	ui._audio.repeat_interval = 0.0
	ui.close()
	await core_bridge_checks(cards)
	check(load("res://data/audio/ui_sounds.tres").actions[&"open"] == &"journal_open", "Local remapping does not mutate the shared sound bank")
	ui.free()
	await create_timer(0.1).timeout
	print("Growth choice audio: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func core_bridge_checks(cards: Array[GrowthChoiceOption]) -> void:
	var feedback: CoreFeedbackAudio = load("res://scenes/audio/core_feedback_audio.tscn").instantiate()
	feedback.sounds = load("res://data/audio/core_sound_bank_world.tres")
	root.add_child(feedback)
	await process_frame
	var core_cues: Array[StringName] = []
	feedback._ui.repeat_interval = 0.0
	feedback._ui.cue_played.connect(func(cue: StringName): core_cues.append(cue))
	feedback._bind_choices(ui)
	ui.present_choices(cards)
	check(core_cues == [&"card_reveal"], "Actual core bridge retains one reveal cue for the complete hand")
	core_cues.clear()
	cues.clear()
	ui.set_draw_status(3, true)
	ui.request_reroll()
	check(core_cues == [&"reroll", &"card_reveal"] and cues.is_empty(), "Actual redraw has one core redraw/reveal pair without reopening audio")
	ui.select_option(&"ordinary")
	cues.clear()
	ui.confirm_selection()
	expect([&"confirm"], "Growth application reuses the existing single confirmation event")
	check(ui._audio._voices.any(func(voice): return voice.stream == feedback.sounds.clips_for(&"growth_apply")[0]), "The actual confirmation voice uses the approved growth-application clip")
	feedback.free()
	await process_frame
