extends Node2D
## Canvas projection of the real player fire; meshes and materials survive each loop.
const Timeline = preload("res://scripts/ui/main_menu_timeline.gd")
const SHADER = preload("res://shaders/ui/main_menu_fire.gdshader")
const GROUND_PROJECTION := Vector2(60, 30)
@export var source_visuals: PlayerActionVisuals = preload("res://data/combat/scenes/world/player/action_visuals.tres")

var segments: Array[Dictionary] = []
var clock := 0.0
var _ribbons: Array[MeshInstance2D] = []
var _lifetime := 0.0

func _ready() -> void:
	segments = Timeline.flight_segments()
	_lifetime = source_visuals.fire_trail_fresh_seconds + source_visuals.fire_trail_burn_seconds + source_visuals.fire_trail_ember_seconds
	for segment in segments: _build_ribbon(segment)
	sample(0.0, 0.0)

func _build_ribbon(segment: Dictionary) -> void:
	var start: Vector2 = segment.start / GROUND_PROJECTION
	var end: Vector2 = segment.end / GROUND_PROJECTION
	var center := (start + end) * 0.5
	var heading := (end - start).normalized()
	var length := start.distance_to(end)
	var width := source_visuals.fire_trail_width
	var along := heading * (length + width) * 0.5
	var across := heading.orthogonal() * width * 0.5
	var vertices := PackedVector3Array()
	for point: Vector2 in [center - along - across, center + along - across, center + along + across, center - along + across]:
		var projected := point * GROUND_PROJECTION
		vertices.append(Vector3(projected.x, projected.y, 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := ShaderMaterial.new()
	instance.shader = SHADER
	for pair in [["fresh_seconds", "fire_trail_fresh_seconds"], ["burn_seconds", "fire_trail_burn_seconds"], ["ember_seconds", "fire_trail_ember_seconds"], ["energy", "fire_trail_energy"], ["pixels_per_meter", "fire_trail_pixels_per_meter"]]:
		instance.set_shader_parameter(pair[0], source_visuals.get(pair[1]))
	instance.set_shader_parameter("birth", segment.birth)
	instance.set_shader_parameter("traversal_seconds", segment.seconds)
	instance.set_shader_parameter("segment_length", length)
	instance.set_shader_parameter("width", width)
	instance.set_shader_parameter("ground_projection", GROUND_PROJECTION)
	var ribbon := MeshInstance2D.new()
	ribbon.mesh = mesh
	ribbon.material = instance
	add_child(ribbon)
	_ribbons.append(ribbon)

func sample(stamp: float, strength: float) -> void:
	clock = stamp
	for index in _ribbons.size():
		var ribbon := _ribbons[index]
		var segment: Dictionary = segments[index]
		ribbon.visible = strength > 0.0 and stamp >= segment.birth and stamp < float(segment.birth) + float(segment.seconds) + _lifetime
		if not ribbon.visible: continue
		ribbon.material.set_shader_parameter("effect_clock", stamp)
		ribbon.material.set_shader_parameter("strength", clampf(strength, 0.0, 1.0))
