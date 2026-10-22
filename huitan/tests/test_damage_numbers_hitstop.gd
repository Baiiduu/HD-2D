extends "res://tests/test_sword_hit_impact.gd"

var numbers: DamageNumbers

func frame(seconds: float, engine_delta := 1.0 / 60.0) -> void:
	# 同一帧里先收到普通 delta，再由命中把 Engine.time_scale 切到 0.001。
	numbers.set("_last_tick", Time.get_ticks_usec() - int(seconds * 1000000.0))
	numbers._process(engine_delta)

func run() -> void:
	await setup()
	var previous := player.movement_camera
	camera = FollowCamera.new()
	camera.target = player
	camera.distance = 30.0
	camera.fov = 28.0
	world.add_child(camera)
	player.movement_camera = camera
	previous.free()
	camera.current = true
	camera.set_process(false)
	impact = load("res://scripts/world/hit_impact_presentation.gd").new()
	impact.session = session
	world.add_child(impact)
	impact.set_process(false)
	numbers = load("res://scenes/combat/damage_numbers.tscn").instantiate()
	numbers.number_styles = load("res://data/combat/scenes/world/configuration.tres").number_styles
	numbers.session = session
	session.add_child(numbers)
	var enemy := hit_target(&"basic_sword", false, 10.0)
	check(enemy.health == 90.0 and numbers._active.size() == 1, "A real ten-damage basic hit creates one number before the short hold")
	var number := numbers._active[0]
	frame(1.0 / 60.0)
	check(numbers._active.size() == 1 and number.active and number.visible and number.age > 0.0 and number.age < 0.04, "The ordinary unscaled entry-frame delta cannot expire the number immediately")
	check(number._text == "10" and number.event != null, "A held basic hit keeps its actual ten-damage event and text")
	for index in 2: enemy.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	frame(0.012, 0.012 * Engine.time_scale)
	check(enemy.health == 70.0 and numbers._active.size() == 3, "Every valid same-target hit keeps its own number during the hold")
	check(numbers._active.all(func(item): return item.active and item.age < 0.06), "Existing and new digits share the real frame duration without stacking time conversions")
	impact.advance(0.06)
	var age := number.age
	numbers._process(1.0 / 60.0)
	check(is_equal_approx(number.age - age, 1.0 / 60.0), "After the hold, digits return to the ordinary combat clock")
	numbers.clear()
	for source in [&"flight_sword", &"ricochet_storm"]:
		impact.clear()
		emit_kill(source)
		number = numbers._active[0]
		frame(1.0 / 60.0)
		check(numbers._active.size() == 1 and number.active and number.age < 0.04, "Lethal hits also retain their number on time-scale entry: " + String(source))
		numbers.clear()
	impact.clear()
	hit_target(&"basic_sword", false, 10.0)
	number = numbers._active[0]
	frame(0.012)
	age = number.age
	session.set_combat_frozen(true)
	numbers.set("_last_tick", Time.get_ticks_usec() - 3000000)
	session.set_combat_frozen(false)
	impact.clear()
	hit_target(&"basic_sword", false, 10.0)
	numbers._process(1.0 / 60.0)
	check(numbers._active.size() == 2 and number.active and number.age - age < 0.04, "Returning from upgrade freeze cannot charge frozen wall time to old numbers")
	impact.clear()
	numbers.clear()
	hit_target(&"basic_sword", false, 10.0)
	frame(0.02)
	check(numbers._active.size() == 1 and numbers._active[0].age < 0.04, "Idle pool reuse starts from the new hit instead of stale wall time")
	impact.clear()
	numbers._process(2.0)
	check(numbers._active.is_empty() and not numbers.is_processing(), "Numbers still expire and return to the idle pool normally")
	world.queue_free()
	await settle(4)
	print("Damage numbers during hit-stop: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
