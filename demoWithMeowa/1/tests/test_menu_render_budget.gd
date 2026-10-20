extends SceneTree

const WORLD := "res://scenes/world/world.tscn"
const PAGE := preload("res://scripts/ui/graphics_settings_page.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	node_added.connect(func(node):
		if node.scene_file_path == "res://scenes/ui/main_menu.tscn":
			node.audio_enabled = false
			node.save_preferences = false
		if node.scene_file_path != WORLD: return
		node.get_node("LoadoutUI").save_enabled = false
		node.get_node("GameSettingsUI").save_graphics_settings = false
		node.get_node("MapEffects/GameAudio").load_local_mix = false
		node.get_node("MapEffects/CoreFeedbackAudio").enabled = false
		node.get_node("MapEffects/BGM").music_enabled = false
		node.get_node("MapEffects/Weather").rain_audio_enabled = false
		node.get_node("MapEffects/Weather").wind_audio_enabled = false
		node.get_node("WorldEntry").preview_on_direct_run = false)
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func wait_ready(startup: Node) -> void:
	var deadline := Time.get_ticks_msec()+15000
	while not startup.game_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(startup.game_ready,"完整准备结束后开始可用")

func run() -> void:
	var original_disable := root.disable_3d
	root.disable_3d = false
	var world := load(WORLD).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await process_frame
	var primary = world.get_node("GameSettingsUI")._graphics_page
	check(primary.configured,"正式画质在首轮延迟初始化内就绪，不再等待两个绘制帧")
	while not primary.configured: await process_frame
	var folder := "D:/.codexfile/work/gpu-startup-20261020"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("quality-%d.cfg" % OS.get_process_id())
	var fixture := ConfigFile.new()
	fixture.set_value("scene:"+WORLD,"ssao",false)
	fixture.set_value("display","msaa",0)
	fixture.save(path)
	var environment: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	var defaults: Dictionary = primary.defaults.duplicate()
	var page := PAGE.new()
	page.config_path = path
	world.add_child(page)
	page.configure(world,Theme.new())
	await process_frame
	check(page.configured and not environment.ssao_enabled and root.msaa_3d == Viewport.MSAA_DISABLED,"本机覆盖在下一帧前生效")
	while not page.configured: await process_frame
	check(page.defaults == defaults,"第二个画质入口仍保留地图原始默认值，不把已应用的本机值当默认")
	page.save_enabled = false
	page.reset_defaults()
	page.free()
	var screen: CanvasItem = world.get_node("MapEffects/PostProcess/Screen")
	var reflection := world.get_node("MapEffects/WaterReflection")
	var aurora := world.get_node("MapEffects/Aurora")
	var startup := world.get_node("WorldMainMenu")
	var entry := world.get_node("WorldEntry")
	startup.open_menu()
	var saw_warmup := false
	var prematurely_disabled := false
	while not startup.game_ready:
		await process_frame
		if entry.active:
			saw_warmup = true
			prematurely_disabled = prematurely_disabled or root.disable_3d or not screen.visible
	check(saw_warmup and not prematurely_disabled,"四个入场代表状态仍可真实绘制，预热期间不禁用 3D 或后处理")
	check(root.disable_3d and not screen.visible,"菜单准备完成后关闭被遮住的主视口 3D 和地图后处理")
	check(not paused and world.get_node("Player").is_physics_processing() and startup.menu.is_processing(),"只暂停后台绘制，人物物理和菜单输入更新继续")
	check(aurora._field.render_target_update_mode == SubViewport.UPDATE_DISABLED,"菜单驻留停止极光附加视口绘制")
	check(reflection.views.all(func(view): return view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED),"菜单驻留停止水面反射附加视口绘制")
	if "render_suspended" in aurora and "render_suspended" in reflection:
		var before: float = aurora.clock
		aurora._process(0.25)
		check(aurora.clock > before,"暂停绘制仍保持极光时钟连续")
		aurora.flow_speed = 0.0
		aurora._apply()
		check(aurora._field.render_target_update_mode == SubViewport.UPDATE_DISABLED,"静止极光的单次刷新同样不能绕过暂停")
		aurora.flow_speed = 0.9
		aurora._apply()
		reflection._process(0.0)
		check(aurora._field.render_target_update_mode == SubViewport.UPDATE_DISABLED and reflection.active_view_count == 0,"控制器重应用或更新不能绕过菜单的绘制暂停")
	else: check(false,"两个附加视口有独立绘制暂停，不修改画质开关")
	var report: Dictionary = startup._feedback_warmup.report.duplicate()
	var menu_page = startup.menu._graphics_page
	check(menu_page.set_option("ssao",false),"菜单画质入口保持可用")
	check(not root.disable_3d and screen.visible and not startup.game_ready,"菜单修改画质后恢复后台绘制并重新等待正常视图")
	startup._rendered()
	menu_page.set_option("ssil",false)
	check(startup._frames_left == 2,"恢复期间再次修改画质，从最后一次变更重新等待两次绘制")
	await wait_ready(startup)
	check(root.disable_3d and not entry.active and startup._feedback_warmup.report == report,"画质变更后重新收住绘制，不重复隐藏入场或反馈预热")
	root.size_changed.emit()
	check(not root.disable_3d and not startup.game_ready,"窗口尺寸变化也先恢复绘制")
	await wait_ready(startup)
	var menu = startup.menu
	menu.start_feedback_seconds = 0.3
	menu.start_game()
	root.size_changed.emit()
	check(menu.flow.busy and not startup.game_ready,"已接受开始时遇到尺寸变化，确认流程继续等待重新绘制")
	await wait_ready(startup)
	check(menu.buttons[0].disabled and menu.flow.busy,"重新就绪不解锁已接受的开始按钮")
	await create_timer(0.4).timeout
	check(startup.started and current_scene == world,"确认反馈结束后进入原 World")
	check(not root.disable_3d and screen.visible and entry.active,"正式入场开始前已恢复 3D 与原后处理")
	if "render_suspended" in aurora and "render_suspended" in reflection:
		check(not aurora.render_suspended and not reflection.render_suspended and aurora._field.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"进入后按最新配置恢复附加视口")
	entry.skip()
	# 上层原本已关闭的画面必须保持；关闭菜单组件不得强制开启它们。
	root.disable_3d = true
	screen.hide()
	check(startup.return_to_menu(),"返回沿用原 World")
	await wait_ready(startup)
	world.free()
	check(root.disable_3d,"场景退出按进入菜单前的状态归还视口，而非强制开启 3D")
	root.disable_3d = original_disable
	await process_frame
	await create_timer(0.1).timeout
	print("MENU_RENDER_BUDGET ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
