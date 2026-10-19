extends VBoxContainer
## User overrides only. Scene defaults stay authoritative until a control is changed.
## Hardware/display choices are global; artistic overrides are scoped to the map.

const HEIGHTS := [2160, 1440, 1200, 1080, 900, 800, 720, 600, 540]
const DESCRIPTIONS := {
	"fullscreen":"铺满当前屏幕。编辑器内嵌运行请先切换到独立运行窗口。",
	"render_height":"降低场景实际绘制的像素数，再放大至全屏；界面保持清晰。越低越省 GPU，但场景会更模糊。",
	"vsync":"让画面提交配合显示器刷新，减少撕裂，可能增加输入等待。测最高 FPS 时关闭，日常试玩按撕裂情况开启。",
	"max_fps":"限制每秒最多绘制多少帧，减少发热和功耗；设置为 100 不代表一定能达到 100 FPS。",
	"msaa":"平滑建筑等几何边缘，2×／4×／8×越高越耗 GPU 和显存；对贴图内部的锯齿作用有限。",
	"fxaa":"用较低开销平滑画面边缘，也可能让像素人物和细节变软。",
	"taa":"结合前后帧减少闪烁；快速弹射、雨丝和像素细节可能出现模糊或拖影。",
	"shadow_atlas":"全向灯与聚光灯共用阴影图集的边长，并非每盏灯各有这么大的贴图。越大阴影细节越足，显存和 GPU 成本也更高；不减少重复投影次数。",
	"moon_shadows":"方向光形成的主要场景阴影；关闭会削弱整体空间层次，照明仍保留。",
	"fill_shadows":"路灯向四周补光产生的阴影。关闭保留暖色补光和其它阴影，但墙后可能漏光；这是本项目已定位的高开销项。",
	"cone_shadows":"路灯向下聚光形成的阴影。关闭保留灯光光圈，但灯下遮挡会减少。",
	"ssao":"补充墙角、脚底和物体接缝的暗部，让物体更贴地；增加 GPU 后处理开销。",
	"ssil":"让屏幕中相邻表面之间产生间接补光和颜色影响；不是新增实体灯光，增加 GPU 开销。",
	"ssr":"利用当前画面生成地面和水面等倒影；画面外的物体无法完整反映，关闭可减少 GPU 开销。",
	"glow":"让灯芯等高亮位置向外产生柔和光晕；关闭不改变真实灯光照明。",
	"bloom":"调整泛光的亮度，不是画质等级；泛光关闭时此项没有可见效果。",
	"distance_fog":"远处逐渐融入雾色，突出前后层次；与灯光穿过空气的体积雾是两种效果。",
	"volumetric_fog":"让灯光在空气中显出雾和光束，开销通常比普通距离雾高。",
	"dof":"让焦点前后或画面外围变模糊，取决于当前地图的景深方式；关闭可保持全画面清晰。",
	"vignette":"让画面四角变暗，突出中心；强度控制观感，不是主要性能选项。",
	"wet_surface":"控制雨后湿膜与灯光倒影，保留原地表纹理；与 SSR 开关共同影响反光表现。",
	"water_mirror":"在支持镜像的水面可见时，用额外视角绘制倒影；没有活动镜像时关闭不会明显提速。",
	"water_mirror_scale":"水面镜像相对场景渲染分辨率的宽高比例。50% 对应约四分之一像素，倒影会更模糊。",
	"rain":"独立切换下雨，保留当前光影风格和已调雨量。雨声、雨纹随天气变化，基础风摆保持；停雨后地面按原速度退湿。",
	"rain_intensity":"调整实际雨量；现有雨声、地面雨纹和湿润反馈也会随雨量变化。",
	"rain_amount":"雨幕中的雨丝数量，越多越密，也会增加粒子绘制和透明叠加开销。",
	"ground_rain":"显示落在地面的雨纹，不改变人物和怪物逻辑。",
	"lens_drops":"显示镜头表面的雨滴与滑落效果，会覆盖并扭曲部分画面。",
	"wind":"控制花草的自然风摆，不移除草木，也不改变碰撞与分布。",
	"aurora":"控制天空极光及对应地面倒影。本项目已测到极光额外视口的成本较小，关掉它不保证明显提速。",
	"fireflies":"显示环境中的萤火光点，保留场景布局。",
	"lamp_dust":"显示路灯附近的金色颗粒；体积雾关闭时可能已不显示。",
}
const SPECS := [
	{"key":"fullscreen", "group":"显示", "label":"全屏", "target":"display", "scope":"display"},
	{"key":"render_height", "group":"显示", "label":"场景渲染分辨率", "target":"resolution", "scope":"display"},
	{"key":"vsync", "group":"显示", "label":"垂直同步", "target":"vsync", "scope":"display"},
	{"key":"max_fps", "group":"显示", "label":"帧率上限", "target":"engine", "property":"max_fps", "scope":"display", "values":[0,30,60,90,100,120,144,165,240], "labels":["不限","30","60","90","100","120","144","165","240"]},
	{"key":"msaa", "group":"抗锯齿与阴影", "label":"多重采样抗锯齿", "target":"view", "property":"msaa_3d", "scope":"display", "values":[0,1,2,3], "labels":["关闭","2×","4×","8×"]},
	{"key":"fxaa", "group":"抗锯齿与阴影", "label":"快速抗锯齿", "target":"view", "property":"screen_space_aa", "scope":"display", "values":[0,1], "labels":["关闭","FXAA"]},
	{"key":"taa", "group":"抗锯齿与阴影", "label":"时间抗锯齿", "target":"view", "property":"use_taa", "scope":"display"},
	{"key":"shadow_atlas", "group":"抗锯齿与阴影", "label":"局部阴影贴图尺寸", "target":"view", "property":"positional_shadow_atlas_size", "scope":"display", "values":[1024,2048,4096,8192], "labels":["1024","2048","4096","8192"]},
	{"key":"moon_shadows", "group":"抗锯齿与阴影", "label":"方向光阴影", "target":"moon", "property":"shadow_enabled"},
	{"key":"fill_shadows", "group":"抗锯齿与阴影", "label":"路灯全向补光阴影", "target":"art", "property":"street_fill_shadows_enabled"},
	{"key":"cone_shadows", "group":"抗锯齿与阴影", "label":"路灯聚光阴影", "target":"art", "property":"street_cone_shadows_enabled"},
	{"key":"ssao", "group":"环境与后处理", "label":"环境遮蔽（SSAO）", "target":"environment", "property":"ssao_enabled"},
	{"key":"ssil", "group":"环境与后处理", "label":"间接光照（SSIL）", "target":"environment", "property":"ssil_enabled"},
	{"key":"ssr", "group":"环境与后处理", "label":"屏幕空间反射（SSR）", "target":"environment", "property":"ssr_enabled"},
	{"key":"glow", "group":"环境与后处理", "label":"泛光", "target":"environment", "property":"glow_enabled"},
	{"key":"bloom", "group":"环境与后处理", "label":"泛光强度", "target":"art", "property":"bloom", "range":[0.0,2.0,0.05]},
	{"key":"distance_fog", "group":"环境与后处理", "label":"距离雾", "target":"environment", "property":"fog_enabled"},
	{"key":"volumetric_fog", "group":"环境与后处理", "label":"体积雾与雾中光束", "target":"art", "property":"volumetric_fog"},
	{"key":"dof", "group":"环境与后处理", "label":"景深", "target":"camera", "property":"dof_enabled"},
	{"key":"vignette", "group":"环境与后处理", "label":"暗角强度", "target":"art", "property":"vignette", "range":[0.0,1.0,0.05]},
	{"key":"wet_surface", "group":"水面与地面", "label":"湿地面与灯光倒影", "target":"art", "property":"wet_surface_enabled"},
	{"key":"water_mirror", "group":"水面与地面", "label":"水面镜像反射", "target":"art", "property":"water_reflection_enabled"},
	{"key":"water_mirror_scale", "group":"水面与地面", "label":"水面反射分辨率比例", "target":"art", "property":"water_reflection_scale", "values":[0.25,0.5,0.75,1.0], "labels":["25%","50%","75%","100%"]},
	{"key":"rain", "group":"天气与装饰", "label":"下雨", "target":"weather", "property":"raining"},
	{"key":"rain_intensity", "group":"天气与装饰", "label":"降雨强度", "target":"weather", "property":"rain_intensity", "range":[0.0,1.0,0.05]},
	{"key":"rain_amount", "group":"天气与装饰", "label":"雨丝数量", "target":"weather", "property":"rain_amount", "range":[100,8000,100], "integer":true},
	{"key":"ground_rain", "group":"天气与装饰", "label":"地面雨纹", "target":"weather", "property":"ground_rain_enabled"},
	{"key":"lens_drops", "group":"天气与装饰", "label":"镜头水滴", "target":"weather", "property":"lens_drops_enabled"},
	{"key":"wind", "group":"天气与装饰", "label":"花草风摆", "target":"weather", "property":"wind_enabled"},
	{"key":"aurora", "group":"天气与装饰", "label":"天空极光与极光倒影", "target":"aurora", "property":"enabled"},
	{"key":"fireflies", "group":"天气与装饰", "label":"萤火光点", "target":"art", "property":"fireflies_enabled"},
	{"key":"lamp_dust", "group":"天气与装饰", "label":"路灯金色颗粒", "target":"art", "property":"street_dust_enabled"},
]

