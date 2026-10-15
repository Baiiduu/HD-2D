@tool
class_name NightAtmosphere
extends Node3D
## Reusable scene-local atmosphere. Markers author the layout; cached batches animate on the GPU.

const SHAFT = preload("res://shaders/visual/atmosphere_shaft.gdshader")
const TREE = preload("res://shaders/visual/atmosphere_tree.gdshader")
const CITY_FOLIAGE = preload("res://shaders/visual/atmosphere_city_foliage.gdshader")
const SMOKE = preload("res://shaders/visual/atmosphere_smoke.gdshader")
const MOTES = preload("res://shaders/visual/atmosphere_motes.gdshader")
const FLAME = preload("res://shaders/visual/atmosphere_flame.gdshader")
const LEAVES = preload("res://shaders/visual/atmosphere_leaves.gdshader")
const GRASS = preload("res://shaders/environment/vegetation_wind.gdshader")
const BOKEH_SCRIPT = preload("res://scripts/visual/hdr_bokeh.gd")
const GRASS_TEXTURES := ["res://assets/meowa/dressing/grass/grass_01.png", "res://assets/meowa/dressing/grass/grass_03.png"]

@export_group("连接")
@export var camera: Camera3D
@export var moon: DirectionalLight3D
@export var weather: Node3D
@export var vegetation_root: Node3D
@export var editor_preview := true
@export_tool_button("重建效果", "Reload") var rebuild_button = rebuild

@export_group("独立开关")
@export var enabled := true:
	set(value): enabled = value; _queue_apply()
@export var shafts_enabled := true:
	set(value): shafts_enabled = value; _queue_apply()
@export var smoke_enabled := true:
	set(value): smoke_enabled = value; _queue_apply()
@export var motes_enabled := true:
	set(value): motes_enabled = value; _queue_apply()
@export var wind_enabled := true:
	set(value): wind_enabled = value; _queue_apply()
@export var flame_enabled := true:
	set(value): flame_enabled = value; _queue_apply()
@export var leaves_enabled := true:
	set(value): leaves_enabled = value; _queue_apply()
@export var bokeh_enabled := true:
	set(value): bokeh_enabled = value; _queue_apply()

@export_group("风、月光与烟")
@export var wind_direction := Vector2(1.0, 0.35)
@export_range(0.0, 3.0, 0.05) var wind_multiplier := 0.65
@export_range(0.0, 0.5, 0.01) var moon_shafts_energy := 0.09
@export_range(0.0, 1.0, 0.01) var lamp_shafts_energy := 0.24
@export_range(0.0, 0.6, 0.01) var smoke_opacity := 0.2
@export_range(0.0, 0.3, 0.01) var tree_flexibility := 0.11
@export_range(0.0, 0.3, 0.01) var grass_flexibility := 0.045
@export var bokeh: HDRBokeh

var _generated: Node3D
var _materials: Array[ShaderMaterial] = []
var _tree_materials: Array[ShaderMaterial] = []
var _tree_originals: Dictionary = {}
var _kit_originals: Dictionary = {}
var _grass_materials: Array[ShaderMaterial] = []
var _groups: Dictionary = {}
var _lamps: Array[OmniLight3D] = []
var _lamp_colors: Array[Color] = []
var _lamp_shaft_materials: Array[ShaderMaterial] = []
var _lamp_surfaces: Array[StandardMaterial3D] = []
var _moon_material: ShaderMaterial
var _lamp_material: ShaderMaterial
var _smoke_material: ShaderMaterial
var _fire_light: OmniLight3D
var _foreground: MultiMeshInstance3D
var _clock := 0.0
var _queued := false
var _rng := RandomNumberGenerator.new()
var _compositor: Compositor
var _prior_compositor: Compositor
var _prior_dof_mode := 0

func _ready() -> void:
	if camera is FollowCamera: _prior_dof_mode = (camera as FollowCamera).dof_mode
	rebuild()
	if not Engine.is_editor_hint(): _connect_bokeh.call_deferred()

func _queue_apply() -> void:
	if _queued or not is_inside_tree(): return
	_queued = true
	_apply_parameters.call_deferred()

func _material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	_materials.append(material)
	return material

