extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var path := "res://scripts/player/ricochet_time_scale.gd"
	check(FileAccess.file_exists(path), "整段环绕需要统一管理满蓄和环绕的时间所有权")
	if not FileAccess.file_exists(path):
		quit(1)
		return
	var clock: RefCounted = load(path).new()
	clock.advance(1.0, false, 0.82, 0.12, 0.06)
	check(Engine.time_scale == 1.0 and not clock.active, "切入前普通飞行保持原速")
	clock.advance(0.03, true, 0.82, 0.12, 0.06)
	check(Engine.time_scale < 1.0 and Engine.time_scale > 0.95, "接群后轻柔进入，首次切入保留速度")
	clock.advance(0.09, true, 0.82, 0.12, 0.06)
	check(is_equal_approx(Engine.time_scale, 0.82), "按真实时间在 0.12 秒到达轻微慢动作")
	for frame in 240: clock.advance(1.0 / 60.0, true, 0.82, 0.12, 0.06)
	check(is_equal_approx(Engine.time_scale, 0.82), "整段持续恒定，不随续段和攻击反复停顿")
	clock.advance(0.03, false, 0.82, 0.12, 0.06)
	check(Engine.time_scale > 0.82 and Engine.time_scale < 1.0, "离开环绕快速平滑恢复")
	clock.advance(0.03, false, 0.82, 0.12, 0.06)
	check(Engine.time_scale == 1.0 and not clock.active, "脱离 0.06 秒后恢复完整原速")
	clock.advance(0.04, true, 0.82, 0.12, 0.06)
	var entering := Engine.time_scale
	clock.advance(0.01, false, 0.82, 0.12, 0.06)
	var leaving := Engine.time_scale
	clock.advance(0.0, true, 0.82, 0.12, 0.06)
	check(leaving > entering and is_equal_approx(Engine.time_scale, leaving), "短暂退出再接群从当前比例续接")
	clock.reset()
	check(Engine.time_scale == 1.0 and not clock.active, "接管／冻结／重置能立即完全恢复")
	Engine.time_scale = 0.8
	clock.advance(0.12, true, 0.82, 0.12, 0.06)
	check(is_equal_approx(Engine.time_scale, 0.8 * 0.82), "已有时间比例作为进入前基准")
	clock.advance(0.01, true, 0.82, 0.12, 0.06, 0.75)
	check(is_equal_approx(Engine.time_scale, 0.8 * 0.75), "满蓄与环绕重叠取较慢者，避免二次相乘")
	clock.advance(0.01, true, 0.82, 0.12, 0.06)
	check(is_equal_approx(Engine.time_scale, 0.8 * 0.82), "满蓄到期后仍延续环绕，不恢复错误基准")
	clock.reset()
	check(is_equal_approx(Engine.time_scale, 0.8), "完整退出恢复最初比例")
	Engine.time_scale = 1.0
	clock.advance(0.12, true, 0.82, 0.12, 0.06)
	Engine.time_scale = 0.6
	clock.advance(0.1, true, 0.82, 0.12, 0.06)
	check(is_equal_approx(Engine.time_scale, 0.6) and not clock.active, "外部接管时立即让出时间所有权")
	for frame in 60: clock.advance(1.0 / 60.0, true, 0.82, 0.12, 0.06)
	check(is_equal_approx(Engine.time_scale, 0.6), "同段环绕不反复夺回外部时间控制")
	clock.reset()
	check(is_equal_approx(Engine.time_scale, 0.6), "释放不会覆盖外部接管")
	Engine.time_scale = 1.0
	clock.advance(0.12, true, 1.0, 0.12, 0.06)
	check(Engine.time_scale == 1.0 and not clock.active, "比例为一时不占用全局时钟")
	clock.reset()
	var state: SceneState = load("res://scenes/world/world.tscn").get_state()
	var enabled := false
	for index in state.get_node_count():
		if state.get_node_name(index) != &"ChargePresentation": continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == &"orbit_slow_enabled": enabled = state.get_node_property_value(index, property)
	check(not enabled, "World 停用全局环绕慢动作，人物移速由独立环绕规则控制")
	var defaults := ChargePresentation.new()
	check(not defaults.orbit_slow_enabled and is_equal_approx(defaults.orbit_slow_scale, 0.82), "共享默认不开启其它地图慢动作，初始比例为 0.82")
	var world := Node3D.new()
	world.add_child(defaults)
	defaults.owner = world
	var entries: Array[Dictionary] = load("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["orbit_slow_enabled", "orbit_slow_scale", "orbit_slow_enter_seconds", "orbit_slow_exit_seconds"]:
		check(entries.any(func(item): return item.property == property and item.common and item.category == "视觉" and item.label != property), "参数总览提供中文慢动作入口：" + property)
	world.free()
	await process_frame
	await process_frame
	print("Orbit slow: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
