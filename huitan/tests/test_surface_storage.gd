extends SceneTree
const SCRATCH := "D:/.codexfile/work/game-preparation-optimize-20261019/storage/"
const WORLD_SURFACE := "res://data/world/world_surface.res"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var surface := TerrainSurfaceData.new()
	check(surface.has_method("save_to_file"), "Surface storage exposes the same compressed save path used by the painter")
	if surface.has_method("save_to_file"): roundtrip_checks(surface)
	check(FileAccess.file_exists(WORLD_SURFACE), "World stores hand-painted data as a compact native resource")
	if FileAccess.file_exists(WORLD_SURFACE):
		check(FileAccess.get_file_as_bytes(WORLD_SURFACE).slice(0, 4).get_string_from_ascii() == "RSCC", "Formal surface is losslessly compressed")
		check(ResourceLoader.get_resource_uid(WORLD_SURFACE) == ResourceUID.text_to_id("uid://bkckbayjwnsuy"), "Format migration preserves the map's existing resource UID")
		var packed: PackedScene = load("res://scenes/world/world.tscn")
		var state := packed.get_state()
		var bound := false
		for node in state.get_node_count():
			for property in state.get_node_property_count(node):
				if state.get_node_property_name(node, property) == &"surface_data":
					var data: Resource = state.get_node_property_value(node, property)
					bound = bound or data.resource_path == WORLD_SURFACE
		check(bound, "The actual World scene reads the compressed surface directly")
	print(JSON.stringify({"suite":"surface_storage", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func roundtrip_checks(surface: TerrainSurfaceData) -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var path := SCRATCH + "editable.res"
	var image := Image.create_empty(256, 256, false, Image.FORMAT_RGBAH)
	image.set_pixel(3, 4, TerrainSurfaceData.pixel_record(257, 1048577))
	surface.chunks[Vector2i(-2, 3)] = image
	var stamp := TerrainSurfaceStamp.new()
	stamp.code = 14
	stamp.position = Vector2(-3.2, 4.5)
	stamp.rotation_degrees = 37.0
	stamp.flip_h = true
	stamp.layer_order = 1048578
	surface.stamps.assign([stamp])
	surface.drawing_serial = 1048578
	surface.texture_origin = Vector2(-15.2, 29.6)
	check(surface.call("save_to_file", path) == OK, "Painter save produces a native compressed file")
	# 新建的外部测试文件尚未被编辑器扫描，运行时 UID 查询只读项目 UID 索引。
	var uid := ResourceUID.create_id()
	check(ResourceSaver.set_uid(path, uid) == OK, "The saved resource accepts an explicit stable UID")
	ResourceUID.add_id(uid, path)
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainSurfaceData
	check(restored != null and restored.chunks[Vector2i(-2, 3)].get_data() == image.get_data(), "Half-float codes and drawing order survive byte-for-byte")
	check(restored.drawing_serial == surface.drawing_serial and restored.texture_origin == surface.texture_origin and restored.stamps[0].layer_order == stamp.layer_order and restored.stamps[0].flip_h and restored.stamps[0].rotation_degrees == stamp.rotation_degrees, "Stamp ordering, rotation, mirror and surface coordinates survive")
	surface.paint_segment(Vector2.ZERO, Vector2(0.1, 0), 0.04, 256)
	check(surface.call("save_to_file", path) == OK and ResourceLoader.get_resource_uid(path) == uid, "A second brush edit saves to the same UID")
	var edited := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainSurfaceData
	check(edited.chunks.size() > restored.chunks.size() and edited.drawing_serial == surface.drawing_serial, "Reload reads the latest brush edit rather than an old cache")
	check(FileAccess.get_file_as_bytes(path).slice(0, 4).get_string_from_ascii() == "RSCC", "Repeated painter saves retain compression")
	ResourceUID.remove_id(uid)