func _group(id: String) -> Node3D:
	var group := Node3D.new()
	group.name = id.capitalize().replace(" ", "")
	_generated.add_child(group)
	_groups[id] = group
	return group

func rebuild() -> void:
	if not is_inside_tree(): return
	if is_instance_valid(_generated):
		_generated.free()
	_materials.clear()
	_tree_materials.clear()
	_grass_materials.clear()
	_lamps.clear()
	_lamp_colors.clear()
	_lamp_shaft_materials.clear()
	_lamp_surfaces.clear()
	_groups.clear()
	_rng.seed = 92609
	_generated = Node3D.new()
	_generated.name = "AtmosphereBatches"
	add_child(_generated)
	for id in ["shafts", "smoke", "motes", "plants", "fire", "leaves"]: _group(id)
	_moon_material = _material(SHAFT)
	_lamp_material = _material(SHAFT)
	_lamp_material.set_shader_parameter("light_color", Color(1.0, 0.76, 0.43))
	_lamp_material.set_shader_parameter("light_direction", Vector3.UP)
	_lamp_material.set_shader_parameter("near_fade", Vector2(1.0, 4.0))
	_smoke_material = _material(SMOKE)
	for marker: Node3D in $MoonShafts.get_children():
		_shaft(marker.name, marker.global_position, _moon_material, 12.0, 2.2, 0.65)
	for marker: Node3D in $SmokeSources.get_children():
		_batch(marker.name, _groups.smoke, _smoke_material, 16, marker.global_position, Vector3(4, 7, 4))
	_prepare_lamps()
	_prepare_plants()
	_bind_kit_wind()
	_prepare_fire()
	var motes := _material(MOTES)
	motes.set_shader_parameter("box_size", Vector3(18, 3, 14))
	motes.set_shader_parameter("energy", 4.0)
	_batch("PlazaDust", _groups.motes, motes, 32, global_position + Vector3(0, 1.8, 3), Vector3(20, 5, 16))
	var foreground_material := _material(MOTES)
	foreground_material.set_shader_parameter("box_size", Vector3(13, 3, 5))
	foreground_material.set_shader_parameter("particle_size", 0.035)
	foreground_material.set_shader_parameter("energy", 4.5)
	_foreground = _batch("ForegroundHighlights", _groups.motes, foreground_material, 10, global_position + Vector3(0, 4, 7), Vector3(16, 5, 8))
	_apply_parameters()

func _batch(id: String, parent: Node3D, material: ShaderMaterial, count: int, at: Vector3, bounds: Vector3) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	for index in count:
		multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))
	var batch := MultiMeshInstance3D.new()
	batch.name = id
	batch.multimesh = multimesh
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.custom_aabb = AABB(-bounds * 0.5, bounds)
	parent.add_child(batch)
	batch.global_position = at
	return batch

func _shaft(id: String, at: Vector3, material: ShaderMaterial, length: float, width: float, top: float) -> void:
	var quad := QuadMesh.new()
	quad.subdivide_depth = 6
	quad.material = material
	var shaft := MeshInstance3D.new()
	shaft.name = id
	shaft.mesh = quad
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.custom_aabb = AABB(Vector3.ONE * -(length + width), Vector3.ONE * (length + width) * 2.0)
	_groups.shafts.add_child(shaft)
	shaft.global_position = at
	shaft.set_instance_shader_parameter("shaft_length", length)
	shaft.set_instance_shader_parameter("shaft_width", width)
	shaft.set_instance_shader_parameter("shaft_top_width", top)
	shaft.set_instance_shader_parameter("shaft_seed", _rng.randf() * 10.0)

