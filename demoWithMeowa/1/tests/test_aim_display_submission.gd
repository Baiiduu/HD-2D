extends SceneTree

class Preview extends AimPathPreview:
	var submissions := 0
	var target_updates := 0
	func _process(delta: float) -> void:
		submissions += 1
		super._process(delta)
	func _update_target() -> void:
		target_updates += 1
		super._update_target()

var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var view := Preview.new()
	world.add_child(view)
	if not "defer_display_updates" in view:
		check(false, "显示提交需要支持同一显示阶段合并请求")
	else:
		view.set("defer_display_updates", true)
		var camera := Camera3D.new()
		world.add_child(camera)
		var sprite := Sprite3D.new()
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		sprite.texture = ImageTexture.create_from_image(image)
		world.add_child(sprite)
		var latest: AimPathData
		for index in 3:
			latest = AimPathData.new()
			latest.append(Vector3.ZERO, Vector3(1 + index, 0, 0), Vector3.RIGHT, 0.1)
			view.display(latest, camera, 0.018, 0.03, 0.1, 1, Color.WHITE, 0.45)
			view.mark_target(sprite)
		check(view.submissions == 0 and view.target_updates == 0, "多次预测请求不重复提交路线或角标")
		camera.rotation.y = 0.4
		view._process(0.0)
		check(view.submissions == 1 and view.target_updates == 1 and view.route == latest, "镜头更新后的统一阶段只提交最新路线和目标一次")
		check(view._lines.multimesh.visible_instance_count == 1 and view._target.visible, "最新路线和真实目标仍正常显示")
		view.display(latest, camera, 0.022, 0.03, 0.1, 2, Color(0.8, 0.6, 0.4), 0.35)
		check(view._line_material.get_shader_parameter("tint") == Color(0.8, 0.6, 0.4) and view._line_material.get_shader_parameter("dash_period") == 0.022 * 14.0 and view._target_material.get_shader_parameter("opacity") == minf(0.8, 0.35 * 1.4), "颜色、透明度与像素尺度热调及时更新，仍保留角标独立透明度")
		view.mark_target(null)
		check(not view._target.visible, "死亡或关闭目标提示立即撤下角标")
		view.stop()
		view._process(0.0)
		check(not view.visible and not view.is_processing() and view.route == null and not view._target.visible, "停止后没有残留待提交路线")
		view.set("defer_display_updates", false)
		var count := view.submissions
		view.display(latest, camera, 0.018, 0.03, 0.1, 1, Color.WHITE, 0.45)
		check(view.submissions == count + 1, "独立预览保留原即时显示接口")
	world.free()
	print("Aim display submission: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
