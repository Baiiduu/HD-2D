@tool
class_name ArtDirection
extends Node

## 美术总控：把调画面最常用的参数集中在一个节点上。
## 在编辑器检查器里修改会实时生效；运行时也以这里的数值为准，
## 会覆盖环境、月光、天空、地面材质、光晕与后处理中的对应设置。

@export_group("引用")
@export var world_environment: WorldEnvironment:
	set(v): world_environment = v; _queue_apply()
@export var moon: DirectionalLight3D:
	set(v): moon = v; _queue_apply()
@export var terrain: Terrain:
	set(v): terrain = v; _queue_apply()
@export var post_process: CanvasItem:
	set(v): post_process = v; _queue_apply()
@export var water_reflection: PlanarWaterReflection:
	set(v): water_reflection = v; _queue_apply()

@export_group("水面")
@export var water_reflection_enabled := true:
	set(v): water_reflection_enabled = v; _queue_apply()
## 宽高比例：0.5 对应四分之一像素数量；可见的两个水位各用一张视图。
@export_range(0.25, 1.0, 0.05) var water_reflection_scale := 0.5:
	set(v): water_reflection_scale = v; _queue_apply()
@export_range(0.0, 1.5, 0.05) var water_reflection_strength := 0.85:
	set(v): water_reflection_strength = v; _queue_apply()
@export_range(0.0, 0.3, 0.01) var water_wave_strength := 0.08:
	set(v): water_wave_strength = v; _queue_apply()

@export_group("整体")
## 曝光：整体明暗，最直接的提亮手段
@export_range(0.2, 3.0, 0.01) var exposure := 1.3:
	set(v): exposure = v; _queue_apply()
@export_range(0.5, 2.0, 0.01) var brightness := 1.05:
	set(v): brightness = v; _queue_apply()
@export_range(0.5, 2.0, 0.01) var contrast := 1.05:
	set(v): contrast = v; _queue_apply()
@export_range(0.0, 2.0, 0.01) var saturation := 1.1:
	set(v): saturation = v; _queue_apply()
## 泛光强度：灯、霓虹的光晕扩散
@export_range(0.0, 2.0, 0.01) var bloom := 0.8:
	set(v): bloom = v; _queue_apply()

@export_group("环境光与月光")
## 环境光：决定阴影里的颜色和亮度
@export var ambient_color := Color(0.5, 0.48, 0.52):
	set(v): ambient_color = v; _queue_apply()
@export_range(0.0, 3.0, 0.01) var ambient_energy := 0.7:
	set(v): ambient_energy = v; _queue_apply()
@export var moon_color := Color(0.9, 0.86, 0.8):
	set(v): moon_color = v; _queue_apply()
@export_range(0.0, 4.0, 0.01) var moon_energy := 0.85:
	set(v): moon_energy = v; _queue_apply()

@export_group("雾")
## 雾色：同时用于距离雾、天空地平线、地图边缘
@export var fog_color := Color(0.38, 0.35, 0.4):
	set(v): fog_color = v; _queue_apply()
## 距离雾：从多远开始起雾、到多远达到最浓（米）
@export_range(0.0, 100.0, 0.5) var fog_begin := 14.0:
	set(v): fog_begin = v; _queue_apply()
@export_range(1.0, 200.0, 0.5) var fog_end := 50.0:
	set(v): fog_end = v; _queue_apply()
## 最远处雾的浓度（0 = 无雾，1 = 完全看不见）
@export_range(0.0, 1.0, 0.01) var fog_amount := 0.7:
	set(v): fog_amount = v; _queue_apply()
## 低处（溪谷）额外的雾
@export_range(0.0, 2.0, 0.01) var low_fog := 0.3:
	set(v): low_fog = v; _queue_apply()
## 地图最外圈多少米逐渐融进雾色，0 = 关闭
@export_range(0.0, 20.0, 0.1) var map_edge_fog := 0.0:
	set(v): map_edge_fog = v; _queue_apply()
## 体积雾：让灯光在空气里有光晕，过大会让画面发白
@export var volumetric_fog := true:
	set(v): volumetric_fog = v; _queue_apply()
@export_range(0.0, 0.1, 0.001) var volumetric_density := 0.006:
	set(v): volumetric_density = v; _queue_apply()

@export_group("天空")
@export var sky_top_color := Color(0.05, 0.05, 0.11):
	set(v): sky_top_color = v; _queue_apply()