func _prepare_lamps() -> void:
	if not vegetation_root: return
	for lamp: Node3D in vegetation_root.get_children():
		if not str(lamp.name).begins_with("Lamp"): continue
		var light := lamp.get_node_or_null("Light") as OmniLight3D
		if not light: continue
		_lamps.append(light)
		_lamp_colors.append(light.light_color)
		var mesh := lamp.get_node_or_null("Lantern/Mesh") as MeshInstance3D
		if mesh:
			var original := mesh.get_active_material(0) as StandardMaterial3D
			if original:
				var material := original.duplicate() as StandardMaterial3D
				mesh.material_override = material
				_lamp_surfaces.append(material)
		for surface_mesh: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
			for surface in surface_mesh.mesh.get_surface_count():
				var original := surface_mesh.get_active_material(surface) as StandardMaterial3D
				if original and str(original.resource_name).begins_with("Glow"):
					var material := original.duplicate() as StandardMaterial3D
					surface_mesh.set_surface_override_material(surface, material)
					_lamp_surfaces.append(material)
		var shaft_material := _lamp_material.duplicate() as ShaderMaterial
		shaft_material.set_shader_parameter("light_color", light.light_color)
		_materials.append(shaft_material)
		_lamp_shaft_materials.append(shaft_material)
		_shaft("%sLightCone" % lamp.name, lamp.global_position + Vector3(0, 0.05, 0), shaft_material, light.position.y, 2.0, 0.14)
		var dust := _material(MOTES)
		dust.set_shader_parameter("box_size", Vector3(2.0, 2.2, 2.0))
		dust.set_shader_parameter("particle_size", 0.025)
		dust.set_shader_parameter("energy", 3.0)
		dust.set_shader_parameter("glow_color", light.light_color)
		_batch("%sDust" % lamp.name, _groups.motes, dust, 8, lamp.global_position + Vector3(0, 1.2, 0), Vector3(3, 3, 3))

func _prepare_plants() -> void:
	if not vegetation_root: return
	for planter: Node3D in vegetation_root.get_children():
		var soil := planter.get_node_or_null("Soil/Mesh") as MeshInstance3D
		var extent := Vector3.ZERO
		var plant_root := planter.global_position + Vector3.UP * 0.46
		if soil and soil.mesh is BoxMesh:
			extent = (soil.mesh as BoxMesh).size
			plant_root = soil.global_position
		else:
			var shape := planter.get_node_or_null("Collision/Shape0") as CollisionShape3D
			if shape and shape.shape is BoxShape3D:
				var size := (shape.shape as BoxShape3D).size
				if size.y < 0.6 and minf(size.x, size.z) > 1.0: extent = size
		if extent == Vector3.ZERO: continue
		for part: Node in planter.get_children():
			var mesh: MeshInstance3D
			if str(part.name).begins_with("Canopy"): mesh = part as MeshInstance3D
			elif part.name == &"Trunk": mesh = part.get_node_or_null("Mesh") as MeshInstance3D
			if not mesh: continue
			var original := _tree_originals.get(mesh, mesh.get_active_material(0)) as StandardMaterial3D
			if not original: continue
			_tree_originals[mesh] = original
			var material := _material(TREE)
			material.resource_name = "CanopyWind" if str(part.name).begins_with("Canopy") else "TrunkWind"
			material.set_shader_parameter("surface_color", original.albedo_color)
			material.set_shader_parameter("flexibility", tree_flexibility if str(part.name).begins_with("Canopy") else tree_flexibility * 0.5)
			_tree_materials.append(material)
			mesh.material_override = material
			mesh.extra_cull_margin = 0.4
			mesh.set_instance_shader_parameter("plant_root", plant_root)
			mesh.set_instance_shader_parameter("plant_height", 3.4)
		for texture_path in GRASS_TEXTURES:
			var texture := load(texture_path) as Texture2D
			var grass := ShaderMaterial.new()
			grass.shader = GRASS
			grass.set_shader_parameter("sprite_texture", texture)
			grass.set_shader_parameter("stable_shadows", false)
			grass.set_shader_parameter("root_uv", 0.92)
			grass.set_shader_parameter("flexibility", grass_flexibility)
			_grass_materials.append(grass)
			var height := texture.get_height() / 40.0 * 0.22
			var quad := QuadMesh.new()
			quad.size = texture.get_size() / 40.0 * 0.22
			quad.material = grass
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.use_custom_data = true
			batch.mesh = quad
			batch.instance_count = 12
			for index in batch.instance_count:
				var point := Vector3(_rng.randf_range(-extent.x, extent.x) * 0.4, height * 0.42, _rng.randf_range(-extent.z, extent.z) * 0.4)
				batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))
				batch.set_instance_custom_data(index, Color(height * 0.42, 0, 0, 0))
			var field := MultiMeshInstance3D.new()
			field.name = "%sGrass%d" % [planter.name, _grass_materials.size()]
			field.multimesh = batch
			field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			field.extra_cull_margin = 0.3
			_groups.plants.add_child(field)
			field.global_transform = Transform3D(planter.global_basis, plant_root + Vector3.UP * 0.04)
		var leaves := _material(LEAVES)
		var world_extent := planter.global_basis.x.abs() * extent.x + planter.global_basis.z.abs() * extent.z
		leaves.set_shader_parameter("box_size", Vector3(world_extent.x, 3.0, world_extent.z))
		_batch("%sLeaves" % planter.name, _groups.leaves, leaves, 5, plant_root + Vector3.UP * 1.5, Vector3(extent.x + 2, 4, extent.z + 2))

