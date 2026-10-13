@tool
extends RefCounted

const CATEGORIES := ["视觉", "人物", "战斗与成长", "地图与地编", "UI", "声音", "物品与规则"]
const LABELS := {
	"style_wind": "时段风摆倍率", "style_wind_tempo": "时段风摆节奏", "style_fireflies": "时段光点可见比例",
	"region_wind": "区域风摆倍率", "region_fireflies": "区域光点可见比例", "region_blend_width": "动态区域过渡宽度",
	"transition_seconds": "环境动态渐变时间", "battle_fireflies_enabled": "战区外围光点", "battle_firefly_height": "外围光点高度",
	"night_firefly_size": "夜晚光点尺寸倍率",
	"style": "画面风格", "runtime_switch_enabled": "游戏内切换开关", "style_key": "切换按键",
	"pixel_art_enabled": "统一像素美术", "color_ramps_enabled": "材质色阶开关", "color_palette": "材质色板",
	"distance": "镜头距离", "pitch_degrees": "俯角", "fov": "视野 FOV", "focus_height": "焦点高度",
	"dof_amount": "景深强度", "smoothing": "跟随平滑度", "dead_zone": "跟随死区", "yaw_degrees": "初始朝向",
	"exposure": "曝光", "brightness": "亮度", "contrast": "对比度", "saturation": "饱和度", "bloom": "辉光",
	"ambient_energy": "环境光强度", "moon_energy": "主光强度", "fog_amount": "雾强度", "wetness": "地面湿润",
	"hemisphere_fill_enabled": "半球补光开关", "hemisphere_sky_color": "半球天空色", "hemisphere_ground_color": "半球地面反弹色",
	"value_sample_enabled": "明暗层次样板开关", "value_sample_profile": "明暗层次配置",
	"original_material_palette": "原版材质色板", "material_palette": "层次材质色板", "original_foliage_palette": "原版花草色板", "foliage_palette": "层次花草色板", "lighting_presets": "层次光影配置",
	"weather_mode": "晴雨模式", "rain_intensity": "雨量比例", "rain_amount": "雨丝数量", "wind_strength": "风力",
	"ground_rain_enabled": "地面落雨开关", "ground_splash_size": "地面雨纹半径", "ground_splash_density": "地面雨纹密度", "ground_splash_strength": "地面雨纹强度",
	"ground_sheen": "草地湿亮斑覆盖",
	"blink_plant_strength": "闪身压弯花草", "blink_rain_strength": "闪身带偏雨滴",
	"speed": "人物速度", "blink_distance": "闪身距离", "blink_cooldown": "闪身间隔", "jump_height": "跳跃高度",
	"damage": "伤害", "attack_range": "攻击范围", "attack_interval": "攻击间隔", "fan_angle": "扇角",
	"definitions": "本局增益列表", "attribute": "增益属性", "bonus_per_level": "每级增益比例", "max_level": "增益等级上限", "bonus_cap": "同类总增幅上限",
	"card_text_color": "成长卡片文字颜色",
	"skill_definition": "本局技能定义", "skill_paths": "起始技能组件", "levels": "技能等级列表", "parameters": "等级倍率与行为参数",
	"show_run_skill_icons": "本局技能图标", "level_font_size": "技能等级字号",
	"windup_time": "起手时间", "sweep_time": "扫击时间", "fade_time": "收尾时间", "knockback_distance": "击退距离",
	"effect_opacity": "特效透明度", "effect_energy": "特效亮度", "health": "生命", "attack_damage": "怪物攻击伤害",
	"move_speed": "怪物速度", "experience_reward": "经验掉落", "waves": "波次列表", "entries": "出怪编排",
	"spawn_interval": "出怪间隔", "spawn_warning": "出场预告", "retry_key": "重试按键", "rules": "规则资源",
	"max_active_enemies": "同场怪物上限", "top_margin": "顶部边距", "hint_font_size": "波次提示字号", "hint_opacity": "波次提示透明度",
	"endless_mode": "无尽模式", "endless_enemies_per_wave": "无尽每波增加数量", "endless_max_enemies": "无尽每波数量上限",
	"endless_interval_reduction": "无尽每波刷怪间隔减幅", "endless_min_spawn_interval": "无尽最短刷怪间隔",
	"grass_density": "草丛密度", "flower_density": "花簇密度", "paint_palette": "地表画笔列表", "data": "地形数据",
	"grass_variation_enabled": "草地深浅开关", "grass_variation_strength": "草地深浅强度", "grass_variation_size": "草地斑块大小",
	"core_size": "战区中心尺寸", "loop_width": "绕行带宽度", "ui_scale": "界面缩放", "font_size": "文字字号",
	"first_level_experience": "首次升级经验", "per_level_increase": "每级经验增量", "curve_increase": "经验曲线增量", "level_cap": "本局等级上限",
	"bar_width": "属性条宽度", "slot_size": "槽位尺寸", "slot_spacing": "槽位间隔", "screen_margin": "屏幕边距", "glow_strength": "辉光强度",
	"track_width": "经验槽宽度", "badge_width": "等级底片宽度", "attribute_gap": "血蓝条下方间隔", "follow_attributes": "经验条跟随属性条",
	"medium_threshold": "紫色宝石经验阈值", "large_threshold": "暖金宝石经验阈值", "gem_height": "宝石世界高度",
	"bob_amplitude": "宝石漂浮幅度", "bob_speed": "宝石漂浮速度", "absorb_size": "吸收微光尺寸", "absorb_opacity": "吸收微光透明度",
	"flow_enabled": "经验条流光开关", "flow_interval": "流光间隔", "flow_duration": "流光扫过时间", "flow_width": "流光宽度", "flow_strength": "流光亮度",
	"glint_size": "端点星芒尺寸", "glint_strength": "端点星芒强度", "glint_pulse_speed": "端点呼吸速度",
	"trail_length": "宝石流光长度", "trail_size": "尾迹光点尺寸", "trail_brightness": "宝石尾迹亮度", "trail_opacity": "宝石尾迹透明度",
	"background_opacity": "暗底透明度", "volume_db": "音量", "pixel_stone_detail_strength": "卵石暗点保留",
	"music_volume_db": "背景音乐音量", "rain_volume_db": "雨声音量", "wind_volume_db": "风声音量",
	"audio_enabled": "攻击音效开关", "audio_volume_db": "攻击音效音量", "hit_volume_db": "命中声增益",
	"sweep_sounds": "挥击音源", "hit_sounds": "命中音源", "audio_bus": "音频总线", "audio_pitch": "攻击音高",
	"audio_pitch_variation": "攻击音高变化", "hit_sound_limit": "每击命中声上限", "hit_sound_interval": "命中声最小间隔",
	"rotation_sound_interval": "旋转声音脉冲间隔",
	"audio_manager": "公共声音管理器", "max_voices": "全局战斗声音上限", "important_reserve": "重要声音预留",
	"per_cue_limit": "同种声音同时上限", "minimum_interval": "同源声音最小间隔", "merge_window": "密集反馈合并时间",
	"merge_radius": "密集反馈合并半径", "near_distance": "声音清晰半径", "far_distance": "声音最远距离",
	"distance_falloff": "声音距离衰减", "offscreen_gain": "画面外普通声音增益", "panning_strength": "左右声像强度",
	"listener_height": "听觉中心高度", "combat_volume_db": "战斗分组增益", "ambience_volume_db": "环境分组增益",
	"ui_volume_db": "UI 分组增益", "movement_volume_db": "人物动作分组增益", "compression_enabled": "战斗压缩开关",
	"compression_threshold_db": "战斗压缩阈值", "compression_ratio": "战斗压缩比例", "limiter_enabled": "总输出限幅开关",
	"limiter_ceiling_db": "总输出峰值上限",
}
const COMMON := {
	"game_audio.gd": ["enabled", "max_voices", "important_reserve", "merge_window", "far_distance", "combat_volume_db", "music_volume_db"],
	"environment_dynamics.gd": ["enabled", "style_wind", "style_wind_tempo", "style_fireflies", "night_firefly_size", "region_wind", "region_fireflies", "region_blend_width", "transition_seconds", "battle_fireflies_enabled"],
	"spawn_visual_sample.gd": ["style", "runtime_switch_enabled", "style_key", "pixel_art_enabled", "color_ramps_enabled", "color_palette", "grass_variation_enabled", "grass_variation_strength", "grass_variation_size", "value_sample_enabled", "value_sample_profile"],
	"follow_camera.gd": ["distance", "pitch_degrees", "fov", "dof_amount", "focus_height"],
	"art_direction.gd": ["exposure", "contrast", "saturation", "bloom", "moon_energy", "ambient_energy", "hemisphere_fill_enabled", "hemisphere_sky_color", "hemisphere_ground_color"],
	"weather.gd": ["weather_mode", "rain_intensity", "ground_rain_enabled", "ground_splash_size", "ground_splash_density", "ground_splash_strength", "wind_strength", "blink_plant_strength", "blink_rain_strength", "rain_volume_db", "wind_volume_db"],
	"player.gd": ["speed", "blink_distance", "blink_cooldown", "jump_height"],
	"fan_auto_attack.gd": ["damage", "attack_range", "attack_interval", "fan_angle", "effect_opacity", "skill_definition", "audio_enabled", "audio_volume_db", "hit_sound_limit"],
	"run_buffs.gd": ["definitions"],
	"growth_buff_definition.gd": ["bonus_per_level", "max_level", "bonus_cap"],
	"combat_skill_definition.gd": ["levels"],
	"combat_skill_level.gd": ["parameters"],
	"wave_enemy_definition.gd": ["health", "move_speed", "attack_damage", "experience_reward"],
	"wave_prototype.gd": ["waves", "endless_mode", "endless_enemies_per_wave", "endless_max_enemies", "endless_interval_reduction", "endless_min_spawn_interval", "max_active_enemies", "retry_key", "show_ui"],
	"wave_hud.gd": ["enabled", "font_size", "hint_font_size", "top_margin", "text_color"],
	"battle_area.gd": ["core_size", "loop_width", "core_density", "edge_density"],
	"ground_dressing.gd": ["grass_density", "flower_density"],
	"terrain.gd": ["data", "paint_palette"],
	"bgm.gd": ["music_volume_db"],
	"experience_rules.gd": ["first_level_experience", "per_level_increase", "level_cap"],
	"loadout_ui.gd": ["ui_scale", "font_size"],
	"skill_hud.gd": ["slot_size", "slot_spacing", "screen_margin", "glow_strength"],
	"attribute_hud.gd": ["bar_width", "screen_margin", "glow_strength"],
	"experience_hud.gd": ["track_width", "follow_attributes", "attribute_gap", "background_opacity", "show_values", "flow_enabled", "flow_strength", "glint_strength"],
	"experience_pickup.gd": ["medium_threshold", "large_threshold", "gem_height", "bob_amplitude", "trail_length", "trail_brightness"],
	"item_quickbar.gd": ["slot_size", "slot_spacing", "background_opacity"],
	"ui_audio.gd": ["volume_db"],
}

