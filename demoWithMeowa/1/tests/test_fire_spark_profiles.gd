extends SceneTree
const CURRENT := preload("res://scripts/player/player_fire_sparks.gd")
const LEGACY := preload("res://tests/fixtures/legacy_fire_sparks.gd")
const PARAMETERS := ["effect_clock","energy","spark_amount","body_mask_margin_pixels","pixels_per_meter","fire_brush","flow_strength","flow_speed","brush_region","body_mask_enabled"]
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func state(effect: Node3D) -> Array:
	return [effect.count,effect._head,effect._births,effect._ends,effect._transforms,effect._custom,effect._last_end,effect._to_next,effect._serial,effect._bounds,effect.visible]

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var current := CURRENT.new()
	var old := LEGACY.new()
	world.add_child(current)
	world.add_child(old)
	var settings := load("res://data/combat/scenes/world/player/action_visuals.tres").duplicate() as PlayerActionVisuals
	for step in 70:
		if step == 3: settings.fire_trail_energy += 0.00000001
		if step == 7: settings.fire_trail_spark_amount *= 0.5
		if step == 11: settings.fire_trail_pixels_per_meter += 4.0
		if step == 15: settings.fire_trail_brush_region.position.x += 0.01
		if step == 20: settings.fire_trail_body_clearance_pixels += 1.0
		if step == 25: settings.fire_trail_flow_speed += 0.7
		if step == 30: settings.fire_trail_flow_strength *= 0.6
		if step == 35: settings.fire_trail_flow_enabled = false
		if step == 40: settings.fire_trail_flow_enabled = true
		if step == 45:
			current.clear()
			old.clear()
		if step == 50: settings.fire_trail_brush = null
		if step == 55: settings.fire_trail_brush = load("res://assets/meowa/combat/fire_flow/brush.png")
		var clock := step * 0.02
		for effect in [current,old]:
			if step % 3 == 0: effect.deposit(Vector3.RIGHT*step*0.1,Vector3.RIGHT*(step*0.1+0.1),0.02,clock,settings)
			effect.advance(clock,settings)
		check(state(current) == state(old),"配置变化、关闭、重启和过期保留原火星数量、位置、时间及实例数据")
		for parameter in PARAMETERS:
			check(current.material.get_shader_parameter(parameter) == old.material.get_shader_parameter(parameter),"贴图、样式和逐帧时钟与原材质参数一致："+parameter)
	world.free()
	await process_frame
	print("Fire spark profiles: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
