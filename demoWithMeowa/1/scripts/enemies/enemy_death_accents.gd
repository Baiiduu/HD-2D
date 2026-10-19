extends Node3D

## 由死亡快照时钟驱动。六片原生火花与三簇贴地烟尘各一次批量绘制。
const SHADER := preload("res://shaders/combat/death_specks.gdshader")
const SPARKS := preload("res://assets/meowa/combat/body_bounce/bounce_atlas.png")
static var _quad: QuadMesh
static var _spark_material: ShaderMaterial
static var _dust_material: ShaderMaterial
static var _users := 0
var sparks: MultiMeshInstance3D
var dust: MultiMeshInstance3D

func _ready() -> void:
	_users += 1
	if not _quad:
		_quad = QuadMesh.new()
		_spark_material = CombatEffectLayer.material(SHADER)
		CombatEffectLayer.set_parameter(_spark_material, &"spark_texture", SPARKS)
		_dust_material = ShaderMaterial.new()
		_dust_material.shader = SHADER
		_dust_material.set_shader_parameter(&"dust_mode", true)
	sparks = _batch(6, _spark_material)
	dust = _batch(3, _dust_material)
	set_process(false)
	hide()

func _exit_tree() -> void:
	_users -= 1
	if _users == 0:
		_quad = null
		_spark_material = null
		_dust_material = null

func _batch(count: int, material: ShaderMaterial) -> MultiMeshInstance3D:
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	batch.multimesh.mesh = _quad
	batch.multimesh.instance_count = count
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
	batch.top_level = true
	batch.global_transform = Transform3D.IDENTITY
	return batch

func flight(effect: EnemyDeathEffect, facing: Basis, progress: float) -> void:
	show()
	var age := effect._age - effect._pause_seconds
	sparks.visible = effect._trail_enabled and age > 0.035 and age < effect._air_seconds
	if sparks.visible:
		for index in 6:
			var part := clampf((age - 0.02 - index * 0.018) / effect._air_seconds, 0.0, 1.0)
			var point := effect._position + effect._flight_offset(part)
			point.y += sin(part * PI) * (index % 3 - 1) * effect._pixel * 5.0
			var size := effect._pixel * 6.0
			var rotation := facing * Basis(Vector3.BACK, part * TAU * (index + 1) + index)
			sparks.multimesh.set_instance_transform(index, Transform3D(rotation.scaled_local(Vector3(size, size, 1)), point))
			sparks.multimesh.set_instance_color(index, Color(1, 1, 1, (1.0 - progress) * 0.85))
	var landing_age := age - effect._air_seconds
	dust.visible = effect._landing_enabled and landing_age >= 0.0 and landing_age < 0.28
	if dust.visible:
		var phase := landing_age / 0.28
		var ground := effect._position + effect._flight_offset(1.0) - Vector3.UP * effect._size.y * 0.5
		for index in 3:
			var side := float(index - 1)
			var point := ground + facing.x * side * (0.08 + phase * 0.26) + Vector3.UP * (0.12 + phase * 0.1)
			var size := effect._pixel * (16.0 + phase * 6.0)
			dust.multimesh.set_instance_transform(index, Transform3D(facing.scaled_local(Vector3(size, size, 1)), point))
			dust.multimesh.set_instance_color(index, Color(0.78, 0.73, 0.64, (1.0 - phase) * 0.45))

func burst(point: Vector3, pixel: float, facing: Basis, progress: float, angle: float) -> void:
	show()
	sparks.show()
	dust.hide()
	for index in 6:
		var heading := angle + index * TAU / 6.0
		var offset := facing * Vector3(cos(heading), sin(heading), 0) * (0.12 + progress * 0.85)
		var size := pixel * 6.0
		var rotation := facing * Basis(Vector3.BACK, heading + progress * TAU)
		sparks.multimesh.set_instance_transform(index, Transform3D(rotation.scaled_local(Vector3(size, size, 1)), point + offset))
		sparks.multimesh.set_instance_color(index, Color(1, 1, 1, 1.0 - progress))