var entries: Array[Dictionary] = []
var _resources := {}
var _descriptions := {}

func collect(scene: Node) -> Array[Dictionary]:
	entries.clear()
	_resources.clear()
	if scene: _visit(scene, scene)
	return entries

func _visit(node: Node, scene: Node) -> void:
	var path := String(scene.get_path_to(node))
	if node.get_script(): _object(node, path, node)
	for child in node.get_children():
		# 仅登记场景拥有的节点，跳过地形、建筑和 UI 的运行时生成对象。
		if child.owner != null: _visit(child, scene)

func category(filename: String, group: String) -> String:
	if filename == "environment_dynamics.gd": return "视觉"
	if filename in ["game_audio.gd", "bgm.gd", "player_movement_audio.gd", "movement_sound_bank.gd", "ui_audio.gd", "ui_sound_bank.gd"] or "声音" in group or "音效" in group or "风声" in group: return "声音"
	if filename in ["player.gd", "player_blink.gd", "character_lighting.gd"]: return "人物"
	if filename == "wave_hud.gd": return "UI"
	if filename.begins_with("wave_") or filename.begins_with("combat_skill_") or filename in ["fan_auto_attack.gd", "slime.gd", "run_growth.gd", "run_skills.gd", "run_buffs.gd", "growth_buff_definition.gd", "experience_rules.gd", "experience_pickup.gd"]: return "战斗与成长"
	if filename in ["spawn_visual_sample.gd", "spawn_visual_preset.gd", "pixel_color_palette.gd", "value_lighting_profile.gd", "art_direction.gd", "weather.gd", "follow_camera.gd", "atmospheric_light.gd", "daylight_preview.gd", "map_effects.gd", "planar_water_reflection.gd"]: return "视觉"
	if filename in ["training_rules.gd", "loadout_catalog.gd", "equipment_definition.gd", "skill_definition.gd", "item_definition.gd"]: return "物品与规则"
	if filename.ends_with("_ui.gd") or filename.ends_with("_hud.gd") or filename in ["item_quickbar.gd", "inventory_book_page.gd", "growth_choice_card.gd", "growth_choice_option.gd"]: return "UI"
	return "地图与地编"

