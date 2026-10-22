@tool
extends Sprite3D

const SHADER := preload("res://shaders/character/character_lighting.gdshader")
const OCCLUSION_SHADER := preload("res://shaders/character/character_occlusion.gdshader")
const EFFECT_MASK_SHADER := preload("res://shaders/character/combat_effect_mask.gdshader")
const HIT_SILHOUETTE := preload("res://scripts/rendering/hit_silhouette.gd")
static var _shared_bodies: Dictionary = {}
static var _shared_outlines: Dictionary = {}
static var _shared_quads: Dictionary = {}
static var _shared_effect_masks: Dictionary = {}
static var _shared_users := 0

## 同帧、同受光与颜色的波次贴片共用资源；个人参数变化时重新选择，互不修改。
@export var shared_materials := false

@export_group("人物受光")
## 关闭恢复原生 Sprite3D 材质；仍使用现有场景照明与阴影。
@export var lighting_enabled := true:
	set(value): lighting_enabled = value; _queue_apply()
## 扩大侧光的柔和过渡，避免贴片转为背光时突然失去直接照明。
@export_range(0.0, 0.8, 0.05) var light_wrap := 0.3:
	set(value): light_wrap = value; _queue_apply()
## 用世界朝上的受光补充身体体积感，使人物与脚下地面的灯光颜色更一致。
@export_range(0.0, 1.0, 0.05) var top_light_response := 0.4:
	set(value): top_light_response = value; _queue_apply()
## 真实背光照到轮廓时的窄亮边；遮挡或移出光照范围时消失，0 关闭。
@export_range(0.0, 0.5, 0.01) var back_rim_strength := 0.12:
	set(value): back_rim_strength = value; _queue_apply()
## 只缩放当前人物接收的真实全向灯与聚光灯；1 为原强度，0 关闭。
## 仍遵守光源颜色、范围、距离衰减和阴影；方向光与环境光保持原值。
@export_range(0.0, 3.0, 0.05) var local_light_response := 1.0:
	set(value): local_light_response = value; _queue_apply()

@export_group("人物逐帧法线")
## 独立法线提供轻微身体和衣物受光；源图及动画保持原样。
@export var normal_mapping_enabled := false:
	set(value): normal_mapping_enabled = value; _queue_apply()
@export_range(0.0, 1.0, 0.05) var normal_mapping_strength := 0.4:
	set(value): normal_mapping_strength = value; _queue_apply()
## 可选对应法线图；使用图集时必须与完整颜色图集同尺寸、同帧排列。
@export var normal_texture_override: Texture2D:
	set(value): normal_texture_override = value; _queue_apply()

@export_group("遮挡轮廓")
## 被建筑等不透明表面挡住时，仅显示被挡部分的像素轮廓。
@export var occlusion_outline_enabled := true:
	set(value): occlusion_outline_enabled = value; _queue_apply()
## 轮廓颜色；透明度另由下方参数控制。
@export var occlusion_outline_color := Color(1.0, 0.89, 0.55):
	set(value): occlusion_outline_color = value; _queue_apply()
## 向人物边缘内部描线的宽度，单位为原图像素；0 关闭。
@export_range(0.0, 4.0, 0.25) var occlusion_outline_width := 1.0:
	set(value): occlusion_outline_width = value; _queue_apply()
## 轮廓不透明度；越大越容易看清被遮挡人物。
@export_range(0.0, 1.0, 0.05) var occlusion_outline_opacity := 0.85:
	set(value): occlusion_outline_opacity = value; _queue_apply()
## 遮挡表面至少比人物靠近镜头多少米；避免脚底接触和深度误差触发轮廓。
@export_range(0.001, 0.2, 0.001, "suffix:m") var occlusion_depth_bias := 0.03:
	set(value): occlusion_depth_bias = value; _queue_apply()

var _material: ShaderMaterial
var _original_material: Material
var _apply_queued := false
var _outline: MeshInstance3D
var _outline_material: ShaderMaterial
var _outline_mesh: QuadMesh
var _outline_rect := Rect2()
var _outline_pixel_size := -1.0
var _outline_state: Array = []
var _last_flip_h := false
var _last_flip_v := false
var _last_tint := Color(-1.0, -1.0, -1.0, -1.0)
var _shared_registered := false
var _bound_texture: Texture2D
var _occlusion_outline_allowed := true
var _effect_receiver := false
var _effect_mask_state: Array = []
var _motion_lean := Vector3.ZERO
var _motion_pivot := Vector3.ZERO
var _hit_silhouette: RefCounted
var _hit_silhouette_amount := 0.0
var _speed_rim_amount := 0.0

