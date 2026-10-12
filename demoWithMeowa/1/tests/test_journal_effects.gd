extends SceneTree

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func wait(seconds := 0.36) -> void:
	await create_timer(seconds, true).timeout

func run() -> void:
	var ui: LoadoutUI = load("res://scenes/ui/loadout_ui.tscn").instantiate()
	ui.save_enabled = false
	root.add_child(ui)
	await process_frame
	ui._tab_pressed(0)
	ui.open_menu()
	assert(ui.menu_open and ui._input_guard.visible and not paused)
	assert(ui._book.modulate.a == 0.0)
	await wait(0.08)
	assert(ui._motion.amount > 0 and ui._motion.amount < 1)
	assert(ui._book.scale.x > ui.open_start_scale and ui._book.scale.x < 1)
	await wait()
	await process_frame
	assert(ui._motion.amount == 1 and not ui._input_guard.visible)
	assert(ui._book.position == Vector2.ZERO and ui._book.scale == Vector2.ONE)
	# Data changes immediately while the visual icon and numbers travel to their target.
	var before: float = ui.state.get_character_attributes()["attack"]
	assert(ui.state.equip("staff"))
	var after: float = ui.state.get_character_attributes()["attack"]
	assert(before != after and ui._motion._flights.size() == 1)
	await wait(0.08)
	assert(ui._motion.numbers.attack < before and ui._motion.numbers.attack > after)
	var target: LoadoutTile = ui._motion._slot(0)
	assert(target.payload.id == "staff" and target.get_child(0).modulate.a == 0)
	await wait(0.65)
	assert(ui._motion._flights.is_empty() and ui._fx.get_child_count() == 0)
	assert(ui._motion.numbers.attack == after and target.get_child(0).modulate.a == 1)
	# Replacement during flight must cancel the previous visual, without losing the latest state.
	assert(ui.state.equip("sword"))
	await wait(0.05)
	assert(ui.state.equip("staff"))
	await wait(0.65)
	assert(ui._fx.get_child_count() == 0 and ui.state.get_equipped_id(0) == "staff")
	ui._tab_pressed(2)
	assert(ui.current_page == 1 and ui._content.modulate.a == 0)
	await wait(0.05)
	assert(ui._content.modulate.a > 0 and ui._content.modulate.a < 1)
	ui._tab_pressed(0)
	await wait()
	assert(ui.current_page == 0 and ui._content.position == Vector2.ZERO and ui._content.modulate.a == 1)
	# Closing holds the input blocker until the visible book is gone; reopening reverses it.
	ui.close_menu()
	assert(ui._motion.closing and ui.is_in_group(&"gameplay_input_blockers"))
	await wait(0.04)
	ui.open_menu()
	await wait()
	assert(ui.menu_open and not ui._motion.closing and ui._motion.amount == 1)
	assert(ui.state.equip("sword"))
	await wait(0.04)
	ui.close_menu()
	await wait()
	assert(not ui.menu_open and not ui._window.visible and not ui.is_in_group(&"gameplay_input_blockers"))
	assert(ui._fx.get_child_count() == 0 and not paused)
	# Reduced motion and zero durations preserve all management behavior.
	ui.motion_enabled = false
	ui.open_menu()
	assert(ui._motion.amount == 1 and not ui._input_guard.visible)
	assert(ui.state.equip("staff"))
	await process_frame
	assert(ui._motion.numbers == ui.state.get_character_attributes() and ui._fx.get_child_count() == 0)
	ui.close_menu()
	assert(not ui.menu_open)
	ui.motion_enabled = true
	ui.open_duration = 0
	ui.close_duration = 0
	ui.open_menu()
	assert(ui._motion.amount == 1)
	ui.close_menu()
	assert(not ui.menu_open)
	# An externally paused world stays paused; the CanvasLayer can still animate.
	ui.open_duration = 0.24
	ui.close_duration = 0.16
	paused = true
	ui.open_menu()
	await wait()
	assert(ui._motion.amount == 1 and paused)
	ui.close_menu()
	await wait()
	assert(not ui.menu_open and paused)
	paused = false
	ui.free()
	await process_frame
	print("PASS: open/close interpolation, icon flights and exact attribute totals, repeated replacement, rapid tab and open/close reversal, input blocker lifetime, reduced motion and zero durations.")
	quit()
