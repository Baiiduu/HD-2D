extends Node
## 菜单内分帧准备真实反馈对象；不调用攻击、刷怪、伤害或声音播放入口。
const REMAINS := preload("res://scripts/enemies/enemy_remains_materials.gd")
const BODY_LAYOUT := preload("res://scripts/rendering/sprite_body_layout.gd")
# 菜单仍逐帧响应输入；缩短整条准备队列的调度等待，不省略预热内容。
const BUDGET_USEC := 6000
var completed := false
var prepared_audio: Array[AudioStream] = []
var report := {"jobs": 0, "cpu_usec": 0, "longest_job_usec": 0, "audio": 0, "textures": 0, "fonts": 0, "skills": 0, "body_layouts": 0}
var _world: Node
var _jobs: Array[Callable] = []
var _cursor := 0
var _seen := {}
var _fonts := {}
var _font_layer: CanvasLayer
var _proxies: Node3D
var _draws_left := -1
var _bank: CoreSoundBank
var _body_textures := {}
var _body_layouts := {}

func start(world: Node) -> void:
	if _world: return
	_world = world
	_proxies = Node3D.new()
	_proxies.name = "PreparedSurfaces"
	_proxies.hide()
	add_child(_proxies)
	_font_layer = CanvasLayer.new()
	_font_layer.layer = -100
	add_child(_font_layer)
	var player: Player = world.get_node("Player")
	for component in [player.body_ricochet, player._blink, player.flight_trail, player.motion_feedback, player.surface_feedback, player.fire_trail, player.bounce_effect, player.hurt_effect, player.sword]:
		if component: _jobs.append(component.prepare_feedback)
	for resource in [player.animations, player.action_visuals, player.sword_rules]: _queue_resource(resource)
	_queue_body_frames(player.animations, player.sprite)
	for action in [&"charge", &"flight", &"recovery", &"normal_attack", &"flight_attack", &"bounce"]:
		_queue_body_frames(player.action_visuals.frames_for(action), player.sprite)
	var wave: WavePrototype = world.get_node("WavePrototype")
	var manager := wave.run_skill_manager
	for id in manager.get_registered_ids():
		if not manager.is_skill_available(id): continue
		var skill := manager.get_skill(id)
		if skill.has_method("prepare_feedback"):
			_jobs.append(skill.prepare_feedback)
			report.skills += 1
		_queue_resource(skill.get_skill_definition())
		for property in skill.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE: _queue_variant(skill.get(property.name))
	if wave.enemy_catalog:
		for enemy in wave.enemy_catalog.enemies: _queue_resource(enemy, true)
	_jobs.append(func():
		if is_instance_valid(wave._prepared_feedback): wave._prepared_feedback.prepare_projectiles())
	_jobs.append(func():
		if is_instance_valid(wave._spawn_shadows): wave._spawn_shadows.prepare_feedback(wave.max_active_enemies))
	var growth := wave.get_node("RunGrowth") as RunGrowth
	_queue_resource(growth.pickup_scene)
	_jobs.append(func():
		if growth.pickup_scene:
			var pickup := growth.pickup_scene.instantiate() as ExperiencePickup
			pickup.name = "PreparedExperience"
			pickup.process_mode = Node.PROCESS_MODE_DISABLED
			_proxies.add_child(pickup)
		var telegraph := EnemyTelegraph.new()
		telegraph.name = "PreparedTelegraph"
		_proxies.add_child(telegraph))
	_bank = world.get_node("MapEffects/CoreFeedbackAudio").sounds
	_queue_resource(_bank)
	var core := world.get_node("MapEffects/CoreFeedbackAudio") as CoreFeedbackAudio
	for clips in [core._loop_clips,core._charge_wind_clips,core._flight_clips]: _queue_variant(clips)
	var music := world.get_node("MapEffects/BGM") as BackgroundMusic
	_queue_variant(music.playlists)
	if music.playlists.is_empty(): _queue_resource(music.music_stream)
	var weather := world.get_node("MapEffects/Weather")
	_queue_resource(weather.rain_sound)
	_queue_resource(weather.wind_sound)
	for node in world.find_children("*", "PlayerMovementAudio", true, false): _queue_resource(node.sounds)
	for node in world.find_children("*", "UIAudio", true, false): _queue_resource(node.sounds)
	for style in wave.get_node("DamageNumbers").number_styles:
		_queue_font(style.number_font if style.number_font else ThemeDB.fallback_font, style.number_font_size, style.number_outline_size)
	for label: Label in world.find_children("*", "Label", true, false):
		_queue_font(label.get_theme_font("font"), label.get_theme_font_size("font_size"), label.get_theme_constant("outline_size"), label.text)
	var presentation := world.get_node("WavePresentation")
	_queue_resource(presentation.settings)
	_jobs.append(func():
		for closing in [false,true]:
			presentation.prepare_feedback(closing)
			for label: Label in presentation.find_children("*","Label",true,false):
				_queue_font(label.get_theme_font("font"),label.get_theme_font_size("font_size"),label.get_theme_constant("outline_size"),label.text))
	var canvas_seen := {}
	for item: CanvasItem in world.find_children("*","CanvasItem",true,false):
		if not item.material or canvas_seen.has(item.material): continue
		canvas_seen[item.material] = true
		var material: Material = item.material
		_jobs.append(func():
			var card := ColorRect.new()
			card.material = material
			card.size = Vector2(8,8)
			_font_layer.add_child(card))
	if DisplayServer.get_name() != "headless": RenderingServer.frame_post_draw.connect(_rendered)
	set_process(true)