var save_enabled := true
var config_path := "user://graphics_settings.cfg"
var configured := false
var overrides := {}
var defaults := {}
var controls := {}
var targets := {}
var world: Node
var window: Window
var _status: Label
var _save_timer: Timer
var _applying := false
var _refreshing := false
var _windowed_size := Vector2i(1280, 800)
var _native_scale := 1.0

func configure(scene: Node, settings_theme: Theme) -> void:
	world = scene
	window = get_window()
	theme = settings_theme
	add_theme_constant_override("separation", 12)
	# Let the formal map's deferred Style, weather and resource binding finish first.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree(): return
	var art := world.get_node_or_null("MapEffects/ArtDirection")
	var environment_node := world.get_node_or_null("MapEffects/WorldEnvironment") as WorldEnvironment
	var player := world.get_node_or_null("Player") as Player
	targets = {"art":art, "environment":environment_node.environment if environment_node else null,
		"weather":world.get_node_or_null("MapEffects/Weather"), "camera":player.movement_camera if player else null,
		"aurora":world.get_node_or_null("MapEffects/Aurora"), "moon":world.get_node_or_null("MapEffects/Moon"),
		"view":window, "engine":Engine}
	_native_scale = window.scaling_3d_scale
	if window.mode == Window.MODE_WINDOWED: _windowed_size = window.size
	for spec in SPECS:
		if available(spec): defaults[spec.key] = read_value(spec)
	_build()
	configured = true
	if art and art.has_signal("applied"): art.applied.connect(_on_art_applied)
	var style := world.get_node_or_null("VisualSample")
	if style and style.has_signal("style_changed"): style.style_changed.connect(_on_style_changed)
	window.size_changed.connect(refresh_resolution)
	if save_enabled:
		load_settings()
		if not overrides.is_empty(): apply_settings()
	refresh_resolution()
	sync_controls()

