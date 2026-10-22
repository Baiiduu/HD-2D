extends SceneTree
## 仅检查实例数据和生命周期，不运行渲染、截图或性能采样。
const DEBRIS = preload("res://scripts/enemies/hit_debris.gd")

class DebrisProbe extends "res://scripts/enemies/hit_debris.gd":
	var uploaded: Dictionary[int, Dictionary] = {}
	var upload_count := 0
	# Headless 的 Dummy 渲染器不保留实例数据，记录同一上传入口的参数。
	func _upload_instance(index: int, transform: Transform3D, color: Color, custom: Color) -> void:
		uploaded[index] = {"transform": transform, "color": color, "custom": custom}
		upload_count += 1
		super._upload_instance(index, transform, color, custom)

var checks := 0
var failures := 0
var world: Node3D
var debris: DebrisProbe
var settings := PlayerActionVisuals.new()

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in debris.multimesh.visible_instance_count:
		if debris.uploaded.has(index): result.append(debris.uploaded[index])
	return result

func emit_burst(lethal := false) -> void:
	debris.burst(Vector3(2.0, 0.75, -3.0), Vector3.RIGHT, 0.025, settings, lethal)

func presentation_checks() -> void:
	settings.hit_debris_count = 16
	settings.hit_debris_seconds = 0.42
	settings.hit_debris_speed_multiplier = 2.4
	seed(419)
	var expected_random := randi()
	seed(419)
	emit_burst()
	check(randi() == expected_random, "碎屑发射不消耗玩法的全局随机流")
	var original := snapshot()
	check(original.size() == 16 and debris.emitted == 16, "普通命中保留配置的全部碎屑")
	var valid := true
	for item in original:
		var data: Color = item.custom
		var color: Color = item.color
		var transform: Transform3D = item.transform
		valid = valid and transform.origin == Vector3(2.0, 0.75, -3.0)
		valid = valid and color.a >= 0.42 * 0.8 - 0.000001 and color.a <= 0.42 + 0.000001
		valid = valid and data.r > 0.0 and data.g > 0.0 and data.a == 0.0
	check(valid and original.size() == 16, "提交数据保留世界出生点、完整寿命和定向弹道")
	var uploads := debris.upload_count
	debris.advance(0.1)
	check(snapshot() == original and debris.upload_count == uploads, "未到期时不重建、上传或改写碎屑轨迹")
	var clock: float = debris.clock
	debris.advance(0.0)
	debris.advance(-1.0)
	check(debris.clock == clock and snapshot() == original, "零时间与负时间不推进碎屑")
	emit_burst(true)
	check(debris.multimesh.visible_instance_count == 40 and debris.emitted == 40, "击杀仍额外发射一半碎屑")
	check(debris.get_child_count() == 0 and not debris.is_processing(), "继续使用一个批次且没有逐粒节点或独立回调")
	check(debris.material_override.next_pass != null and debris.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "保留建筑遮挡补画且不增加阴影")
	debris.clear()
	check(not debris.active and not debris.visible and debris.multimesh.visible_instance_count == 0 and debris.clock == 0.0, "主动清理立即撤下所有实例并重置时钟")

func survivor_checks() -> void:
	settings.hit_debris_count = 16
	for index in 8:
		settings.hit_debris_seconds = 0.15 if index % 2 == 0 else 0.6
		emit_burst()
		debris.advance(0.01)
	var before := snapshot()
	var expected: Array[Dictionary] = []
	for item in before:
		if item.color.a > 0.2: expected.append(item)
	var emitted: int = debris.emitted
	var random_state: int = debris._random.state
	debris.advance(0.2)
	check(expected.size() == 64, "交错长短寿命用例同时包含存活与过期碎屑")
	check(snapshot() == expected, "回收交错过期槽位，逐项保留存活碎屑数据与透明绘制顺序")
	check(debris.emitted == emitted and debris._random.state == random_state, "回收不伪造命中、不消耗后续碎屑的随机状态")
	emit_burst()
	var appended := snapshot()
	check(appended.size() == 80 and appended.slice(0, 64) == expected and is_equal_approx(appended[64].custom.a, debris.clock), "回收后在存活前缀之后发射，新命中不覆盖旧弹道")
	debris.advance(0.7)
	check(not debris.active and debris.multimesh.visible_instance_count == 0, "全部自然到期后隐藏批次")
	emit_burst()
	var restarted := snapshot()
	check(restarted.size() == 16 and restarted[0].custom.a == 0.0 and debris.clock == 0.0, "闲置后重新命中从新批次起点开始，不复活旧碎屑")
	debris.clear()

func sustained_checks() -> void:
	settings.hit_debris_count = 16
	settings.hit_debris_seconds = 0.42
	var peak := 0
	# 固定输入验证资源规模；不计时，不据此推导实机 FPS。
	for step in 600:
		debris.advance(0.02)
		emit_burst()
		peak = maxi(peak, debris.multimesh.visible_instance_count)
	check(peak <= 512, "连续命中 12 秒时提交量受存活窗口约束，不随累计命中增长到容量上限；实际峰值 %d" % peak)
	print("Sustained lifecycle submitted-instance peak: ", peak)
	check(debris.active, "回收过程中连续命中保持批次活跃")
	debris.advance(0.7)
	check(not debris.visible and debris.multimesh.visible_instance_count == 0, "停止连续命中后完整回收")

func capacity_checks() -> void:
	settings.hit_debris_count = 32
	settings.hit_debris_seconds = 0.6
	var initial_emitted: int = debris.emitted
	for index in DEBRIS.CAPACITY / 32 + 1: emit_burst()
	check(debris.multimesh.visible_instance_count == DEBRIS.CAPACITY and debris.emitted - initial_emitted == DEBRIS.CAPACITY + 32, "同一时刻超过容量仍沿用固定容量环写，不越界或拒绝新命中")
	debris.advance(0.7)
	check(not debris.active and debris.multimesh.visible_instance_count == 0, "容量饱和后仍按原寿命完整释放")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	debris = DebrisProbe.new()
	world.add_child(debris)
	debris._random.seed = 109
	presentation_checks()
	survivor_checks()
	sustained_checks()
	capacity_checks()
	world.free()
	print("Hit debris lifecycle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
