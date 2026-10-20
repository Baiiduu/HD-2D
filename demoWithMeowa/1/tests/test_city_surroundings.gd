extends SceneTree
## 仅检查静态资源、战区留空与取景射线；视觉观感由正式地图人工验收。

const SCENE := "res://scenes/world/city_surroundings.tscn"
const WORLD := "res://scenes/world/world.tscn"
const BATTLE := Rect2(-16.0, 28.8, 32.0, 32.0)
class SkyFixture extends Node3D:
	var terrain: Terrain

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	check(ResourceLoader.exists(SCENE), "Formal map has the exterior city scene")
	if not ResourceLoader.exists(SCENE):
		finish()
		return
	var city := load(SCENE).instantiate() as Node3D
	var city_state := (load(SCENE) as PackedScene).get_state()
	root.add_child(city)
	check(not city.has_node("Foundations"), "The city blends its real surfaces into the background without separate foundation blocks")
	check(city.get_meta(&"setback_m", 0.0) >= 10.0, "The complete city group is set farther away from the battlefield")
	check(is_equal_approx(Vector2(city.position.x, city.position.z - 44.8).length(), city.get_meta(&"setback_m", 0.0)), "The setback is present in the actual scene transform")
	check(city.get_node("MechStation").position.y > -18.0, "The mech station is raised relative to the surrounding city")
	check(city.find_children("*", "CollisionObject3D", true, false).is_empty(), "Backdrop creates no physical obstacles")
	check(city.find_children("*", "NavigationRegion3D", true, false).is_empty(), "Backdrop creates no navigation regions")
	check(city.find_children("*", "Light3D", true, false).is_empty(), "Backdrop adds no real light sources")
	check(city.find_children("*", "AnimationPlayer", true, false).is_empty(), "Train remains static")
	check(city.get_node("StreetBlocks").get_child_count() == 6, "Six low street blocks frame the battlefield")
	check(city.get_node("Towers").get_child_count() == 4, "Four staggered towers provide the skyline")
	check(city.get_node("ElevatedRail/Train").get_child_count() == 3, "Static train has two cabs and one carriage")
	var boxes: Array[AABB] = []
	var heights: Array[float] = []
	var materials: Dictionary = {}
	var shaders: Dictionary = {}
	var textures: Dictionary = {}
	var triangles := 0
	for mesh: MeshInstance3D in city.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		boxes.append(box)
		var footprint := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		check(not footprint.intersects(BATTLE.grow(8.0)), "All displayed geometry stays beyond the battle area and its buffer")
		var local_center := city.to_local(box.get_center())
		check(local_center.z < -25.0 and absf(atan2(local_center.x, -local_center.z)) < deg_to_rad(40.0), "All exterior pieces form one forward-facing city sector")
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Distant geometry casts no dynamic shadows")
		check(mesh.gi_mode == GeometryInstance3D.GI_MODE_DISABLED, "Distant geometry adds no GI workload")
		check(mesh.is_in_group(&"distant_city_geometry"), "Distant surfaces opt out of planar reflection copies")
		check(mesh.get_script() == null, "Static geometry runs no per-object script")
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as ShaderMaterial
			check(material != null and material.shader.resource_path == "res://shaders/environment/city_background_blend.gdshader", "Original city surfaces use the shared lit background blending shader")
			if material:
				materials[material] = true
				shaders[material.shader] = true
				var texture: Texture2D = material.get_shader_parameter("albedo_texture")
				if texture: textures[texture] = true
				check(mesh.mesh.surface_get_material(i) == material, "Shared mesh materials do not retain unused imported texture copies")
				check(material.get_shader_parameter("emission_energy") <= 0.3, "Distant emissions stay restrained")
				var backdrop: Texture2D = material.get_shader_parameter("background_texture")
				check(backdrop != null and backdrop.resource_path == "res://assets/meowa/environment/distant_city/city_matte.png", "Model blending reuses the original painted background")
			var arrays := mesh.mesh.surface_get_arrays(i)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size() / 3
	check(triangles < 14000, "Exterior geometry stays within the first-pass triangle budget")
	check(materials.size() <= 16, "City instances share their material resources")
	check(shaders.size() == 1, "Every city material uses the same shader without overlay passes")
	check(textures.size() == 2, "All city pieces reuse only the existing street and structure atlases")
	for structure: Node3D in blending_structures(city):
		var bounds := group_bounds(structure)
		for mesh: MeshInstance3D in structure.find_children("*", "MeshInstance3D", true, false):
			var profile: Variant = node_property(city_state, String(city.get_path_to(mesh)), &"instance_shader_parameters/blend_profile")
			check(profile is Vector3, "Each real model saves an explicit linear blend band")
			if profile is Vector3:
				check(absf(mesh.global_position.y + profile.x - bounds.position.y) < 0.01, "Connected pieces blend from the same actual structure bottom")
				check(profile.y >= 2.0 and profile.y < bounds.size.y * 0.75, "The lower body blends while the upper silhouette remains readable")
				check(profile.z >= 0.0 and profile.z < 0.4, "Upper surfaces retain most of their shaded structure")
	for block: Node3D in city.get_node("StreetBlocks").get_children():
		var top := -INF
		for mesh: MeshInstance3D in block.find_children("*", "MeshInstance3D", true, false):
			top = maxf(top, (mesh.global_transform * mesh.get_aabb()).end.y)
		heights.append(top)
		check(faces_battlefield(block), "Street facades face back toward the player and battlefield")
	check(faces_battlefield(city.get_node("MechStation")), "The mech presents its front toward the player")
	check(heights.max() - heights.min() > 2.0, "Street roofs have deliberate height variation")
	check(camera_obstructions(boxes) == 0, "Exterior geometry never intersects sampled camera-to-combat sightlines")
	check(in_default_view(city.get_node("MechStation")), "Mech station has a visible silhouette in the default gameplay framing")
	check(in_default_view(city.get_node("ElevatedRail/Train")), "Static train is visible in the default gameplay framing")
	check(visible_vertices(city.get_node("MechStation/SentinelMech")) >= 4, "The mech itself emerges beyond the battle ground silhouette")
	for car in city.get_node("ElevatedRail/Train").get_children():
		check(visible_vertices(car) >= 4, "Every train carriage emerges beyond the battle ground silhouette")
	var state := (load(WORLD) as PackedScene).get_state()
	var city_node := node_index(state, "CitySurroundings")
	check(city_node >= 0, "World directly instances the new city exterior")
	if city_node >= 0:
		check(state.get_node_instance(city_node).resource_path == SCENE, "World uses the reviewed city scene")
	check(node_property(state, "WavePrototype", &"battle_area") == BATTLE, "Formal battle bounds remain 32 by 32 metres")
	check(is_equal_approx(node_property(state, "MapEffects/Camera3D", &"fov"), 28.0) and is_equal_approx(node_property(state, "MapEffects/Camera3D", &"distance"), 30.0) and is_equal_approx(node_property(state, "MapEffects/Camera3D", &"pitch_degrees"), 30.627), "Base gameplay framing is preserved")
	var environment: Environment = node_property(state, "MapEffects/WorldEnvironment", &"environment")
	var sky := environment.sky.sky_material as ShaderMaterial
	check(sky.get_shader_parameter("city_matte_enabled") == true, "World retains its original painted distant background")
	var matte: Texture2D = sky.get_shader_parameter("city_matte")
	check(matte != null and matte.resource_path == "res://assets/meowa/environment/distant_city/city_matte.png", "The original background artwork remains connected")
	check(node_property(state, "MapEffects/Aurora", &"enabled") == true, "The World aurora controller remains enabled")
	await aurora_binding_check(environment, state)
	reflection_exclusion_check()
	city.queue_free()
	await process_frame
	print("Exterior geometry: ", triangles, " triangles, ", materials.size(), " shared materials")
	finish()

