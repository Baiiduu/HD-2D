@tool
extends Sprite3D

const SHADER := preload("res://shaders/character_lighting.gdshader")
const OCCLUSION_SHADER := preload("res://shaders/character_occlusion.gdshader")

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

func _ready() -> void:
	process_priority = 1 # Sync flips after Player has selected this frame's facing.
	apply_lighting()

func _process(_delta: float) -> void:
	# An already-open @tool scene may not receive _ready after a script reload.
	if not _material:
		apply_lighting()
	if lighting_enabled:
		_material.set_shader_parameter("flip_h", flip_h)
		_material.set_shader_parameter("flip_v", flip_v)
		_material.set_shader_parameter("tint", modulate)
	_sync_outline()

func _queue_apply() -> void:
	if not is_inside_tree() or _apply_queued:
		return
	_apply_queued = true
	apply_lighting.call_deferred()

func _sync_texture() -> void:
	if _material:
		_material.set_shader_parameter("sprite_texture", texture)
	else:
		_queue_apply()

func apply_lighting() -> void:
	_apply_queued = false
	if not texture_changed.is_connected(_sync_texture):
		texture_changed.connect(_sync_texture)
	var defaults := {"lighting_enabled": true, "light_wrap": 0.3,
		"top_light_response": 0.4, "back_rim_strength": 0.12,
		"occlusion_outline_enabled": true, "occlusion_outline_color": Color(1.0, 0.89, 0.55),
		"occlusion_outline_width": 1.0, "occlusion_outline_opacity": 0.85, "occlusion_depth_bias": 0.03}
	for key in defaults:
		if get(key) == null:
			set(key, defaults[key])
	if not _material:
		_original_material = material_override
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	apply_lighting_to(_material)
	material_override = _material if lighting_enabled else _original_material
	_sync_outline()
	notify_property_list_changed()

func _sync_outline() -> void:
	if not is_inside_tree():
		return
	if not occlusion_outline_enabled or not texture or occlusion_outline_width <= 0.0 or occlusion_outline_opacity <= 0.0:
		if is_instance_valid(_outline):
			_outline.visible = false
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
	var rect := get_item_rect()
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

func _validate_property(property: Dictionary) -> void:
	# Recreate the preview material on load instead of saving a generated override.
	if property.name == "material_override" and _material and material_override == _material:
		property.usage &= ~PROPERTY_USAGE_STORAGE