func _queue_body_frames(frames: SpriteFrames, source: Sprite3D) -> void:
	if not frames or DisplayServer.get_name() == "headless": return
	for animation in frames.get_animation_names():
		for index in frames.get_frame_count(animation):
			var texture := frames.get_frame_texture(animation,index)
			if not texture or _body_textures.has(texture): continue
			_body_textures[texture] = true
			for flipped in [false,true]: _jobs.append(_prepare_body_card.bind(texture,flipped,source))

func _prepare_body_card(texture: Texture2D, flipped: bool, source: Sprite3D) -> void:
	var card := Sprite3D.new()
	card.texture = texture
	for property in PlayerFlightTrail.SPRITE_PROPERTIES: card.set(property,source.get(property))
	card.flip_h = flipped
	var key := BODY_LAYOUT.key_for(card)
	var cache: Dictionary = source.get_meta(BODY_LAYOUT.META, {})
	if _body_layouts.has(key) or cache.has(key):
		card.free()
		return
	_body_layouts[key] = true
	card.material_override = source.material_override
	_proxies.add_child(card)
	# 和正式遮罩一样，等 Sprite3D 完成本帧的延迟网格更新再读取。
	_enqueue_body_layout.call_deferred(card,source)

func _enqueue_body_layout(card: Sprite3D, source: Sprite3D) -> void:
	if not is_inside_tree(): return
	_draws_left = -1
	_jobs.append(func():
		BODY_LAYOUT.sample(card,source)
		report.body_layouts += 1
		card.queue_free())

func _process(_delta: float) -> void:
	var start_time := Time.get_ticks_usec()
	while _cursor < _jobs.size() and Time.get_ticks_usec()-start_time < BUDGET_USEC:
		var stamp := Time.get_ticks_usec()
		_jobs[_cursor].call()
		_cursor += 1
		var elapsed := Time.get_ticks_usec()-stamp
		report.jobs += 1
		report.cpu_usec += elapsed
		report.longest_job_usec = maxi(report.longest_job_usec, elapsed)
	if _cursor < _jobs.size(): return
	if _draws_left < 0:
		_draws_left = 2
		return
	if DisplayServer.get_name() == "headless": _rendered()
	if _draws_left > 0: return
	completed = true
	_jobs.clear()
	_font_layer.hide()
	set_process(false)
	_disconnect_render()

func _rendered() -> void:
	if _draws_left > 0: _draws_left -= 1

func _queue_variant(value: Variant, enemy := false) -> void:
	if value is Resource: _queue_resource(value, enemy)
	elif value is Array:
		for item in value: _queue_variant(item, enemy)
	elif value is Dictionary:
		for item in value.values(): _queue_variant(item, enemy)

func _queue_resource(resource: Resource, enemy := false) -> void:
	if not resource or resource is Script: return
	var key := [resource, enemy]
	if _seen.has(key): return
	_seen[key] = true
	_jobs.append(_prepare_resource.bind(resource, enemy))

func _prepare_resource(resource: Resource, enemy: bool) -> void:
	if resource is PackedScene:
		var state: SceneState = resource.get_state()
		for i in state.get_node_count():
			_queue_resource(state.get_node_instance(i), enemy)
			for p in state.get_node_property_count(i): _queue_variant(state.get_node_property_value(i,p), enemy)
	elif resource is CoreSoundBank:
		for row in CoreSoundBank.AUDITION:
			if row[0] != &"kill_slime_retired": _queue_variant(resource.clips_for(row[0]))
	elif resource is AudioStreamRandomizer:
		for index in resource.streams_count: _queue_resource(resource.get_stream(index))
	elif resource is AudioStream:
		if _bank and _bank.filter_clips([resource]).is_empty(): return
		if not (resource is AudioStreamWAV or resource is AudioStreamOggVorbis or resource is AudioStreamMP3): return
		# 手动解码到丢弃的内存缓冲，完全不连接 AudioStreamPlayer 或音频总线。
		var playback: AudioStreamPlayback = resource.instantiate_playback()
		if playback:
			playback.start()
			playback.mix_audio(1.0, 256)
			playback.stop()
			prepared_audio.append(resource)
			report.audio += 1
	elif resource is SpriteFrames:
		for animation in resource.get_animation_names():
			for index in resource.get_frame_count(animation): _queue_resource(resource.get_frame_texture(animation,index), enemy)
	elif resource is Texture2D:
		resource.get_rid()
		report.textures += 1
		if resource is AtlasTexture: _queue_resource(resource.atlas, enemy)
		elif enemy:
			for variant in [[true,false], [false,false], [true,true]]:
				var mesh := MeshInstance3D.new()
				mesh.mesh = QuadMesh.new()
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.material_override = REMAINS.material(resource, variant[0], variant[1])
				_proxies.add_child(mesh)
	elif resource is Font or resource is Shader: return
	else:
		for property in resource.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE: _queue_variant(resource.get(property.name), enemy)

func _queue_font(font: Font, size: int, outline: int, text := "") -> void:
	var key := [font,size,outline]
	if _fonts.has(key):
		_fonts[key].text += text
		if _fonts[key].label: _fonts[key].label.text = _fonts[key].text
		return
	_fonts[key] = {"text":text + "0123456789.,+-× 第波无尽开始结束清空胜利失败升级继续", "label":null}
	_jobs.append(func():
		var label := Label.new()
		label.add_theme_font_override("font",font)
		label.add_theme_font_size_override("font_size",size)
		label.add_theme_constant_override("outline_size",outline)
		label.text = _fonts[key].text
		_fonts[key].label = label
		_font_layer.add_child(label)
		font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size)
		report.fonts += 1)

func _disconnect_render() -> void:
	if RenderingServer.frame_post_draw.is_connected(_rendered): RenderingServer.frame_post_draw.disconnect(_rendered)

func _exit_tree() -> void:
	_disconnect_render()
	_jobs.clear()