func node_index(state: SceneState, path: String) -> int:
	for i in state.get_node_count():
		if String(state.get_node_path(i)).trim_prefix("./") == path: return i
	return -1

func blending_structures(city: Node3D) -> Array[Node]:
	var structures: Array[Node] = []
	structures.append_array(city.get_node("StreetBlocks").get_children())
	structures.append_array(city.get_node("Towers").get_children())
	structures.append(city.get_node("MechStation"))
	structures.append(city.get_node("ElevatedRail"))
	return structures

func group_bounds(group: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func faces_battlefield(node: Node3D) -> bool:
	var to_player := Vector3(0, 0, 44.8) - node.global_position
	to_player.y = 0.0
	var front := node.global_basis.z
	front.y = 0.0
	return front.normalized().dot(to_player.normalized()) > cos(deg_to_rad(40.0))

func node_property(state: SceneState, path: String, property: StringName) -> Variant:
	var node := node_index(state, path)
	if node >= 0:
		for i in state.get_node_property_count(node):
			if state.get_node_property_name(node, i) == property: return state.get_node_property_value(node, i)
	return null

func reflection_exclusion_check() -> void:
	var reflection := PlanarWaterReflection.new()
	var surface := MeshInstance3D.new()
	surface.mesh = BoxMesh.new()
	surface.position.y = 3.0
	surface.add_to_group(&"distant_city_geometry")
	root.add_child(surface)
	var sources: Array[Node] = [surface]
	reflection._prepare_geometry(sources, 0, 0.0)
	check(surface.layers == 1 and reflection.get_child_count() == 0, "Distant surfaces are excluded even when a later edit places them above water")
	surface.free()
	reflection.free()

func aurora_binding_check(environment: Environment, state: SceneState) -> void:
	var fixture := SkyFixture.new()
	fixture.terrain = Terrain.new()
	var ground: ShaderMaterial = node_property(state, "Homestead", &"top_material")
	fixture.terrain.top_material = ground.duplicate()
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment.duplicate(true)
	fixture.add_child(world_environment)
	var aurora := load("res://scripts/world/aurora_sky.gd").new() as Node
	fixture.add_child(aurora)
	root.add_child(fixture)
	for i in range(3): await process_frame
	var sky := world_environment.environment.sky.sky_material as ShaderMaterial
	var live_ground := fixture.terrain.top_material as ShaderMaterial
	check(aurora.is_processing() and sky.get_shader_parameter("aurora_enabled") == true, "The real aurora component initializes and keeps flowing with the painted background")
	check(live_ground.get_shader_parameter("aurora_enabled") == true and sky.get_shader_parameter("aurora_texture") != null and sky.get_shader_parameter("aurora_texture") == live_ground.get_shader_parameter("aurora_texture"), "Sky and wet ground remain bound to the same live aurora field")
	var terrain := fixture.terrain
	fixture.free()
	terrain.free()
	await process_frame

func camera_obstructions(boxes: Array[AABB]) -> int:
	var blocked := 0
	# 平常、蓄力低视角和近景，遍历完整转向与战区中心、边缘。
	for pitch in [22.0, 27.0, 30.627, 34.0]:
		for distance in [18.0, 30.0, 34.0]:
			for yaw in range(0, 360, 15):
				var offset: Vector3 = Vector3(0.0, sin(deg_to_rad(pitch)), cos(deg_to_rad(pitch))).rotated(Vector3.UP, deg_to_rad(yaw)) * distance
				for x in [-15.5, 0.0, 15.5]:
					for z in [29.3, 44.8, 60.3]:
						var focus := Vector3(x, 0.75, z)
						var eye: Vector3 = focus + offset
						for target_x in [-15.5, 0.0, 15.5]:
							for target_z in [29.3, 44.8, 60.3]:
								for height in [0.1, 1.0, 2.0]:
									var target := Vector3(target_x, height, target_z)
									for box in boxes:
										if box.intersects_segment(eye, target):
											blocked += 1
											if blocked <= 3: printerr("Blocked view: ", eye, " -> ", target, " by ", box)
	return blocked

func in_default_view(group: Node3D) -> bool:
	var focus := Vector3(0.0, 0.75, 48.0)
	var orbit := Vector3(0.0, sin(deg_to_rad(30.627)), cos(deg_to_rad(30.627))).rotated(Vector3.UP, deg_to_rad(135.0)) * 30.0
	var eye := focus + orbit
	var inverse_view := Basis.looking_at(-orbit, Vector3.UP).inverse()
	var screen := Rect2()
	var initialized := false
	var tangent := tan(deg_to_rad(28.0 * 0.5))
	for mesh: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		for corner in range(8):
			var point := inverse_view * (box.get_endpoint(corner) - eye)
			if point.z >= -0.1: continue
			var uv := Vector2(0.5 + point.x / (-point.z * tangent * 3.2), 0.5 - point.y / (-point.z * tangent * 2.0))
			screen = screen.expand(uv) if initialized else Rect2(uv, Vector2.ZERO)
			initialized = true
	var visible := screen.intersection(Rect2(0, 0, 1, 1))
	print(group.name, " projected bounds: ", screen, "; visible area: ", visible.get_area())
	return initialized and visible.size.y > 0.035 and visible.get_area() > 0.005

func visible_vertices(group: Node3D) -> int:
	var focus := Vector3(0.0, 0.75, 48.0)
	var orbit := Vector3(0.0, sin(deg_to_rad(30.627)), cos(deg_to_rad(30.627))).rotated(Vector3.UP, deg_to_rad(135.0)) * 30.0
	var eye := focus + orbit
	var inverse_view := Basis.looking_at(-orbit, Vector3.UP).inverse()
	var tangent := tan(deg_to_rad(14.0))
	var visible := 0
	for mesh: MeshInstance3D in group.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var world := mesh.global_transform * vertex
				var point := inverse_view * (world - eye)
				if point.z >= -0.1: continue
				var uv := Vector2(0.5 + point.x / (-point.z * tangent * 3.2), 0.5 - point.y / (-point.z * tangent * 2.0))
				if not Rect2(0, 0, 1, 1).has_point(uv): continue
				if world.y < 0.0:
					var ground := eye.lerp(world, eye.y / (eye.y - world.y))
					if BATTLE.has_point(Vector2(ground.x, ground.z)): continue
				visible += 1
	print(group.name, " vertices beyond the battlefield silhouette: ", visible)
	return visible

func finish() -> void:
	print(JSON.stringify({"suite": "city_surroundings", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