func _bind_kit_wind() -> void:
	if not vegetation_root: return
	var shared: Dictionary = {}
	for mesh: MeshInstance3D in vegetation_root.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh: continue
		for surface in mesh.mesh.get_surface_count():
			var original: Material = _kit_originals.get(mesh, {}).get(surface, mesh.get_active_material(surface))
			if not original is ShaderMaterial: continue
			var source := original as ShaderMaterial
			if not source.shader or source.shader.resource_path != "res://shaders/city_foliage.gdshader": continue
			if not _kit_originals.has(mesh): _kit_originals[mesh] = {}
			_kit_originals[mesh][surface] = original
			if not shared.has(original):
				var material := source.duplicate() as ShaderMaterial
				material.shader = CITY_FOLIAGE
				shared[original] = material
				_materials.append(material)
				_tree_materials.append(material)
			mesh.set_surface_override_material(surface, shared[original])
			mesh.extra_cull_margin = 0.4
			mesh.set_instance_shader_parameter("plant_root", mesh.global_position + Vector3.UP * 0.45)
			mesh.set_instance_shader_parameter("plant_height", maxf(mesh.get_aabb().size.y - 0.45, 0.5))

func _prepare_fire() -> void:
	_fire_light = null
	for marker: Node3D in $FireSources.get_children():
		var flame := MeshInstance3D.new()
		flame.name = "%sFlame" % marker.name
		var quad := QuadMesh.new()
		quad.size = Vector2(0.42, 0.65)
		quad.material = _material(FLAME)
		flame.mesh = quad
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_groups.fire.add_child(flame)
		flame.global_position = marker.global_position + Vector3.UP * 0.6
		var bowl := MeshInstance3D.new()
		bowl.name = "%sBrazier" % marker.name
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.23
		cylinder.bottom_radius = 0.19
		cylinder.height = 0.3
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.17, 0.18, 0.19)
		metal.roughness = 0.85
		cylinder.material = metal
		bowl.mesh = cylinder
		_groups.fire.add_child(bowl)
		bowl.global_position = marker.global_position + Vector3.UP * 0.15
		_fire_light = OmniLight3D.new()
		_fire_light.name = "%sWarmLight" % marker.name
		_fire_light.light_color = Color(1.0, 0.47, 0.12)
		_fire_light.omni_range = 3.4
		_fire_light.shadow_enabled = true
		_groups.fire.add_child(_fire_light)
		_fire_light.global_position = marker.global_position + Vector3.UP * 0.65
		var embers := _material(MOTES)
		embers.set_shader_parameter("embers", true)
		embers.set_shader_parameter("particle_size", 0.045)
		embers.set_shader_parameter("energy", 5.0)
		embers.set_shader_parameter("glow_color", Color(1.0, 0.32, 0.045))
		_batch("%sEmbers" % marker.name, _groups.fire, embers, 16, marker.global_position + Vector3.UP * 0.45, Vector3(3, 5, 3))
		_batch("%sSmoke" % marker.name, _groups.smoke, _smoke_material, 12, marker.global_position + Vector3.UP * 0.8, Vector3(4, 7, 4))

func _connect_bokeh() -> void:
	if not camera or not RenderingServer.get_rendering_device(): return
	if not bokeh: bokeh = BOKEH_SCRIPT.new()
	_prior_compositor = camera.compositor
	_compositor = Compositor.new()
	var effects: Array[CompositorEffect] = []
	if _prior_compositor: effects.assign(_prior_compositor.compositor_effects)
	effects.append(bokeh)
	_compositor.compositor_effects = effects
	camera.compositor = _compositor
	_apply_parameters()

