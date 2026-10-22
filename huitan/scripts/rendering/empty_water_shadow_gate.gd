extends Node

## Runtime-only gate for EnvironmentLantern's water-only shadow light.
## Geometry references do not own Nodes. SceneTree events maintain the arrays.
const WATER_LAYER := 1 << 16
static var _shared: Node
var _geometry: Array[GeometryInstance3D] = []
var _gi: Array[Node] = []
var _cameras: Array[Camera3D] = []
var _lights: Array[OmniLight3D] = []
var _desired: Dictionary[int, bool] = {}
var _tree: SceneTree
var _draw_boundary := false

static func set_shadow_enabled(light: OmniLight3D, desired: bool) -> void:
	if Engine.is_editor_hint() or not light.is_inside_tree():
		light.shadow_enabled = desired
		return
	if not is_instance_valid(_shared) or _shared.is_queued_for_deletion():
		# Runtime load avoids relying on the editor's global class cache during
		# first import, and permits the controller to call us from its _ready.
		_shared = load("res://scripts/rendering/empty_water_shadow_gate.gd").new()
		_shared.name = "EmptyWaterShadowGate"
		light.get_tree().root.add_child.call_deferred(_shared, false, Node.INTERNAL_MODE_BACK)
	_shared.call("_register", light, desired)

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tree.node_added.connect(_added)
	_tree.node_removed.connect(_removed)
	_bootstrap(_tree.root)
	RenderingServer.frame_pre_draw.connect(sync_now)
	RenderingServer.frame_post_draw.connect(_drawn)

func _bootstrap(node: Node) -> void:
	_added(node)
	for child in node.get_children(true): _bootstrap(child)

func _added(node: Node) -> void:
	if node is GeometryInstance3D:
		_geometry.append(node)
	elif node is Camera3D:
		_cameras.append(node)
	elif node.is_class("VoxelGI") or node.is_class("LightmapGI"):
		_gi.append(node)
	# A newly added drawable may receive its final layers after node_added.
	# A late draw-boundary addition therefore restores conservatively now.
	if _draw_boundary and (node is GeometryInstance3D or node is Camera3D or node is WorldEnvironment or node in _gi):
		_restore()

func _removed(node: Node) -> void:
	if node is GeometryInstance3D: _geometry.erase(node)
	elif node is Camera3D: _cameras.erase(node)
	else: _gi.erase(node)
	if node is OmniLight3D and node in _lights:
		# Leave RendererSceneCull's exit/unpair transaction before changing
		# soft-shadow state. Freed nodes discard the deferred property message;
		# detached survivors restore before their owner's next deferred apply.
		node.set_deferred("shadow_enabled", bool(_desired.get(node.get_instance_id(), true)))
		_lights.erase(node)
		_desired.erase(node.get_instance_id())
		if _lights.is_empty(): queue_free()

func _register(light: OmniLight3D, desired: bool) -> void:
	if light not in _lights: _lights.append(light)
	_desired[light.get_instance_id()] = desired
	# An apply/Style change always honors the source immediately; pre_draw
	# recomputes the current consumer proof instead of remembering old geometry.
	if light.shadow_enabled != desired: light.shadow_enabled = desired

func _environment_has_gi(environment: Environment) -> bool:
	return environment != null and environment.sdfgi_enabled

func sync_now() -> void:
	_draw_boundary = true
	var unknown_gi := false
	for node in _gi:
		if is_instance_valid(node) and node.is_inside_tree():
			unknown_gi = true
			break
	if not unknown_gi:
		for camera in _cameras:
			if is_instance_valid(camera) and _environment_has_gi(camera.environment):
				unknown_gi = true
				break
	var consumer_worlds := {}
	for geometry in _geometry:
		# Hidden, offscreen and shadow-only objects all remain consumers.
		# The common formal-map path stops at this single cheap layer test.
		if is_instance_valid(geometry) and geometry.layers & WATER_LAYER:
			if geometry.is_inside_tree(): consumer_worlds[geometry.get_world_3d().get_instance_id()] = true
	for light in _lights:
		if not is_instance_valid(light) or not light.is_inside_tree(): continue
		var desired := bool(_desired.get(light.get_instance_id(), true))
		var world := light.get_world_3d()
		var eligible := not unknown_gi and String(light.name) == "WaterLight" and light.light_cull_mask == WATER_LAYER and light.light_volumetric_fog_energy == 0.0
		eligible = eligible and not _environment_has_gi(world.environment) and not _environment_has_gi(world.fallback_environment)
		var enabled := desired and (not eligible or consumer_worlds.has(world.get_instance_id()))
		if light.shadow_enabled != enabled: light.shadow_enabled = enabled

func _drawn() -> void:
	_draw_boundary = false

func _restore() -> void:
	for light in _lights:
		if is_instance_valid(light): light.shadow_enabled = bool(_desired.get(light.get_instance_id(), true))

func _exit_tree() -> void:
	_restore()
	if RenderingServer.frame_pre_draw.is_connected(sync_now): RenderingServer.frame_pre_draw.disconnect(sync_now)
	if RenderingServer.frame_post_draw.is_connected(_drawn): RenderingServer.frame_post_draw.disconnect(_drawn)
	if is_instance_valid(_tree):
		if _tree.node_added.is_connected(_added): _tree.node_added.disconnect(_added)
		if _tree.node_removed.is_connected(_removed): _tree.node_removed.disconnect(_removed)
	_geometry.clear()
	_gi.clear()
	_cameras.clear()
	_lights.clear()
	_desired.clear()
	if _shared == self: _shared = null