func available(spec: Dictionary) -> bool:
	if spec.key == "rain":
		var style := world.get_node_or_null("VisualSample")
		if style and not style.get("independent_weather"): return false
	return spec.target in ["display", "resolution", "vsync"] or is_instance_valid(targets.get(spec.target))

func read_value(spec: Dictionary) -> Variant:
	match spec.target:
		"display": return window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
		"resolution": return 0
		"vsync": return DisplayServer.window_get_vsync_mode(window.get_window_id()) != DisplayServer.VSYNC_DISABLED
	return targets[spec.target].get(spec.property)

func value_for(key: String) -> Variant:
	if overrides.has(key): return overrides[key]
	for spec in SPECS:
		if spec.key == key and available(spec): return read_value(spec)
	return null

func _build() -> void:
	var note := Label.new()
	note.text = "修改即时生效并保存。全屏保持铺满屏幕，降低场景分辨率可减轻 GPU 负担；界面保持清晰。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var embedded := "--wid" in OS.get_cmdline_args()
	if embedded:
		var hint := Label.new()
		hint.text = "编辑器内嵌运行仍可调整场景分辨率；切换全屏请使用独立运行窗口。"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
	var previous := ""
	for spec in SPECS:
		if not available(spec): continue
		if previous != spec.group:
			previous = spec.group
			var heading := Label.new()
			heading.text = previous
			heading.add_theme_font_size_override("font_size", 22)
			add_child(heading)
		var control: Control
		if spec.has("values") or spec.target == "resolution":
			var row := VBoxContainer.new()
			add_child(row)
			var label := Label.new()
			label.text = spec.label
			row.add_child(label)
			var select := OptionButton.new()
			select.fit_to_longest_item = false
			select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if spec.has("values"):
				for index in spec.values.size():
					select.add_item(spec.labels[index])
					select.set_item_metadata(index, spec.values[index])
				var initial: Variant = read_value(spec)
				if initial not in spec.values:
					select.add_item("场景默认")
					select.set_item_metadata(select.item_count - 1, initial)
					select.set_item_disabled(select.item_count - 1, true)
			select.item_selected.connect(func(index: int): set_option(spec.key, select.get_item_metadata(index)))
			row.add_child(select)
			control = select
		elif spec.has("range"):
			var row := HBoxContainer.new()
			add_child(row)
			var label := Label.new()
			label.text = spec.label
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var number := SpinBox.new()
			number.min_value = spec.range[0]
			number.max_value = spec.range[1]
			number.step = spec.range[2]
			number.custom_minimum_size.x = 100
			number.value_changed.connect(func(value: float): set_option(spec.key, int(value) if spec.get("integer", false) else value))
			row.add_child(number)
			control = number
		else:
			var checkbox := CheckBox.new()
			checkbox.text = spec.label
			checkbox.toggled.connect(func(value: bool): set_option(spec.key, value))
			if spec.key == "fullscreen": checkbox.disabled = embedded or DisplayServer.get_name() == "headless"
			add_child(checkbox)
			control = checkbox
		controls[spec.key] = control
		control.tooltip_text = DESCRIPTIONS.get(spec.key, "")
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var reset := Button.new()
	reset.text = "恢复本页场景默认设置"
	reset.pressed.connect(reset_defaults)
	add_child(reset)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.35
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)

