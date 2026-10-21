class_name RicochetStormEffect
extends Node3D

const EFFECT_LAYER := preload("res://scripts/rendering/combat_effect_layer.gd")

const SHADER := preload("res://shaders/combat/ricochet_storm.gdshader")
const PATCH_SHADER := preload("res://shaders/combat/ricochet_storm_patch.gdshader")
enum Kind { CHAIN, SKY, TRAIL }
static var _quad: QuadMesh

@export_group("Meowa 原生雷电素材")
@export var arc_texture: Texture2D
@export var head_texture: Texture2D
@export var impact_frames: SpriteFrames
## 与现有人物实际缩放后的原生像素密度一致；不改变图片像素。
@export_range(0.005, 0.05, 0.001, "suffix:m/px") var pixel_size := 0.016
@export_group("雷潮表现")
@export_range(0.05, 1.0, 0.01, "suffix:s") var arc_duration := 0.28
@export_range(0.01, 0.15, 0.005, "suffix:s") var reveal_seconds := 0.035
@export_range(0.1, 1.0, 0.01, "suffix:s") var impact_duration := 0.28
@export_range(0.5, 5.0, 0.1, "suffix:m") var sky_height := 2.8
@export_range(0.1, 1.5, 0.05, "suffix:m") var impact_height := 0.45
@export_range(0.0, 4.0, 0.05) var effect_energy := 1.4
@export_range(0.5, 4.0, 0.1) var arc_energy_multiplier := 2.5
@export_range(0.0, 1.0, 0.05) var effect_opacity := 0.95
@export_group("成片电涌")
## 多目标实际落雷后铺开，沿用完整 Meowa 命中帧与原生像素；单怪不铺电涌面。
@export var patch_enabled := true
@export_range(0.15, 0.6, 0.01, "suffix:s") var patch_duration := 0.34
@export_range(0.0, 1.0, 0.05) var patch_opacity := 0.7
@export_range(0.1, 1.5, 0.05, "suffix:m") var patch_height := 0.6

var _bolts: Array[Dictionary] = []
var _pool: Array[Dictionary] = []
var _arc_material: ShaderMaterial
var _head_material: ShaderMaterial
var _impacts: LightPierceEffect
var _patches: Array[Dictionary] = []
var _patch_pool: Array[Dictionary] = []
var _patch_material: ShaderMaterial
var _patch_texture: Texture2D
var _patch_pixels := Vector2.ZERO

func _ready() -> void:
	if not _quad: _quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_arc_material = _material(arc_texture)
	EFFECT_LAYER.set_parameter(_arc_material, "arc_spine", true)
	EFFECT_LAYER.set_parameter(_arc_material, "spine_palette", head_texture)
	EFFECT_LAYER.set_parameter(_arc_material, "energy", effect_energy * arc_energy_multiplier)
	_head_material = _material(head_texture)
	_impacts = LightPierceEffect.new()
	_impacts.impact_frames = impact_frames
	_impacts.impact_width = pixel_size * 64.0
	_impacts.impact_height = impact_height
	_impacts.impact_duration = impact_duration
	_impacts.effect_energy = effect_energy
	_impacts.effect_opacity = effect_opacity
	_impacts.ground_light_enabled = false
	add_child(_impacts)
	_patch_material = EFFECT_LAYER.material(PATCH_SHADER)
	EFFECT_LAYER.set_parameter(_patch_material, "energy", effect_energy)
	set_process(false)

func prepare_feedback() -> void:
	if not _pool.is_empty(): return
	_impacts.prepare_feedback()
	for index in 4:
		show_link(Vector3.ZERO, Vector3(3.0, 0.0, index * 0.5))
	show_patch(PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]))
	stop()

func _material(texture: Texture2D) -> ShaderMaterial:
	var result := EFFECT_LAYER.material(SHADER)
	EFFECT_LAYER.set_parameter(result, "effect_texture", texture)
	EFFECT_LAYER.set_parameter(result, "energy", effect_energy)
	return result

func _mesh(material: ShaderMaterial) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func show_link(from: Vector3, to: Vector3, strength := 1.0, kind: Kind = Kind.CHAIN, visual_scale := 1.0) -> void:
	if from.distance_squared_to(to) < 0.0025: return
	var bolt: Dictionary = _pool.pop_back() if not _pool.is_empty() else {"parts": [], "head": _mesh(_head_material)}
	bolt.from = from
	bolt.to = to
	bolt.age = 0.0
	bolt.strength = strength
	bolt.kind = kind
	bolt.visual_scale = visual_scale
	bolt.phase = float(_bolts.size() * 7 + _pool.size() * 13)
	var slices := ceili(from.distance_to(to) / (pixel_size * arc_texture.get_width() * visual_scale))
	while bolt.parts.size() < slices: bolt.parts.append(_mesh(_arc_material))
	# 本条雷弧的相位与类别在取用池节点时确定，之后只更新揭示、位置和消散。
	for index in bolt.parts.size():
		bolt.parts[index].set_instance_shader_parameter("phase", float(bolt.phase) + index * 19.0)
		bolt.parts[index].set_instance_shader_parameter("show_spine", kind != Kind.TRAIL)
	_bolts.append(bolt)
	_update_bolt(bolt, get_viewport().get_camera_3d())
	set_process(true)

func show_hit(point: Vector3, sky_strike := false, visual_scale := 1.0) -> void:
	_impacts.show_hit(point, visual_scale)
	if sky_strike:
		var end := point + Vector3.UP * impact_height
		show_link(end + Vector3(0.45, sky_height, -0.25), end, 0.9, Kind.SKY, visual_scale)