## 远景剪影（远山、松林）最近一层的颜色
@export var silhouette_color := Color(0.1, 0.09, 0.13):
	set(v): silhouette_color = v; _queue_apply()
## 北方地平线的暖色辉光
@export var horizon_glow_color := Color(0.75, 0.42, 0.24):
	set(v): horizon_glow_color = v; _queue_apply()
@export_range(0.0, 2.0, 0.01) var horizon_glow := 0.5:
	set(v): horizon_glow = v; _queue_apply()
@export_range(0.0, 0.05, 0.001) var stars := 0.01:
	set(v): stars = v; _queue_apply()

@export_group("地面")
## 地面湿润程度：0 干燥，1 雨后（灯光倒影随之变强）
@export_range(0.0, 1.0, 0.01) var wetness := 0.4:
	set(v): wetness = v; _queue_apply()
@export var puddles := false:
	set(v): puddles = v; _queue_apply()
## 积水多少（仅在开启积水时有效）
@export_range(0.0, 1.0, 0.01) var puddle_amount := 0.4:
	set(v): puddle_amount = v; _queue_apply()

@export_group("灯光与后处理")
## 灯头光晕亮度
@export_range(0.0, 2.0, 0.01) var halo_energy := 0.35:
	set(v): halo_energy = v; _queue_apply()
@export_range(0.0, 1.0, 0.01) var vignette := 0.3:
	set(v): vignette = v; _queue_apply()
## 分离色调：暗部偏冷、亮部偏暖的程度
@export_range(0.0, 1.0, 0.01) var split_toning := 0.25:
	set(v): split_toning = v; _queue_apply()

var _apply_queued := false

func _ready() -> void:
	if not Engine.is_editor_hint() and "--no-reflection" in OS.get_cmdline_user_args():
		water_reflection_enabled = false
	apply()

func _queue_apply() -> void:
	if _apply_queued or not is_inside_tree():
		return
	_apply_queued = true
	apply.call_deferred()

func apply() -> void:
	_apply_queued = false
	if water_reflection and not Engine.is_editor_hint():
		water_reflection.enabled = water_reflection_enabled
		water_reflection.resolution_scale = water_reflection_scale
		water_reflection.strength = water_reflection_strength
		water_reflection.wave_strength = water_wave_strength
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.tonemap_exposure = exposure
		env.adjustment_enabled = true
		env.adjustment_brightness = brightness
		env.adjustment_contrast = contrast
		env.adjustment_saturation = saturation
		env.glow_intensity = bloom
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = ambient_energy
		env.fog_light_color = fog_color
		env.fog_depth_begin = fog_begin
		env.fog_depth_end = maxf(fog_end, fog_begin + 1.0)
		env.fog_density = fog_amount
		env.fog_height_density = low_fog
		env.volumetric_fog_enabled = volumetric_fog
		env.volumetric_fog_density = volumetric_density
		var sky := env.sky.sky_material as ShaderMaterial if env.sky else null
		if sky:
			sky.set_shader_parameter("zenith_color", sky_top_color)
			sky.set_shader_parameter("horizon_color", fog_color)
			sky.set_shader_parameter("fog_color", fog_color)
			sky.set_shader_parameter("silhouette_color", silhouette_color)
			sky.set_shader_parameter("glow_color", horizon_glow_color)
			sky.set_shader_parameter("glow_strength", horizon_glow)
			sky.set_shader_parameter("star_density", stars)
	if moon:
		moon.light_color = moon_color
		moon.light_energy = moon_energy
	if terrain and terrain.top_material:
		var ground := terrain.top_material
		ground.set_shader_parameter("wetness", wetness)
		ground.set_shader_parameter("puddles", puddles)
		ground.set_shader_parameter("puddle_threshold", 1.0 - puddle_amount)
		ground.set_shader_parameter("edge_fog_color", fog_color)
		ground.set_shader_parameter("edge_fade_distance", map_edge_fog)
	if post_process and post_process.material is ShaderMaterial:
		var post := post_process.material as ShaderMaterial
		post.set_shader_parameter("vignette_strength", vignette)
		post.set_shader_parameter("split_toning", split_toning)
	if is_inside_tree():
		_apply_halos(get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene)

## 场景里所有名为 Halo 的光晕面片（包括灯笼子场景里的）
func _apply_halos(root: Node) -> void:
	if not root:
		return
	for node in root.find_children("Halo", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh and mesh.surface_get_material(0) is ShaderMaterial:
			(mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("energy", halo_energy)
