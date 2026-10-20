extends SceneTree

const ROOT := "res://assets/models/pocket_universe_nursery/"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	for name in ["albedo", "normal", "orm", "emission"]:
		check(FileAccess.file_exists(ROOT + "textures/pocket_universe_%s.png" % name), "需要生产贴图：" + name)
	if failures:
		quit(1)
		return
	for name in ["albedo", "normal", "orm", "emission"]:
		var settings := ConfigFile.new()
		settings.load(ROOT + "textures/pocket_universe_%s.png.import" % name)
		check(settings.get_value("params", "compress/mode") == 0 and not settings.get_value("params", "mipmaps/generate"), "无损导入、不生成 mipmap：" + name)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "pocket_universe_uv_layout.json"))
	var source := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "source/style_master.png"))
	source.convert(Image.FORMAT_RGB8)
	var albedo := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "textures/pocket_universe_albedo.png"))
	var orm := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "textures/pocket_universe_orm.png"))
	check(source.get_size() == Vector2i(1024, 1024) and albedo.get_size() == source.get_size(), "生产颜色图保留原生 1024 像素")
	check(layout.pixels_per_meter == 80, "统一约 80 原生像素／世界米")
	for key: String in layout.regions:
		var r: Array = layout.regions[key].rect
		var box := Rect2i(r[0], r[1], r[2], r[3])
		check(albedo.get_region(box).get_data() == source.get_region(box).get_data(), "保留 Meowa 原生颜色像素：" + key)
		check(albedo.get_pixel(box.position.x-1, box.position.y).is_equal_approx(albedo.get_pixelv(box.position)), "UV 岛边距扩展原像素：" + key)
	check(orm.get_size() == Vector2i(1024, 1024), "ORM 与颜色共用分辨率及 UV")
	var before: Node3D = load(ROOT + "source/whitebox.tscn").instantiate()
	var after: Node3D = load("res://scenes/buildings/pocket_universe_nursery.tscn").instantiate()
	check(after.get_meta("production_stage") == "textured_preview", "独立建筑已接入生产图集")
	var material: ORMMaterial3D = load(ROOT + "pocket_universe_material.tres")
	check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and not material.texture_repeat, "原生最近邻与禁用整图重复")
	check(material.normal_enabled and material.normal_scale <= 0.4, "法线仅轻微表现结构")
	check(material.emission_texture != null, "发光遮罩独立，墙身不整片发光")
	check(material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "局部发光必须相乘，遮罩黑区不能叠加白色发光基色")
	var emission := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "textures/pocket_universe_emission.png"))
	check(emission.get_pixel(148, 656).r == 0.0 and emission.get_pixel(148, 656).g == 0.0 and emission.get_pixel(148, 656).b == 0.0, "蓝色星球的发光遮罩保持黑色，不能整体提白")
	check(emission.get_pixel(148, 748).g > 0.0, "轨道在局部发光遮罩中保留亮度")
	for mesh: MeshInstance3D in after.find_children("*", "MeshInstance3D", true, false):
		var original: MeshInstance3D = before.get_node(NodePath("Model/" + String(mesh.name)))
		check(mesh.transform.is_equal_approx(original.transform) and mesh.mesh.get_aabb().is_equal_approx(original.mesh.get_aabb()), "贴图不改变体量：" + String(mesh.name))
		var expected: Material = load("res://assets/models/cyber_armillary/material.tres") if mesh.get_meta("shared_orbit_atlas", false) else material
		check(mesh.material_override == expected, "主体共用图集材质，轨道复用中央球体材质：" + String(mesh.name))
		var uvs: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var valid := true
		for uv in uvs: valid = valid and uv.is_finite() and uv.x > 0 and uv.x < 1 and uv.y > 0 and uv.y < 1
		check(valid, "UV 有效且不跨出图集：" + String(mesh.name))
	var old_parts := before.get_node("BuildingCollision").get_children()
	var new_parts := after.get_node("BuildingCollision").get_children()
	check(old_parts.size() == new_parts.size(), "贴图保留全部碰撞部位")
	for i in mini(old_parts.size(), new_parts.size()):
		check(old_parts[i].transform.is_equal_approx(new_parts[i].transform) and old_parts[i].shape.get_debug_mesh().get_faces() == new_parts[i].shape.get_debug_mesh().get_faces(), "碰撞形状与白模一致：" + String(old_parts[i].name))
	before.free()
	after.free()
	print("Pocket universe materials: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