## 仅主体实例持有；共享材质、遮挡轮廓、怪物及残影不会被一起染亮。
func set_speed_rim(data: Vector4, direction: Vector3, color: Color) -> void:
	_speed_rim_amount = data.x
	set_instance_shader_parameter(&"speed_rim_data", data)
	set_instance_shader_parameter(&"speed_rim_direction", direction)
	set_instance_shader_parameter(&"speed_rim_color", color)
	if _material: material_override = _material if _uses_custom_material() else _original_material

func show_hit_silhouette(settings: PlayerActionVisuals, source: StringName) -> void:
	if not HIT_SILHOUETTE.accepts(settings, source): return
	if not _hit_silhouette: _hit_silhouette = HIT_SILHOUETTE.new()
	if not _hit_silhouette.strike(settings, source): return
	set_instance_shader_parameter(&"hit_silhouette_rim_color", _hit_silhouette.rim_color)
	_apply_hit_silhouette()

func clear_hit_silhouette() -> void:
	if _hit_silhouette: _hit_silhouette.clear()
	_apply_hit_silhouette()

func _advance_hit_silhouette(delta: float) -> void:
	if not _hit_silhouette or not can_process() or (_hit_silhouette.remaining <= 0.0 and _hit_silhouette.cooldown <= 0.0): return
	_hit_silhouette.advance(delta / maxf(Engine.time_scale, 0.001))
	_apply_hit_silhouette()

func _apply_hit_silhouette() -> void:
	var value: float = _hit_silhouette.amount if _hit_silhouette else 0.0
	if is_equal_approx(value, _hit_silhouette_amount): return
	_hit_silhouette_amount = value
	set_instance_shader_parameter(&"hit_silhouette_amount", value)
	if _material: material_override = _material if _uses_custom_material() else _original_material

func _uses_custom_material() -> bool:
	return lighting_enabled or not _motion_lean.is_zero_approx() or _hit_silhouette_amount > 0.0 or _speed_rim_amount > 0.0

## 与原贴图/受光解耦，实例参数避免影响共享同帧材质的怪物。
func set_motion_pose(lean: Vector3, pivot: Vector3) -> void:
	_motion_lean = lean
	_motion_pivot = pivot
	set_meta("motion_lean", lean)
	set_meta("motion_pivot", pivot)
	apply_motion_to(self)
	if is_instance_valid(_outline): apply_motion_to(_outline)
	if _material: material_override = _material if _uses_custom_material() else _original_material

func apply_motion_to(instance: GeometryInstance3D) -> void:
	instance.set_instance_shader_parameter("motion_lean", _motion_lean)
	instance.set_instance_shader_parameter("motion_pivot", _motion_pivot)

## 波次统一开关只作许可门，不覆盖 Sprite 自己保存的轮廓开关。
func set_occlusion_outline_allowed(value: bool) -> void:
	_occlusion_outline_allowed = value
	_sync_outline()

func _ready() -> void:
	_effect_receiver = get_parent() is WaveEnemy
	process_priority = 1 # Sync flips after Player has selected this frame's facing.
	apply_lighting()
	_sync_effect_mask()

func _exit_tree() -> void:
	if _bound_texture and _bound_texture.changed.is_connected(_sync_texture):
		_bound_texture.changed.disconnect(_sync_texture)
	_bound_texture = null
	if _shared_registered:
		_shared_users -= 1
		_shared_registered = false
		if _shared_users == 0:
			_shared_bodies.clear()
			_shared_outlines.clear()
			_shared_quads.clear()
			_shared_effect_masks.clear()

func _process(_delta: float) -> void:
	_advance_hit_silhouette(_delta)
	# An already-open @tool scene may not receive _ready after a script reload.
	if not _material:
		apply_lighting()
	if _uses_custom_material():
		if shared_materials:
			if flip_h != _last_flip_h or flip_v != _last_flip_v or modulate != _last_tint: _select_shared_body()
		elif flip_h != _last_flip_h:
			_material.set_shader_parameter("flip_h", flip_h)
			_last_flip_h = flip_h
		if not shared_materials and flip_v != _last_flip_v:
			_material.set_shader_parameter("flip_v", flip_v)
			_last_flip_v = flip_v
		if not shared_materials and modulate != _last_tint:
			_material.set_shader_parameter("tint", modulate)
			_last_tint = modulate
	_sync_outline()
	_sync_effect_mask()