func show_patch(points: PackedVector3Array, visual_scale := 1.0) -> void:
	if not patch_enabled or points.size() < 2 or not impact_frames: return
	if not impact_frames.has_animation(&"impact") or impact_frames.get_frame_count(&"impact") == 0: return
	var frame := impact_frames.get_frame_texture(&"impact", 0)
	if not frame: return
	_patch_pixels = frame.get_size() * 1.5
	for point in points:
		var patch: Dictionary = _patch_pool.pop_back() if not _patch_pool.is_empty() else {"mesh": _mesh(_patch_material)}
		patch.point = point + Vector3.UP * patch_height
		patch.age = 0.0
		patch.visual_scale = visual_scale
		patch.mesh.set_instance_shader_parameter("phase", floorf(point.x / pixel_size) * 0.13 + floorf(point.z / pixel_size) * 0.37)
		_patches.append(patch)
		_update_patch(patch, get_viewport().get_camera_3d())
	set_process(true)

func _update_patch(patch: Dictionary, camera: Camera3D) -> void:
	var progress := clampf(float(patch.age) / patch_duration, 0.0, 1.0)
	var frame_count := impact_frames.get_frame_count(&"impact")
	var frame := impact_frames.get_frame_texture(&"impact", mini(int(progress * frame_count), frame_count - 1))
	var texture: Texture2D = frame.atlas if frame is AtlasTexture else frame
	var rect: Rect2 = frame.region if frame is AtlasTexture else Rect2(Vector2.ZERO, frame.get_size())
	# 所有电涌共用命中图集；每个实例只传原生帧矩形、进度与强度。
	if texture != _patch_texture:
		_patch_texture = texture
		EFFECT_LAYER.set_parameter(_patch_material, "effect_texture", texture)
	var mesh: MeshInstance3D = patch.mesh
	mesh.global_position = patch.point
	var basis := camera.global_basis if camera else Basis.IDENTITY
	mesh.global_basis = Basis(basis.x * _patch_pixels.x * pixel_size * float(patch.visual_scale), basis.y * _patch_pixels.y * pixel_size * float(patch.visual_scale), basis.z)
	mesh.set_instance_shader_parameter("frame_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	mesh.set_instance_shader_parameter("progress", progress)
	mesh.set_instance_shader_parameter("intensity", patch_opacity * effect_opacity)
	mesh.show()

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for index in range(_bolts.size() - 1, -1, -1):
		var bolt: Dictionary = _bolts[index]
		bolt.age += delta
		if bolt.age >= arc_duration:
			_recycle(bolt)
			_bolts.remove_at(index)
		else: _update_bolt(bolt, camera)
	for index in range(_patches.size() - 1, -1, -1):
		var patch: Dictionary = _patches[index]
		patch.age += delta
		if patch.age >= patch_duration:
			patch.mesh.hide()
			_patch_pool.append(patch)
			_patches.remove_at(index)
		else: _update_patch(patch, camera)
	if _bolts.is_empty() and _patches.is_empty(): set_process(false)

func _update_bolt(bolt: Dictionary, camera: Camera3D) -> void:
	var offset: Vector3 = bolt.to - bolt.from
	var length := offset.length()
	var direction := offset / length
	var normal := camera.global_basis.z if camera else Vector3(0, 0.6, 1)
	var side := normal.cross(direction).normalized()
	if side.is_zero_approx(): side = Vector3.RIGHT
	var reveal := minf(1.0, float(bolt.age) / maxf(reveal_seconds, 0.001) + 0.12)
	var visible_length := length * reveal
	var scale: float = bolt.visual_scale
	var tile_length := pixel_size * arc_texture.get_width() * scale
	var width := pixel_size * arc_texture.get_height() * scale
	var fade := 1.0 - smoothstep(0.18, 1.0, float(bolt.age) / arc_duration)
	for index in bolt.parts.size():
		var node: MeshInstance3D = bolt.parts[index]
		var part_length := clampf(visible_length - index * tile_length, 0.0, tile_length)
		node.visible = part_length > 0.001
		if not node.visible: continue
		node.global_position = bolt.from + direction * (index * tile_length + part_length * 0.5)
		node.global_basis = Basis(direction * part_length, side * width, direction.cross(side))
		node.set_instance_shader_parameter("source_rect", Vector4(0, 0, part_length / tile_length, 1))
		node.set_instance_shader_parameter("intensity", fade * effect_opacity * float(bolt.strength))
	var head: MeshInstance3D = bolt.head
	head.visible = float(bolt.strength) > 0.5 and reveal < 1.0
	if head.visible:
		var head_width := pixel_size * head_texture.get_width() * scale
		head.global_position = bolt.from + direction * (visible_length - head_width * 0.44)
		head.global_basis = Basis(direction * head_width, side * pixel_size * head_texture.get_height() * scale, direction.cross(side))
		head.set_instance_shader_parameter("intensity", fade * effect_opacity * float(bolt.strength))

func _recycle(bolt: Dictionary) -> void:
	for part in bolt.parts: part.hide()
	bolt.head.hide()
	_pool.append(bolt)

func stop() -> void:
	for bolt in _bolts: _recycle(bolt)
	_bolts.clear()
	for patch in _patches:
		patch.mesh.hide()
		_patch_pool.append(patch)
	_patches.clear()
	if _impacts: _impacts.stop()
	set_process(false)