func validated(spec: Dictionary, value: Variant) -> Variant:
	if spec.target == "resolution": return value if typeof(value) == TYPE_INT and (value == 0 or value in HEIGHTS) else null
	if spec.has("values"):
		return value if typeof(value) in [TYPE_INT, TYPE_FLOAT] and value in spec.values else null
	if spec.has("range"):
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)): return null
		var bounded := snappedf(clampf(float(value), spec.range[0], spec.range[1]), spec.range[2])
		return int(bounded) if spec.get("integer", false) else bounded
	return value if typeof(value) == TYPE_BOOL else null

func set_option(key: String, value: Variant) -> bool:
	for spec in SPECS:
		if spec.key != key or not available(spec): continue
		var valid: Variant = validated(spec, value)
		if valid == null: return false
		overrides[key] = valid
		apply_settings()
		if save_enabled: _save_timer.start()
		return true
	return false

func apply_settings() -> void:
	if not configured or _applying: return
	_applying = true
	var art_changed := false
	var weather_changed := false
	for spec in SPECS:
		if not overrides.has(spec.key) or not available(spec): continue
		var value: Variant = overrides[spec.key]
		match spec.target:
			"display":
				if DisplayServer.get_name() == "headless" or "--wid" in OS.get_cmdline_args(): continue
				var fullscreen: bool = window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
				if fullscreen != value:
					if value: _windowed_size = window.size
					window.mode = Window.MODE_FULLSCREEN if value else Window.MODE_WINDOWED
					if not value: window.size = _windowed_size
			"resolution": pass
			"vsync":
				if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED, window.get_window_id())
			_:
				var target: Object = targets[spec.target]
				if target.get(spec.property) != value:
					target.set(spec.property, value)
					art_changed = art_changed or spec.target == "art"
					weather_changed = weather_changed or spec.target == "weather"
	if art_changed: targets.art.apply()
	if weather_changed: targets.weather._apply()
	# ArtDirection.apply can touch renderer state. Explicit environment choices win last.
	_apply_environment_overrides()
	if targets.camera: targets.camera._update_dof()
	_applying = false
	refresh_resolution()
	sync_controls()

