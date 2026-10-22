extends SceneTree

const SOURCE := "res://scripts/input/control_bindings.gd"
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if not ResourceLoader.exists(SOURCE):
		check(false, "需要统一且可保存的操作按键模型")
		quit(1)
		return
	var model = load(SOURCE).new()
	check(model.bindings.toggle_rain == [KEY_G] and model.bindings.cycle_style == [KEY_R], "下雨默认 G，与 R 光影独立")
	check(model.movement_keys() == [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT], "移动保留八个独立物理键位，维持弹射的按键中断语义")
	check(model.bindings.normal_attack == [-MOUSE_BUTTON_LEFT] and model.bindings.body_charge == [-MOUSE_BUTTON_RIGHT], "普攻和蓄力保持原鼠标按键")
	var baseline: Dictionary = model.bindings.duplicate(true)
	check(not model.set_binding(&"toggle_rain", 0, KEY_R).is_empty() and model.bindings == baseline, "重复键位拒绝生效，不覆盖现有操作")
	check(not model.set_binding(&"toggle_rain", 0, KEY_Y).is_empty(), "镜头跟随 Y 也参与全局冲突检查")
	for code in [KEY_ESCAPE, KEY_F1, KEY_F12, KEY_1, KEY_CTRL, 0, -MOUSE_BUTTON_WHEEL_UP]:
		check(not model.set_binding(&"toggle_rain", 0, code).is_empty(), "保留界面返回、F 类与无效输入：%d" % code)
	check(not model.set_binding(&"move_up", 0, -MOUSE_BUTTON_MIDDLE).is_empty(), "移动使用键盘，避免鼠标点击变成持续移动")
	check(not model.set_binding(&"missing", 0, KEY_G).is_empty() and not model.set_binding(&"move_up", 8, KEY_G).is_empty(), "拒绝未知动作和无效槽位")
	check(model.set_binding(&"toggle_rain", 0, KEY_H).is_empty() and model.bindings.toggle_rain == [KEY_H], "单独改雨天键")
	check(model.set_binding(&"move_up", 0, KEY_I).is_empty() and model.movement_keys()[0] == KEY_I and model.movement_keys()[4] == KEY_UP, "移动主键改为 I 后仍保留上方向键")
	check(model.set_binding(&"normal_attack", 0, -MOUSE_BUTTON_MIDDLE).is_empty(), "战斗动作支持鼠标中键")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_H
	event.pressed = true
	check(model.event_code(event) == KEY_H, "捕获物理键位")
	event.echo = true
	check(model.event_code(event) == 0, "按键自动重复不触发捕获")
	event.echo = false
	event.ctrl_pressed = true
	check(model.event_code(event) == 0, "不把组合键误识别为单键")
	event.ctrl_pressed = false
	event.pressed = false
	check(model.event_code(event) == 0, "松键不完成改键")
	model.apply_input_map()
	event.pressed = true
	check(event.is_action_pressed(&"toggle_rain", false, true), "改键接入真实 InputMap")
	event.physical_keycode = KEY_G
	check(not event.is_action_pressed(&"toggle_rain", false, true), "旧雨天键已解绑")
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	check(mouse.is_action_pressed(&"normal_attack", false, true), "鼠标改键接入真实攻击动作")
	var directory := "D:/.codexfile/work/control-bindings-20261019"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory + "/bindings-%d.cfg" % OS.get_process_id()
	check(model.save_to_path(path) == OK, "改键保存到独立配置")
	var restored = load(SOURCE).new()
	check(restored.load_from_path(path) == OK and restored.bindings == model.bindings, "重启恢复全部按键及备选键")
	model.reset_defaults()
	check(model.bindings == baseline, "恢复默认完整还原键位")
	# 验证最终组合，而非逐条加载，允许已保存的键位对调。
	model.set_binding(&"move_up", 0, KEY_V)
	model.set_binding(&"move_down", 0, KEY_W)
	model.set_binding(&"move_up", 0, KEY_S)
	model.save_to_path(path)
	check(restored.load_from_path(path) == OK and restored.bindings.move_up[0] == KEY_S and restored.bindings.move_down[0] == KEY_W, "合法对调的存档可整体恢复")
	var invalid := ConfigFile.new()
	invalid.set_value("bindings", "toggle_rain", [KEY_R])
	invalid.save(path)
	var before: Dictionary = restored.bindings.duplicate(true)
	check(restored.load_from_path(path) == ERR_INVALID_DATA and restored.bindings == before, "损坏或冲突存档不破坏当前可用键位")
	print("Control bindings: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