func _sync_effect_mask() -> void:
	if not _effect_receiver: return
	if not texture:
		material_overlay = null
		_effect_mask_state.clear()
		return
	var state: Array = [texture, modulate.a, billboard]
	if state == _effect_mask_state: return
	# state 同时用作共享缓存键；本地失效时不能清空字典中的同一个数组。
	_effect_mask_state = state.duplicate()
	if not _shared_registered:
		_shared_registered = true
		_shared_users += 1
	if not _shared_effect_masks.has(state):
		var material := ShaderMaterial.new()
		material.shader = EFFECT_MASK_SHADER
		material.render_priority = -120
		material.set_shader_parameter("sprite_texture", texture)
		material.set_shader_parameter("opacity", modulate.a)
		material.set_shader_parameter("fixed_y", billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
		_shared_effect_masks[state] = material
	material_overlay = _shared_effect_masks[state]

func _queue_apply() -> void:
	if not is_inside_tree() or _apply_queued:
		return
	_apply_queued = true
	apply_lighting.call_deferred()

func _sync_texture() -> void:
	# 动画帧、图集区域和纹理的原地修改都使轮廓绑定失效。
	_bind_texture_changes()
	_outline_state.clear()
	_effect_mask_state.clear()
	if shared_materials:
		_select_shared_body()
	elif _material:
		_material.set_shader_parameter("sprite_texture", texture)
		_bind_normal(_material)
	else:
		_queue_apply()

func _bind_texture_changes() -> void:
	if _bound_texture == texture: return
	if _bound_texture and _bound_texture.changed.is_connected(_sync_texture):
		_bound_texture.changed.disconnect(_sync_texture)
	_bound_texture = texture
	if _bound_texture and not _bound_texture.changed.is_connected(_sync_texture):
		_bound_texture.changed.connect(_sync_texture)

func _select_shared_body() -> void:
	if not _shared_registered:
		_shared_registered = true
		_shared_users += 1
	var key: Array = [texture, modulate, billboard, flip_h, flip_v, lighting_enabled, light_wrap,
		top_light_response, back_rim_strength, local_light_response, normal_mapping_enabled, normal_mapping_strength, normal_texture_override]
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		key.append(atlas.region)
		key.append(atlas.atlas.get_size() if atlas.atlas else Vector2.ZERO)
	if not _shared_bodies.has(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		apply_lighting_to(material)
		_shared_bodies[key] = material
	_material = _shared_bodies[key]
	material_override = _material if _uses_custom_material() else _original_material
	_last_flip_h = flip_h
	_last_flip_v = flip_v
	_last_tint = modulate

func apply_lighting() -> void:
	_apply_queued = false
	if not texture_changed.is_connected(_sync_texture):
		texture_changed.connect(_sync_texture)
	_bind_texture_changes()
	if not _material: _original_material = material_override
	var defaults := {"lighting_enabled": true, "light_wrap": 0.3,
		"top_light_response": 0.4, "back_rim_strength": 0.12, "local_light_response": 1.0,
		"normal_mapping_enabled": false, "normal_mapping_strength": 0.4,
		"occlusion_outline_enabled": true, "occlusion_outline_color": Color(1.0, 0.89, 0.55),
		"occlusion_outline_width": 1.0, "occlusion_outline_opacity": 0.85, "occlusion_depth_bias": 0.03}
	for key in defaults:
		if get(key) == null:
			set(key, defaults[key])
	if shared_materials:
		_select_shared_body()
	elif not _material:
		_original_material = material_override
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	if not shared_materials: apply_lighting_to(_material)
	_last_flip_h = flip_h
	_last_flip_v = flip_v
	_last_tint = modulate
	_outline_state.clear()
	material_override = _material if _uses_custom_material() else _original_material
	_sync_outline()
	notify_property_list_changed()

func _sync_outline() -> void:
	if not is_inside_tree():
		return
	if not _occlusion_outline_allowed or not occlusion_outline_enabled or not texture or occlusion_outline_width <= 0.0 or occlusion_outline_opacity <= 0.0:
		_outline_state.clear()
		# @tool 重载后辅助节点可能仍在，缓存引用却已丢失；关闭时也须查找旧节点。
		var existing := _outline if is_instance_valid(_outline) else get_node_or_null("OcclusionOutline") as MeshInstance3D
		if is_instance_valid(existing):
			existing.visible = false
		return
	if not is_instance_valid(_outline):
		_outline = get_node_or_null("OcclusionOutline") as MeshInstance3D
		if not _outline:
			_outline = MeshInstance3D.new()
			_outline.name = "OcclusionOutline"
			_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_outline.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			_outline.extra_cull_margin = 0.1
			_outline.add_to_group("occlusion_outlines")
			add_child(_outline)
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OCCLUSION_SHADER
		_outline_material.render_priority = 1
		_outline.material_override = _outline_material
		_outline_mesh = QuadMesh.new()
		_outline.mesh = _outline_mesh
		_outline_pixel_size = -1.0
		_outline_state.clear()
	var rect := get_item_rect()
	var state: Array = [rect, pixel_size, texture, layers, billboard, flip_h, flip_v, modulate.a,
		occlusion_outline_color, occlusion_outline_width, occlusion_outline_opacity, occlusion_depth_bias]
	if state == _outline_state: return
	_outline_state = state
	if shared_materials:
		var mesh_key: Array = [rect, pixel_size]
		if not _shared_quads.has(mesh_key):
			var mesh := QuadMesh.new()
			mesh.size = rect.size * pixel_size
			var center := rect.get_center() * pixel_size
			mesh.center_offset = Vector3(center.x, center.y, 0.0)
			_shared_quads[mesh_key] = mesh
		_outline_mesh = _shared_quads[mesh_key]
		_outline.mesh = _outline_mesh
	if rect != _outline_rect or pixel_size != _outline_pixel_size:
		_outline_rect = rect
		_outline_pixel_size = pixel_size
		_outline_mesh.size = rect.size * pixel_size
		var center := rect.get_center() * pixel_size
		_outline_mesh.center_offset = Vector3(center.x, center.y, 0.0)
	_outline.layers = layers
	_outline.visible = true
	# A quad uses frame-local UVs; AtlasTexture shares its GPU image with the full sheet.
	var outline_texture := texture
	var outline_region := Vector4(0.0, 0.0, 1.0, 1.0)
	if texture is AtlasTexture and (texture as AtlasTexture).atlas:
		var atlas := texture as AtlasTexture
		outline_texture = atlas.atlas
		var atlas_size := outline_texture.get_size()
		var region := atlas.region
		if region.size == Vector2.ZERO:
			region.size = atlas_size
		var origin := region.position / atlas_size
		var extent := region.size / atlas_size
		outline_region = Vector4(origin.x, origin.y, extent.x, extent.y)
	if shared_materials:
		var key: Array = [outline_texture, outline_region, billboard, flip_h, flip_v, modulate.a,
			occlusion_outline_color, occlusion_outline_width, occlusion_outline_opacity, occlusion_depth_bias]
		if _shared_outlines.has(key):
			_outline_material = _shared_outlines[key]
			_outline.material_override = _outline_material
			return
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OCCLUSION_SHADER
		_outline_material.render_priority = 1
		_shared_outlines[key] = _outline_material
		_outline.material_override = _outline_material
	_outline_material.set_shader_parameter("sprite_texture", outline_texture)
	_outline_material.set_shader_parameter("sprite_region", outline_region)
	_outline_material.set_shader_parameter("fixed_y", billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
	_outline_material.set_shader_parameter("flip_h", flip_h)
	_outline_material.set_shader_parameter("flip_v", flip_v)
	_outline_material.set_shader_parameter("sprite_opacity", modulate.a)
	_outline_material.set_shader_parameter("outline_color", occlusion_outline_color)
	_outline_material.set_shader_parameter("outline_width", occlusion_outline_width)
	_outline_material.set_shader_parameter("outline_opacity", occlusion_outline_opacity)
	_outline_material.set_shader_parameter("depth_bias", occlusion_depth_bias)

func apply_lighting_to(material: ShaderMaterial, reflection := false) -> void:
	material.set_shader_parameter("sprite_texture", texture)
	material.set_shader_parameter("tint", modulate)
	material.set_shader_parameter("fixed_y", billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
	material.set_shader_parameter("mirror_view", reflection)
	material.set_shader_parameter("flip_h", flip_h)
	material.set_shader_parameter("flip_v", flip_v)
	material.set_shader_parameter("lighting_enabled", lighting_enabled)
	material.set_shader_parameter("light_wrap", light_wrap)
	material.set_shader_parameter("top_light_response", top_light_response)
	material.set_shader_parameter("back_rim_strength", back_rim_strength)
	material.set_shader_parameter("local_light_response", local_light_response)
	_bind_normal(material)

func _bind_normal(material: ShaderMaterial) -> void:
	var normal := normal_texture_override if normal_texture_override else SurfaceNormalMaps.for_texture(texture)
	var source := (texture as AtlasTexture).atlas if texture is AtlasTexture else texture
	if normal and source and normal.get_size() != source.get_size(): normal = null
	material.set_shader_parameter("normal_texture",normal)
	material.set_shader_parameter("normal_mapping_enabled",normal_mapping_enabled && normal != null)
	material.set_shader_parameter("normal_mapping_strength",normal_mapping_strength)
	var region := Vector4(0.0,0.0,1.0,1.0)
	if texture is AtlasTexture and (texture as AtlasTexture).atlas:
		var atlas := texture as AtlasTexture
		var size := atlas.atlas.get_size()
		var rect := atlas.region
		if rect.size == Vector2.ZERO: rect.size = size
		region = Vector4(rect.position.x / size.x,rect.position.y / size.y,rect.size.x / size.x,rect.size.y / size.y)
	material.set_shader_parameter("sprite_region",region)

func _validate_property(property: Dictionary) -> void:
	# Recreate the preview material on load instead of saving a generated override.
	if property.name == "material_override" and _material and material_override == _material:
		property.usage &= ~PROPERTY_USAGE_STORAGE