func _apply_parameters() -> void:
	_queued = false
	if not is_instance_valid(_generated): return
	_generated.visible = enabled
	set_process(enabled and (editor_preview or not Engine.is_editor_hint()))
	_groups.shafts.visible = shafts_enabled
	_groups.smoke.visible = smoke_enabled
	_groups.motes.visible = motes_enabled
	_groups.fire.visible = flame_enabled
	_groups.leaves.visible = leaves_enabled
	_smoke_material.set_shader_parameter("opacity", smoke_opacity)
	_moon_material.set_shader_parameter("energy", moon_shafts_energy)
	_lamp_material.set_shader_parameter("energy", lamp_shafts_energy)
	for material in _lamp_shaft_materials: material.set_shader_parameter("energy", lamp_shafts_energy)
	for index in _lamps.size():
		var light := _lamps[index]
		light.light_energy = 2.8
		light.light_color = _lamp_colors[index]
		light.omni_range = 5.5
	for material in _lamp_surfaces:
		material.emission_enabled = true
		material.emission_energy_multiplier = 3.0
	if bokeh:
		bokeh.enabled = enabled and bokeh_enabled
		if camera is FollowCamera: (camera as FollowCamera).dof_mode = 2 if bokeh.enabled and _compositor else 0
	if _fire_light: _fire_light.light_energy = 2.5 if enabled and flame_enabled else 0.0
	_update_uniforms()

func _update_uniforms() -> void:
	var wind := wind_direction * wind_multiplier
	if weather:
		wind = weather.get("wind_direction") * float(weather.get("wind_strength")) * wind_multiplier
		if not bool(weather.get("wind_enabled")): wind = Vector2.ZERO
	if not enabled or not wind_enabled: wind = Vector2.ZERO
	for material in _materials:
		material.set_shader_parameter("atmosphere_clock", _clock)
		material.set_shader_parameter("atmosphere_wind", wind)
	for material in _grass_materials:
		material.set_shader_parameter("wind_time", _clock)
		material.set_shader_parameter("wind_direction", wind.normalized() if wind.length_squared() > 0.001 else Vector2.RIGHT)
		material.set_shader_parameter("wind_strength", wind.length())
	for material in _tree_materials:
		if material.shader == TREE:
			material.set_shader_parameter("flexibility", tree_flexibility * (0.5 if material.resource_name == "TrunkWind" else 1.0))
	for material in _grass_materials: material.set_shader_parameter("flexibility", grass_flexibility)
	if moon:
		_moon_material.set_shader_parameter("light_direction", moon.global_basis.z.normalized())
		_moon_material.set_shader_parameter("light_color", moon.light_color)
	if _foreground and camera and not Engine.is_editor_hint():
		_foreground.global_position = camera.global_position - camera.global_basis.z * 17.0
	if bokeh and camera is FollowCamera and not Engine.is_editor_hint():
		bokeh.enabled = enabled and bokeh_enabled and (camera as FollowCamera).dof_enabled
		var follow := camera as FollowCamera
		var focus := follow.target.get_global_transform_interpolated().origin + Vector3.UP * follow.focus_height
		var focus_depth := maxf(camera.near, -(camera.global_transform.affine_inverse() * focus).z)
		bokeh.set_camera_state(focus_depth, camera.near, camera.far)

func _process(delta: float) -> void:
	_clock += delta
	_update_uniforms()
	if _fire_light and flame_enabled:
		_fire_light.light_energy = 2.5 * (0.86 + 0.1 * sin(_clock * 4.6) + 0.04 * sin(_clock * 11.1))

func _exit_tree() -> void:
	if is_instance_valid(camera) and _compositor and camera.compositor == _compositor:
		camera.compositor = _prior_compositor
		if camera is FollowCamera: (camera as FollowCamera).dof_mode = _prior_dof_mode
	for mesh: MeshInstance3D in _tree_originals:
		if is_instance_valid(mesh): mesh.material_override = _tree_originals[mesh]
	for mesh: MeshInstance3D in _kit_originals:
		if is_instance_valid(mesh):
			for surface in _kit_originals[mesh]: mesh.set_surface_override_material(surface, _kit_originals[mesh][surface])
