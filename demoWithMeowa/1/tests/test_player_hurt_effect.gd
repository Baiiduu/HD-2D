extends "res://tests/test_aim_path_preview.gd"

func target_checks() -> void:
	pass

func path_checks() -> void:
	check(player.has_signal("damaged"), "人物提供实际扣血事件，不从通用生命／魔力变化推测受击")
	var effect = player.get("hurt_effect")
	check(effect != null, "人物创建独立受伤粒子组件")
	if not effect: return
	var settings = load("res://data/combat/scenes/world/player/action_visuals.tres").duplicate()
	check(settings.get("hurt_particles_enabled") == true and not PlayerActionVisuals.new().get("hurt_particles_enabled"), "正式 World 独立开启，City 与共享默认不自动改变")
	player.action_visuals = settings
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(player)
	for property in ["hurt_particles_enabled", "hurt_particle_count", "hurt_particle_seconds", "hurt_particle_spread_pixels", "hurt_particle_size_pixels", "hurt_particle_color"]:
		check(entries.any(func(entry): return entry.property == property and entry.category == "人物"), "参数总览可调：" + property)
	player.sprite.pixel_size = 0.02
	player.sprite.scale = Vector3.ONE * 0.9
	check(not effect.is_processing(), "未受击时不执行空闲粒子更新")
	var damage_events: Array[float] = []
	player.connect("damaged", func(amount): damage_events.append(amount))
	var health: float = player.current_health
	player.take_damage(0.0)
	player.take_damage(-1.0)
	player.take_damage(NAN)
	player.spend_mana(1.0)
	player.heal(1.0)
	player._max_health -= 1.0
	player.current_health = player.max_health
	check(damage_events.is_empty() and not effect.is_processing(), "无效伤害、魔力、回血和上限变化均不产生受击粒子")
	player._max_health += 1.0
	player.current_health = health
	seed(3251)
	var expected := randi()
	seed(3251)
	check(player.take_damage(3.0) == 3.0 and damage_events == [3.0], "真实扣血只发一次事件，伤害数值保持原规则")
	check(randi() == expected, "表现不消耗玩法的全局随机序列")
	var particles = effect.get("particles")
	check(particles != null and particles.active and particles.multimesh.visible_instance_count == 8, "一次受伤只发射八颗红色像素粒子")
	if not particles: return
	effect.set_process(false)
	var starts: Array = particles._transforms.slice(0, particles._written)
	var valid := true
	var pixel := player.sprite.pixel_size * player.sprite.global_basis.x.length()
	for index in particles._written:
		var tint: Color = particles._colors[index]
		var size: float = starts[index].basis.x.length()
		valid = valid and tint.r > tint.g * 2.0 and tint.r > tint.b * 2.0
		valid = valid and size >= pixel - 0.00001 and size <= pixel * 3.0 + 0.00001
		valid = valid and tint.a >= 0.24 - 0.00001 and tint.a <= 0.32 + 0.00001
	check(valid, "红色、1～3 原生像素尺寸和短寿命独立于怪物金色碎屑")
	check(particles.get_child_count() == 0 and particles.capacity == 64 and not particles.is_processing(), "复用单个小容量批次，不创建逐颗粒子节点")
	check(particles.material_override.get_shader_parameter("hurt_pixels") == true and particles.material_override.next_pass != null, "像素方片使用共用真实遮挡通路")
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(8, 8, 8)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	player.position += Vector3(2, 0, 1)
	camera.rotate_y(PI / 2.0)
	effect.call("_process", 0.04)
	check(particles._transforms.slice(0, particles._written) == starts, "已发出的粒子保留世界轨迹，不随人物或 Q/E 转向重新定位")
	var clock: float = particles.clock
	session.set_combat_frozen(true)
	effect.call("_process", 0.2)
	check(particles.clock == clock, "升级冻结暂停粒子运动与消散")
	session.set_combat_frozen(false)
	effect.call("_process", 0.4)
	check(not particles.active and not particles.visible and not effect.is_processing(), "短时消散后隐藏并停止更新")
	var old_mesh = particles.multimesh
	player.take_damage(2.0)
	check(effect.get("particles") == particles and particles.multimesh == old_mesh, "后续受伤复用网格、材质和实例缓冲")
	settings.set("hurt_particles_enabled", false)
	effect.call("_process", 0.01)
	player.take_damage(2.0)
	check(not particles.active and not effect.is_processing(), "关闭表现立即清理且不再发射，不改变实际扣血")
	settings.set("hurt_particles_enabled", true)
	player.take_damage(2.0)
	session.run_started.emit()
	check(not particles.active, "重试／新局清理上局残留")
	var count: int = particles.emitted
	session._run_population = WavePopulationRules.new()
	session._run_population.simulation_mode = true
	session._hurt_clock = 0.0
	health = player.current_health
	check(session._damage_player(5.0, session._generation), "怪潮模拟继续保留真实怪物命中资格")
	check(player.current_health == health and particles.emitted == count, "人物免伤模拟不伪造扣血粒子")
	session._run_population = null
	session._hurt_clock = 0.0
	session._damage_player(5.0, session._generation)
	check(player.current_health == health - 5.0 and particles.emitted == count + 8, "正式怪物伤害入口实际触发受伤粒子")
	session.phase = WavePrototype.Phase.REST
	session.phase_changed.emit(session.phase)
	check(not particles.active and not effect.is_processing(), "清波／结束战斗清理粒子")
	player.take_damage(1.0)
	check(not particles.active, "非战斗生命调整不发射")
	session.phase = WavePrototype.Phase.BATTLE
	player.take_damage(99999.0)
	check(player.current_health == 0.0 and particles.active, "真实致死伤害同样提供一次受击反馈，不新增伤害规则")
	count = particles.emitted
	player.take_damage(1.0)
	check(particles.emitted == count, "已经零血时不重复伪造受击")
	session.run_ended.emit("defeat")
	check(not particles.active and not effect.is_processing(), "结算退出清理，组件不残留更新")
	var bank: CoreSoundBank = load("res://data/audio/core_sound_bank_world.tres")
	check(bank.clips_for(&"player_hurt").is_empty(), "人物受击声音继续关闭")