func _apply_environment_overrides() -> void:
	for spec in SPECS:
		if spec.target in ["environment", "moon"] and overrides.has(spec.key) and available(spec):
			targets[spec.target].set(spec.property, overrides[spec.key])

func _on_art_applied() -> void:
	if not _applying: _apply_environment_overrides()

func _on_style_changed(_index: int, _title: String) -> void:
	apply_settings()

func render_pixels() -> Vector2i:
	return Vector2i(maxi(1, window.size.x), maxi(1, window.size.y))

func refresh_resolution() -> void:
	if not configured or _refreshing: return
	_refreshing = true
	var pixels := render_pixels()
	var height: int = overrides.get("render_height", 0)
	if overrides.has("render_height"):
		window.scaling_3d_scale = clampf(float(height) / pixels.y, 0.25, 1.0) if height > 0 else 1.0
	var select: OptionButton = controls.render_height
	select.clear()
	select.add_item("原生 · %d × %d" % [pixels.x, pixels.y])
	select.set_item_metadata(0, 0)
	for candidate: int in HEIGHTS:
		if (candidate > pixels.y or float(candidate) / pixels.y < 0.25) and candidate != height: continue
		var scale := clampf(float(candidate) / pixels.y, 0.25, 1.0)
		var actual := Vector2i(Vector2(pixels) * scale)
		select.add_item("%d × %d%s" % [actual.x, actual.y, "（目标 %dp）" % candidate if actual.y != candidate else ""])
		select.set_item_metadata(select.item_count - 1, candidate)
		if candidate == height: select.select(select.item_count - 1)
	if height == 0: select.select(0)
	var scene_pixels := Vector2i(Vector2(pixels) * window.scaling_3d_scale)
	_status.text = "输出：%d × %d · 场景：%d × %d\n较低分辨率会降低清晰度；阴影提交与 CPU 逻辑仍有独立开销。" % [pixels.x, pixels.y, scene_pixels.x, scene_pixels.y]
	_refreshing = false

func sync_controls() -> void:
	for spec in SPECS:
		if not controls.has(spec.key) or spec.target == "resolution": continue
		var control: Control = controls[spec.key]
		var value: Variant = value_for(spec.key)
		if control is CheckBox: control.set_pressed_no_signal(bool(value))
		elif control is SpinBox: control.set_value_no_signal(float(value))
		elif control is OptionButton:
			for index in control.item_count:
				if control.get_item_metadata(index) == value: control.select(index); break

func scene_section() -> String:
	return "scene:" + (world.scene_file_path if not world.scene_file_path.is_empty() else String(world.name))

func load_settings() -> void:
	if not save_enabled: return
	var config := ConfigFile.new()
	if config.load(config_path) != OK: return
	for spec in SPECS:
		var section: String = "display" if spec.get("scope", "scene") == "display" else scene_section()
		if not config.has_section_key(section, spec.key) or not available(spec): continue
		var valid: Variant = validated(spec, config.get_value(section, spec.key))
		if valid != null: overrides[spec.key] = valid

func save_settings() -> Error:
	if not save_enabled: return OK
	var config := ConfigFile.new()
	config.load(config_path)
	for spec in SPECS:
		var section: String = "display" if spec.get("scope", "scene") == "display" else scene_section()
		if overrides.has(spec.key): config.set_value(section, spec.key, overrides[spec.key])
		elif config.has_section_key(section, spec.key): config.erase_section_key(section, spec.key)
	var result := config.save(config_path)
	if result != OK and _status: _status.text += "\n本次修改已生效，但未能保存显示设置。"
	return result

func reset_defaults() -> void:
	if not configured: return
	# Restore only keys the user changed; leave unrelated visual and gameplay settings alone.
	var changed := overrides.keys()
	for key in changed: overrides[key] = defaults[key]
	apply_settings()
	overrides.clear()
	window.scaling_3d_scale = _native_scale
	var style := world.get_node_or_null("VisualSample")
	if style: style.apply_style()
	refresh_resolution()
	sync_controls()
	if save_enabled: _save_timer.start()

func _exit_tree() -> void:
	if is_instance_valid(_save_timer) and not _save_timer.is_stopped() and save_enabled: save_settings()
