extends SceneTree

const OUT := "D:/.codexfile/work/rain-toggle-20261019/"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func frames(count := 3) -> void:
	for index in count: await process_frame

func lighting(world: Node) -> Array:
	var moon: DirectionalLight3D = world.get_node("MapEffects/Moon")
	var env: Environment = world.get_node("MapEffects/WorldEnvironment").environment
	return [moon.light_color, moon.light_energy, moon.rotation, env.ambient_light_color, env.ambient_light_energy, env.tonemap_exposure]

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("MapEffects/BGM").music_enabled = false
	var weather: Node3D = world.get_node("MapEffects/Weather")
	weather.set("rain_audio_enabled", false)
	weather.set("wind_audio_enabled", false)
	root.add_child(world)
	current_scene = world
	await frames(12)
	var page = world.get_node("GameSettingsUI")._graphics_page
	check(page.configured and page.controls.has("rain"), "游戏内设置提供独立的下雨复选框")
	if not page.controls.has("rain"):
		world.free()
		await frames()
		quit(1)
		return
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	check(sample.get("independent_weather"), "World 明确开启晴雨与光影独立，其他地图保留各自配置")
	check(page.controls.rain is CheckBox and page.controls.rain.button_pressed == weather.get("raining"), "下雨开关显示当前实际天气")
	var initial_rain: bool = page.defaults.rain
	var camera: FollowCamera = world.get_node("Player").movement_camera
	var lens := [camera.fov, camera.distance, camera.pitch_degrees, camera.yaw_degrees]
	var wind: bool = weather.get("wind_enabled")
	page.set_option("rain_intensity", 0.65)
	page.set_option("rain_amount", 2200)
	for raining in [true, false]:
		for style in [0, 1, 2, 3]:
			sample.style = style
			sample.apply_style()
			await frames()
			var light := lighting(world)
			check(page.set_option("rain", raining), "晴雨选项有效")
			await frames()
			check(sample.style == style and lighting(world) == light, "切晴雨保留当前光照风格：%d" % style)
			check(weather.get("raining") == raining and is_equal_approx(weather.call("_rainfall"), 0.65 if raining else 0.0), "晴雨实际控制降雨量：%d" % style)
			check(weather.get("_rain").emitting == raining, "开关控制雨丝生成")
			check(is_equal_approx(weather.get("_ground").get_shader_parameter("rain_amount"), 0.65 if raining else 0.0), "地面雨纹跟随天气开关")
			check(weather.get("rain_amount") == 2200 and is_equal_approx(weather.get("rain_intensity"), 0.65), "晴雨与 Style 均保留调节的雨丝数量和强度")
			page.overrides.erase("rain")
			# 不靠设置页重新覆盖来掩盖 Style 修改，验证天气本身与风格解耦。
			sample.style = (style + 1) % 4
			sample.apply_style()
			await frames()
			check(weather.get("raining") == raining and is_equal_approx(weather.get("rain_intensity"), 0.65), "R 对应的下一种 Style 不重设晴雨与雨量")
	page.controls.rain.button_pressed = true
	check(weather.get("raining"), "复选框直接开启下雨")
	page.controls.rain.button_pressed = false
	check(not weather.get("raining"), "复选框直接关闭下雨")
	check(not page.set_option("rain", "false") and not page.set_option("rain", 1), "下雨开关拒绝无效存档类型")
	check(weather.get("wind_enabled") == wind and [camera.fov, camera.distance, camera.pitch_degrees, camera.yaw_degrees] == lens, "下雨开关不改基础镜头和花草风摆开关")
	page.config_path = OUT + "rain-%d.cfg" % OS.get_process_id()
	var config := ConfigFile.new()
	config.set_value("scene:another-map", "rain", true)
	config.save(page.config_path)
	page.save_enabled = true
	check(page.save_settings() == OK and config.load(page.config_path) == OK and config.get_value(page.scene_section(), "rain") == false, "晴雨独立保存到当前地图的本机配置")
	check(config.get_value("scene:another-map", "rain") == true, "保存不覆盖其他地图的晴雨选择")
	page.save_enabled = false
	page.reset_defaults()
	check(weather.get("raining") == initial_rain and page.overrides.is_empty(), "恢复场景默认会还原地图原始天气并清除选择")
	page.save_enabled = true
	page.load_settings()
	page.apply_settings()
	check(not weather.get("raining") and not page.controls.rain.button_pressed and is_equal_approx(weather.get("rain_intensity"), 0.65), "重新读取配置恢复关闭的晴雨和独立雨量")
	page.save_enabled = false
	world.free()
	await frames()
	print("Rain toggle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