func _object(object: Object, path: String, node: Node) -> void:
	var script := object.get_script() as Script
	if not script: return
	var filename := script.resource_path.get_file()
	var group := "基础"
	var subgroup := ""
	# 非 @tool 脚本在编辑器中是占位实例；从脚本读取导出信息，避免遗漏人物和战斗参数。
	var properties: Array[Dictionary] = script.get_script_property_list()
	# FOV 是 Camera3D 内置属性，与脚本参数放在同一入口。
	if object is Camera3D:
		_add(object, path, node, filename, "构图", "fov")
	for info in properties:
		var usage: int = info.usage
		if usage & PROPERTY_USAGE_GROUP:
			group = info.name
			subgroup = ""
			continue
		if usage & PROPERTY_USAGE_SUBGROUP:
			subgroup = info.name
			continue
		if not usage & PROPERTY_USAGE_EDITOR: continue
		var property: String = info.name
		_add(object, path, node, filename, group + (" / " + subgroup if not subgroup.is_empty() else ""), property)
		var value: Variant = object.get(property)
		if value is Resource: _resource(value, path + " → " + LABELS.get(property, property), node)
		elif value is Array:
			for index in value.size():
				if value[index] is Resource: _resource(value[index], path + " → " + property + "[%d]" % index, node)
	if filename == "spawn_visual_sample.gd":
		for suffix in ["original", "lumina_day", "lumina_rain", "lumina_night"]:
			_resource(load("res://data/visual/spawn_" + suffix + ".tres"), "风格预设 → " + suffix, node)

