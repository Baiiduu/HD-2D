extends SceneTree

class TrainingProbe extends TrainingUI:
	func can_interact() -> bool: return true
	func _process(_delta: float) -> void: pass

var checks := 0
var failures: Array[String] = []
var cues: Array[StringName] = []

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ",label)

func expect(cue: StringName, label: String) -> void:
	check(cues == [cue],label)
	cues.clear()

func settle() -> void:
	for frame in 6: await process_frame

func button_with_text(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == text: return child
		var found := button_with_text(child,text)
		if found: return found
	return null

func run() -> void:
	var master_volume := AudioServer.get_bus_volume_db(0)
	var ui: LoadoutUI = load("res://scenes/ui/loadout_ui.tscn").instantiate()
	ui.save_enabled=false
	ui.motion_enabled=false
	var audio: UIAudio = ui.get_node("UIAudio")
	audio.repeat_interval=0.0
	audio.cue_played.connect(func(cue): cues.append(cue))
	root.add_child(ui)
	await settle()
	check(cues.is_empty(),"Initialization and inventory seeding are silent")
	for cue in UISoundBank.CUES:
		var clip := audio.sounds.get_clip(cue)
		check(clip != null and clip.get_length()>0.3 and clip.get_length()<0.7,"Short playable clip: "+cue)
	ui.open_menu()
	expect(&"journal_open","Opening plays one cover sound")
	check(audio._voices[0].playing,"The cue starts an actual AudioStreamPlayer")
	ui.open_menu()
	check(cues.is_empty(),"Refreshing an open menu does not replay opening audio")
	ui._inventory_book.select_item("wood")
	expect(&"select","Selecting an inventory item plays a soft tick")
	await settle()
	ui._inventory_book._category_buttons[3].pressed.emit()
	expect(&"select","Category changes have one selection sound")
	await settle()
	button_with_text(ui._inventory_book,"整理").pressed.emit()
	expect(&"confirm","Sorting plays confirmation rather than refresh noises")
	ui._inventory_book.selected_item="tomato_seed"
	ui._inventory_book.refresh()
	button_with_text(ui._inventory_book,"加入快捷栏 1").pressed.emit()
	expect(&"item_drop","Quick assignment plays a successful item placement")
	check(ui.state.get_quantity("tomato_seed")==20,"Audio binding keeps shared inventory quantities")
	button_with_text(ui._inventory_book,"加入快捷栏 1").pressed.emit()
	expect(&"error","A rejected assignment cannot play success")
	await settle()
	var target: LoadoutTile = ui._item_bar._slots.get_child(6)
	target._drop_data(Vector2.ZERO,{"kind":"item","id":"tomato_seed"})
	expect(&"item_drop","A valid drop plays placement after the state accepts it")
	await settle()
	var right := InputEventMouseButton.new()
	right.button_index=MOUSE_BUTTON_RIGHT
	right.pressed=true
	ui._item_bar._slots.get_child(6).gui_input.emit(right)
	expect(&"cancel","Right click removal plays cancel")
	ui._item_bar._select(2)
	expect(&"select","Keyboard and mouse quick selection share the same feedback")
	ui._tab_pressed(0)
	expect(&"page_turn","Changing the book page plays a paper turn")
	ui._tab_pressed(0)
	check(cues.is_empty(),"Selecting the current page is silent")
	ui._ui_action(ui.state.equip.bind("staff"),&"equip")
	expect(&"equip","Successful equipment changes have clasp feedback")
	ui._ui_action(ui.state.equip.bind("missing"),&"equip")
	expect(&"error","Invalid equipment has error feedback")
	ui._tab_pressed(2)
	expect(&"page_turn","The skill page uses the same page sound")
	ui._select_skill("ice")
	cues.clear()
	await settle()
	button_with_text(ui._actions,"学习技能").pressed.emit()
	expect(&"confirm","Learning a skill plays success")
	await settle()
	button_with_text(ui._actions,"2").pressed.emit()
	expect(&"item_drop","Assigning a learned skill plays placement")
	ui.close_menu()
	expect(&"journal_close","Closing has one cover sound")
	ui.close_menu()
	check(cues.is_empty(),"Repeated close requests are silent")
	var training := TrainingProbe.new()
	training.loadout=ui
	root.add_child(training)
	await settle()
	check(training.open_menu(),"Training opens through its UI path")
	expect(&"journal_open","Training opening uses the shared audio component")
	check(training.train("health"),"Training action succeeds")
	expect(&"confirm","Accepted training plays success while the loadout is hidden")
	ui.state.training_points=0
	check(not training.train("attack"),"Training rejects insufficient points")
	expect(&"error","Rejected training plays failure")
	training.close_menu()
	expect(&"journal_close","Training closing plays the matching close sound")
	ui.state.add_item("wood",1)
	await settle()
	check(cues.is_empty(),"Programmatic inventory updates stay silent")
	paused=true
	check(audio.play(&"confirm") and audio.can_process() and audio._voices[0].can_process(),"UI audio remains processable during external pause")
	paused=false
	cues.clear()
	audio.enabled=false
	check(not audio.play(&"select") and cues.is_empty(),"Disabling UI audio suppresses future cues")
	var stopped := true
	for voice in audio._voices: stopped = stopped and not voice.playing
	check(stopped,"Disabling stops only the UI voices")
	audio.enabled=true
	audio.repeat_interval=0.1
	audio._last_played.clear()
	check(audio.play(&"select") and not audio.play(&"select"),"Same-frame repeated cues are throttled")
	check(audio._voices.size()==6 and AudioServer.get_bus_volume_db(0)==master_volume,"The bounded voice pool does not alter shared music or ambience volume")
	training.free()
	ui.free()
	await settle()
	print("UI audio: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
