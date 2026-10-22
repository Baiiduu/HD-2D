extends SceneTree

const WORLD := "res://scenes/world/world.tscn"
const LAYOUT := preload("res://scripts/rendering/sprite_body_layout.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
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
		node.get_node("WorldEntry").preview_on_direct_run = false
		node.get_node("WorldMainMenu").prewarm_entry = false)
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	var world := load(WORLD).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var player: Player = world.get_node("Player")
	var start := player.global_transform
	var health := player.current_health
	var startup = world.get_node("WorldMainMenu")
	startup.open_menu()
	while startup.get("_feedback_warmup") == null: await process_frame
	var warmup = startup._feedback_warmup
	warmup.set_process(false)
	var isolated_random := true
	while not warmup.completed:
		seed(8127)
		var expected := randi()
		seed(8127)
		warmup._process(0.0)
		isolated_random = isolated_random and randi() == expected
		await process_frame
	check(isolated_random,"每次同步预热都不消耗出怪或成长的全局随机流")
	var deadline := Time.get_ticks_msec()+20000
	while not startup.game_ready and Time.get_ticks_msec()<deadline: await create_timer(0.01).timeout
	check(startup.game_ready,"主菜单必须等反馈准备完成才允许开始")
	check(player.fire_trail._mesh != null,"首次飞行之前准备地火网格、材质与实例缓冲")
	check(player.fire_trail._sparks != null,"首次飞行之前准备火星实例池")
	check(player.body_ricochet._charge_effect != null,"菜单期间准备蓄力反馈")
	check(not player.bounce_effect._pool.is_empty(),"菜单期间准备碰墙爆点池")
	var wave: WavePrototype = world.get_node("WavePrototype")
	check(warmup._proxies.get_node_or_null("PreparedExperience") is ExperiencePickup and wave.get_node("RunGrowth")._drops.is_empty(),"经验外观已准备，但不登记实际掉落")
	check(warmup._proxies.get_node_or_null("PreparedTelegraph") is EnemyTelegraph,"准备共用怪物招式预告材质和网格")
	check(wave._spawn_shadows._mesh.multimesh.instance_count >= wave.max_active_enemies and wave._spawn_shadows._entries.is_empty(),"预留当前地图容量的出怪剪影缓冲，但不产生出怪预告")
	check(player.sword._effect.mesh != null and not player.sword._tail_pool.is_empty(),"准备正式剑光及消散余迹")
	check(TerrainPath.horizontal_distance(player.global_position,start.origin)<0.001 and player.current_health==health and not player.body_ricochet.flying and not player.body_ricochet.charging,"准备不发射、不改血量或水平移动人物")
	check(world.get_node("WavePrototype").enemies.is_empty() and world.get_node("WavePrototype").phase == WavePrototype.Phase.READY,"准备不刷怪或启动战斗")
	check(not player.fire_trail.visible and not player.fire_trail.is_processing(),"预热后地火保持隐藏和空闲停工")
	check(warmup.report.audio>0 and warmup.report.textures>0 and warmup.report.fonts>0,"实际准备声音解码、贴图与字形")
	var presentation := world.get_node("WavePresentation")
	var title: Label = presentation._opening_title._labels[1]
	check(warmup._fonts.has([title.get_theme_font("font"),presentation.settings.opening_title_size,3]) and warmup._fonts.has([title.get_theme_font("font"),presentation.settings.clear_title_size,3]),"开场和清波两个字号都提前准备")
	check(warmup.prepared_audio.all(func(clip): return clip not in warmup._bank.excluded_clips),"不解码地图停用的旧音源")
	check(world.get_node("MapEffects/GameAudio")._stats.played == 0,"预热不经过声音播放入口")
	check(not warmup.is_processing() and not warmup._proxies.visible and not warmup._font_layer.visible,"准备完成后所有载体隐藏并停止调度")
	var report: Dictionary = warmup.report.duplicate()
	warmup.start(world)
	check(warmup.report == report,"同一 World 不重复预热已有资源")
	var mesh: MultiMeshInstance3D = player.fire_trail._mesh
	var sparks: Node3D = player.fire_trail._sparks
	var capacity := mesh.multimesh.instance_count
	var children := player.fire_trail.get_child_count()
	player.fire_trail._travelled(player.global_position,player.global_position+Vector3.RIGHT*0.2,Vector3.RIGHT,0.02)
	check(player.fire_trail._mesh == mesh and player.fire_trail._sparks == sparks and mesh.multimesh.instance_count == capacity and player.fire_trail.get_child_count() == children,"首次飞行路段复用菜单中的网格、材质和缓冲")
	player.fire_trail.clear()
	var manager: RunSkillManager = world.get_node("WavePrototype").run_skill_manager
	for id in manager.get_registered_ids():
		if not manager.is_skill_available(id): continue
		var skill := manager.get_skill(id)
		if skill is RicochetStorm: check(is_instance_valid(skill._effect) and not skill._effect.is_processing(),"奔雷完整反馈已准备并处于闲置")
		elif skill is LightPierceAutoAttack or skill is PrismRicochetAutoAttack:
			check(not skill._effects.is_empty() and skill._effects.size()==skill._idle_effects.size(),"技能闲置池已准备："+String(id))
		check(manager.get_level(id)==0,"准备不学习技能："+String(id))
	var sprite := Sprite3D.new()
	sprite.texture = player.sprite.texture
	var key := LAYOUT.key_for(sprite)
	var expected_layout := [Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN]
	sprite.set_meta(LAYOUT.META,{key:expected_layout})
	sprite.position = Vector3(3,4,5)
	check(LAYOUT.sample(sprite)==expected_layout,"命中共享原生布局缓存不读取渲染器，位置变化不使局部布局失效")
	sprite.flip_h = not sprite.flip_h
	check(LAYOUT.key_for(sprite)!=key,"镜像切换不能复用相反朝向的 UV")
	sprite.free()
	print("PREWARM_REPORT ",JSON.stringify(report))
	world.free()
	await process_frame
	print("Combat prewarm: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
