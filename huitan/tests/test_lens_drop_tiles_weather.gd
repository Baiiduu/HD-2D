extends SceneTree
const TILES = preload("res://scripts/rendering/lens_drop_tiles.gd")
const POST = preload("res://shaders/post/post_process.gdshader")

class WeatherProbe extends "res://scripts/world/weather.gd":
	func _ready() -> void:
		# 只验证天气上传数据；不创建雨丝、声音或正式地图。
		set_process(false)
		_apply_queued = true

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	var uniforms := {}
	for parameter in POST.get_shader_uniform_list(): uniforms[parameter.name] = parameter.type
	check(uniforms.get("lens_drop_tiles") == TYPE_PACKED_VECTOR4_ARRAY and uniforms.get("lens_tile_screen_size") == TYPE_VECTOR2, "shader 声明的候选表和尺寸类型与天气上传一致")
	check(WeatherProbe.MAX_DROPS == TILES.MAX_DROPS, "天气与候选表共用 12 颗雨滴的容量契约")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var post := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = POST
	post.material = material
	viewport.add_child(post)
	var weather := WeatherProbe.new()
	weather.post_process = post
	viewport.add_child(weather)
	var shape := Vector4(1.0, 1.2, -0.3, 0.4)
	weather._drops.append({"uv": Vector2(0.25, 0.25), "radius": 24.0, "age": 0.4, "lifetime": 4.0, "slide": 1.0, "shape": shape})
	weather._bind_post()
	var values: PackedVector4Array = material.get_shader_parameter("lens_drops")
	var shapes: PackedVector4Array = material.get_shader_parameter("lens_drop_shapes")
	check(values.size() == 12 and values[0] == Vector4(0.25, 0.25, 24.0, 1.0) and shapes[0] == shape, "分块不改雨滴位置、半径、淡入淡出和形状参数")
	check(material.get_shader_parameter("lens_enabled") == true and material.get_shader_parameter("lens_drop_count") == 1, "天气仍按原规则启用镜头雨滴")
	var cells: Variant = material.get_shader_parameter("lens_drop_tiles")
	check(cells is PackedVector4Array and cells.size() == 192, "天气提交完整候选表")
	check(material.get_shader_parameter("lens_tile_screen_size") == Vector2(1440, 900), "候选表绑定实际 Canvas 输出尺寸")
	var builder := TILES.new()
	check(cells == builder.build(values, Vector2(1440, 900)), "候选表与同次上传的水滴快照一致")
	viewport.size = Vector2i(900, 1440)
	await process_frame
	weather._write_drops()
	check(material.get_shader_parameter("lens_tile_screen_size") == Vector2(900, 1440), "窗口比例变化后更新表的尺寸标记")
	check(material.get_shader_parameter("lens_drop_tiles") == builder.build(values, Vector2(900, 1440)), "横竖屏变化重建覆盖，不沿用旧宽高比")
	viewport.scaling_3d_scale = 0.5
	weather._write_drops()
	check(material.get_shader_parameter("lens_tile_screen_size") == Vector2(900, 1440), "降低 3D 渲染比例不误用缩小后的 3D 缓冲尺寸")
	weather._drops[0].uv = Vector2(0.75, 0.8)
	weather._write_drops()
	var moved: PackedVector4Array = material.get_shader_parameter("lens_drops")
	check(moved[0].x == 0.75 and is_equal_approx(moved[0].y, 0.8) and material.get_shader_parameter("lens_drop_tiles") == builder.build(moved, Vector2(900, 1440)), "水滴滑动的参数与候选覆盖同时更新")
	weather.lens_drops_enabled = false
	weather._write_drops()
	check(material.get_shader_parameter("lens_enabled") == false and material.get_shader_parameter("lens_tile_screen_size") == Vector2.ZERO, "关闭效果时停用表，不保留有效尺寸标记")
	weather.lens_drops_enabled = true
	weather._write_drops()
	check(material.get_shader_parameter("lens_enabled") == true and material.get_shader_parameter("lens_tile_screen_size") == Vector2(900, 1440), "重新开启即提交当前覆盖")
	weather.post_process = null
	weather._write_drops()
	check(material.get_shader_parameter("lens_tile_screen_size") == Vector2.ZERO, "只有材质而无有效视口时标记回退原循环")
	weather.post_process = post
	weather._drops.clear()
	weather._write_drops()
	check(material.get_shader_parameter("lens_enabled") == false and material.get_shader_parameter("lens_drop_count") == 0 and material.get_shader_parameter("lens_tile_screen_size") == Vector2.ZERO, "全部到期后关闭雨滴并撤销候选表标记")
	viewport.free()
	print("Lens drop tile weather binding: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
