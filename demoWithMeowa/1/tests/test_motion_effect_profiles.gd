extends SceneTree

const OLD_WIND = preload("res://tests/fixtures/legacy_charge_wind.gd")
const OLD_AIR = preload("res://tests/fixtures/legacy_air_envelope.gd")
const OLD_IMPACT = preload("res://tests/fixtures/legacy_death_impact.gd")
const WIND_PARAMETERS := ["phase", "charge", "airflow_texture", "funnel_enabled", "radius", "bottom_radius", "height", "width", "turns", "trail_span", "opacity", "body_mask_enabled"]
const AIR_PARAMETERS := ["flow_phase", "flow_amount", "opacity", "flow_radius", "flow_length", "flow_brush", "brush_region", "body_mask_enabled"]
const IMPACT_PARAMETERS := ["frame_rect", "tint", "opacity", "hit_flash", "death_energy"]
var checks := 0
var failures := 0
var world: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func parameters(material: ShaderMaterial, names: Array) -> Array:
	var result := []
	for uniform in names: result.append(material.get_shader_parameter(uniform))
	return result

func wind_checks() -> void:
	var current := PlayerChargeWind.new()
	var old = OLD_WIND.new()
	world.add_child(current)
	world.add_child(old)
	var settings := load("res://data/combat/scenes/world/player/action_visuals.tres").duplicate() as PlayerActionVisuals
	var replacement := load("res://assets/meowa/combat/body_rebound/departure_airflow.png") as Texture2D
	for step in 24:
		if step == 3: settings.charge_wind_turns += 0.00000001
		if step == 5: settings.charge_wind_width_pixels += 3.0
		if step == 7: settings.charge_wind_opacity *= 0.7
		if step == 9: settings.charge_wind_texture = replacement
		if step == 11: settings.charge_wind_funnel_enabled = false
		if step == 13: settings.charge_effect_opacity *= 0.8
		if step == 15:
			settings.charge_wind_enabled = false
		if step == 16: settings.charge_wind_enabled = true
		if step == 18:
			current.stop()
			old.stop()
		if step == 20: settings.charge_wind_funnel_enabled = true
		if step == 22: settings.charge_wind_layers = 2
		var pixel := 0.018 if step < 8 else 0.022
		var fraction := minf(1.0, step * 0.25)
		var delta := 0.0 if step % 3 == 0 else 1.0 / 60.0
		current.synchronize(settings, pixel, fraction, delta)
		old.synchronize(settings, pixel, fraction, delta)
		check(parameters(current._material, WIND_PARAMETERS) == parameters(old._material, WIND_PARAMETERS), "蓄力风的材质参数与旧实现一致，包括热调、冻结和重启")
		check(current._phase == old._phase and current.visible == old.visible and current._wisps.custom_aabb == old._wisps.custom_aabb and current._wisps.multimesh.instance_count == old._wisps.multimesh.instance_count, "蓄力风相位、层数与真实包围盒保持")
	current.free()
	old.free()

func air_checks() -> void:
	var current := PlayerAirEnvelope.new()
	var old = OLD_AIR.new()
	for effect in [current, old]:
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/combat/player_air_envelope.gdshader")
		effect.material_override = material
		world.add_child(effect)
	var settings := load("res://data/combat/scenes/world/player/action_visuals.tres").duplicate() as PlayerActionVisuals
	var source := Sprite3D.new()
	world.add_child(source)
	for step in 20:
		source.position = Vector3(step * 0.11, 0, step * -0.03)
		if step == 3: settings.speed_flow_radius += 0.00000001
		if step == 5: settings.speed_flow_radius += 0.2
		if step == 7: settings.speed_flow_length += 0.7
		if step == 9: settings.speed_flow_texture = load("res://assets/meowa/combat/body_rebound/departure_airflow.png")
		if step == 11: settings.speed_flow_texture_region = Rect2(0.1, 0.2, 0.7, 0.6)
		if step == 13: settings.speed_flow_opacity *= 0.5
		if step == 16:
			current.stop()
			old.stop()
		var heading := Vector3.RIGHT.rotated(Vector3.UP, step * 0.23)
		var strength := 0.0 if step == 14 else 0.35 + (step % 3) * 0.25
		var delta := 0.0 if step % 3 == 0 else 1.0 / 60.0
		current.synchronize(source, heading, strength, delta, settings)
		old.synchronize(source, heading, strength, delta, settings)
		check(parameters(current._material, AIR_PARAMETERS) == parameters(old._material, AIR_PARAMETERS), "飞行气流的全部参数保持，真实速度和相位仍持续更新")
		check(current.global_transform == old.global_transform and current.custom_aabb == old.custom_aabb and current.visible == old.visible and current.phase == old.phase, "转向、位置、包围盒与启停保持")
	source.free()
	current.free()
	old.free()

func impact_state(effect: EnemyDeathEffect) -> Array:
	var result := []
	for index in range(1, 4):
		var piece := effect._pieces[index]
		var uniforms := []
		for uniform in IMPACT_PARAMETERS: uniforms.append(piece.get_instance_shader_parameter(uniform))
		result.append([piece.visible, piece.global_transform, piece.material_override, uniforms])
	return result

func impact_checks() -> void:
	var current := EnemyDeathEffect.new()
	var old = OLD_IMPACT.new()
	world.add_child(current)
	world.add_child(old)
	var frames := load("res://data/combat/scenes/world/player/action_visuals.tres").melee_death_impact_frames as SpriteFrames
	check(frames != null and frames.get_frame_count(&"bounce") > 0, "死亡爆点使用正式原生帧")
	for replay in 2:
		for effect in [current, old]:
			effect.stop()
			effect._impact_source = frames
			effect._impact_seconds = 0.16
			effect._impact_frame = -1
			effect._position = Vector3(2.3, 0.5, -1.8)
			effect._impact_angle = 0.37 + replay * 0.7
			effect._impact_radius = replay * 0.75
			effect._impact_opacity = 0.45 if replay else 1.0
			effect._pixel = 0.018
		for step in 21:
			current._age = step * 0.01
			old._age = current._age
			var facing := Basis(Vector3.UP, step * 0.07)
			current._display_impact(facing)
			old._display_impact(facing)
			check(impact_state(current) == impact_state(old), "三路爆点每帧的变换、材质、原生 UV 与消散保持")
	current.free()
	old.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	wind_checks()
	air_checks()
	impact_checks()
	world.free()
	print("Motion effect profiles: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