func _resource(resource: Resource, path: String, node: Node) -> void:
	if _resources.has(resource.get_instance_id()): return
	_resources[resource.get_instance_id()] = true
	if resource.get_script(): _object(resource, path, node)
	elif resource is ShaderMaterial:
		for info in resource.get_property_list():
			var property: String = info.name
			if not property.begins_with("shader_parameter/") or not info.usage & PROPERTY_USAGE_EDITOR: continue
			var name := property.trim_prefix("shader_parameter/")
			entries.append({"object": resource, "node": node, "property": property, "label": name, "category": "视觉",
				"group": "底层着色器（高级）", "path": path, "common": false,
				"description": "直接编辑材质；若此项由视觉、相机或天气控制，请优先调节对应控制节点。",
				"search": ("视觉 材质 着色器 " + path + " " + name).to_lower()})

func _add(object: Object, path: String, node: Node, filename: String, group: String, property: String) -> void:
	var label: String = LABELS.get(property, property)
	var section := category(filename, group)
	var description: String = _documentation(object.get_script()).get(property, "")
	entries.append({"object": object, "node": node, "property": property, "label": label, "category": section,
		"group": group, "path": path, "common": property in COMMON.get(filename, []),
		"description": description, "search": (section + " " + group + " " + path + " " + label + " " + property + " " + description).to_lower()})

func _documentation(script: Script) -> Dictionary:
	if _descriptions.has(script.resource_path): return _descriptions[script.resource_path]
	var descriptions := {}
	if script.get_base_script(): descriptions.merge(_documentation(script.get_base_script()))
	var pattern := RegEx.create_from_string("^@export[^\\n]*\\bvar\\s+(\\w+)")
	var comments := PackedStringArray()
	for line in FileAccess.get_file_as_string(script.resource_path).split("\n"):
		line = line.strip_edges()
		if line.begins_with("##"):
			comments.append(line.trim_prefix("##").strip_edges())
			continue
		var match := pattern.search(line)
		if match: descriptions[match.get_string(1)] = "\n".join(comments)
		if not line.is_empty(): comments.clear()
	_descriptions[script.resource_path] = descriptions
	return descriptions
