extends SceneTree

var checks := 0
var failures := 0
var scene: Node3D
var terrain: Terrain
var player: Player
var camera: Camera3D
var wave: WavePrototype
var skills: RunSkillManager
var growth: RunGrowth
var attack: LightPierceAutoAttack
var fan: FanAutoAttack

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func settle(frames := 4) -> void:
	for frame in frames: await physics_frame

func clear_case() -> void:
	attack.cancel_current()
	attack._cooldown = 0.0
	var enemies := wave.enemies.duplicate()
	wave.enemies.clear()
	for enemy in enemies: enemy.free()
	player.position = Vector3(0, 0.03, 0)

func enemy_at(point: Vector3) -> WaveEnemy:
	assert(wave._spawn_enemy())
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = 1000.0
	enemy.position = point
	return enemy

func set_level(level: int) -> void:
	assert(attack.apply_skill_level(level))
	attack.set_physics_process(false)

func advance(seconds: float) -> void:
	for shot in attack._shots.duplicate(): attack._advance_shot(shot, seconds)

func wall_at(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 2.0, 4.0)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	wall.position = point
	return wall

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	scene = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-9, -9), Vector2i(19, 19))
	scene.add_child(terrain)
	player = Player.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	scene.add_child(player)
	camera = Camera3D.new()
	camera.position = Vector3(0, 9, 14)
	camera.rotation_degrees.x = -32.0
	scene.add_child(camera)
	player.movement_camera = camera
	wave = load("res://scenes/combat/wave_prototype.tscn").instantiate()
	# 只隔离本次接入的两种攻击，其它会话新增的技能保留在正式注册表。
	wave.get_node("RunSkillManager").skill_paths.clear()
	wave.get_node("RunSkillManager").skill_paths.append(NodePath("../FanAutoAttack"))
	wave.get_node("RunSkillManager").skill_paths.append(NodePath("../LightPierceAutoAttack"))
	wave.player = player
	wave.terrain = terrain
	wave.battle_area = Rect2(-12, -12, 24, 24)
	wave.show_ui = false
	scene.add_child(wave)
	root.add_child(scene)
	current_scene = scene
	player.set_physics_process(false)
	wave.set_physics_process(false)
	await settle(10)
	attack = wave.get_node("LightPierceAutoAttack")
	fan = wave.get_node("FanAutoAttack")
	skills = wave.get_node("RunSkillManager")
	growth = wave.get_node("RunGrowth")
	growth.set_physics_process(false)
	# 战斗与学习检查展示完整候选池，独立于正式界面的随机抽卡规则。
	growth.cards_per_draw = 100
	growth.choice_ui.open_duration = 0.0
	wave.skill_draft.initial_choice.open_duration = 0.0
	attack.audio_enabled = false
	check(skills.get_slots().is_empty() and skills.get_level(&"fan_slash") == 0 and skills.get_level(&"light_pierce") == 0, "All registered skills start unlearned")
	check(not fan.is_physics_processing() and not attack.is_physics_processing() and wave.get_attack_stats().is_empty(), "Unlearned weapons perform no attacks or buff work")
	check(wave.start_run() and wave.skill_draft.initial_choice.is_open, "Start requests the shared initial choice UI")
	check(wave.phase == WavePrototype.Phase.READY and wave._pending == 0 and not growth.active and not skills.has_learned_skill(), "No waves, experience or free skill before confirmation")
	check(wave.skill_draft.initial_choice._options.size() == 2 and wave.skill_draft.initial_choice.select_option(&"initial:light_pierce"), "Both actual skills are selectable at the same starting level")
	wave.skill_draft.initial_choice.cancel()
	check(not wave.skill_draft.initial_choice.is_open and get_first_node_in_group(&"gameplay_input_blockers") == null and skills.get_slots().is_empty(), "Cancel returns to empty preparation and releases input")
	check(wave.start_run(), "Initial choice can reopen after cancel")
	wave.skill_draft.initial_choice.select_option(&"initial:light_pierce")
	wave.skill_draft.initial_choice.confirm_selection()
	attack.set_physics_process(false)
	check(wave.phase == WavePrototype.Phase.BATTLE and growth.active and skills.get_level(&"light_pierce") == 1 and skills.get_level(&"fan_slash") == 0, "Only the selected weapon is learned before spawning")
	check(growth.state.level == 1 and growth.state.pending_choices == 0 and skills.get_slots().size() == 1, "Initial selection consumes no XP and adds only the owned HUD slot")
	check(not wave.start_run() and not wave.skill_draft.initial_choice.is_open, "Active battles cannot start a second selection")
	wave._spawn_queue.clear()
	var cards := skills.candidates()
	check(cards.any(func(card: GrowthChoiceOption): return card.id == &"skill:fan_slash:1") and cards.any(func(card: GrowthChoiceOption): return card.id == &"skill:light_pierce:2"), "Level-up pool offers new learning and existing upgrades together")
	check(not cards.any(func(card: GrowthChoiceOption): return card.id == &"P03"), "Pure projectile does not offer ineffective area buffs")
	growth._grant_experience(10)
	check(growth.choice_ui.is_open and wave.combat_frozen, "Real XP opens the existing growth flow")
	growth.choice_ui.select_option(&"skill:fan_slash:1")
	growth.choice_ui.confirm_selection()
	fan.set_physics_process(false)
	check(skills.get_slots().size() == 2 and fan.skill_level == 1 and not wave.combat_frozen, "Previously unlearned A01 uses the same learning flow")
	growth._grant_experience(15)
	growth.choice_ui.select_option(&"skill:light_pierce:2")
	growth.choice_ui.confirm_selection()
	attack.set_physics_process(false)
	check(skills.get_level(&"light_pierce") == 2 and attack.get_attack_stats().targets == 5, "A02 upgrades change actual penetration count")
	wave.skill_draft._choose(3, &"skill:light_pierce:2")
	check(skills.get_level(&"light_pierce") == 2, "Stale growth callbacks cannot duplicate upgrades")
	growth._grant_experience(20)
	growth.choice_ui.select_option(&"skill:light_pierce:3")
	growth.choice_ui.confirm_selection()
	growth._grant_experience(25)
	growth.choice_ui.select_option(&"skill:light_pierce:4")
	growth.choice_ui.confirm_selection()
	attack.set_physics_process(false)
	check(skills.get_level(&"light_pierce") == 4 and skills.get_level(&"fan_slash") == 1, "Actual XP supports every A02 upgrade while preserving A01")
	check(not skills.candidates().any(func(card: GrowthChoiceOption): return String(card.id).begins_with("skill:light_pierce:")), "Maxed A02 exits the real choice pool")

	clear_case()
	set_level(1)
	var line: Array[WaveEnemy] = []
	# 故意按远近相反的数组顺序加入；高速跨完整行程也必须按碰撞顺序命中。
	for x in [7.0, 5.0, 3.0, 1.0]: line.append(enemy_at(Vector3(x, 0.03, 0)))
	var side := enemy_at(Vector3(2, 0.03, 1.0))
	var raised := enemy_at(Vector3(2, 1.2, 0))
	var warning := enemy_at(Vector3(0.5, 0.03, 0))
	warning.spawn_delay = 3.0
	await settle()
	check(attack.fire(), "A02 starts on the nearest eligible target")
	var shot := attack._shots[0]
	var effect: LightPierceEffect = shot.effect
	check(shot.direction.is_equal_approx(Vector3.RIGHT) and effect._manual_flight, "Projectile locks a world direction and uses physical flight positions")
	advance(1.0)
	check(line[3].health == 988.0 and line[2].health == 988.0 and line[1].health == 988.0 and line[0].health == 1000.0, "Swept collision cannot tunnel and the nearest three bodies consume penetration in order")
	check(side.health == 1000.0 and raised.health == 1000.0 and warning.health == 1000.0, "Width, height and spawn protection reject invalid hits")
	check(attack._shots.is_empty() and effect.travelled < 5.0 and effect._impacts.size() == 3, "Projectile stops at its last valid hit with all impact animations")
	check(not attack.fire(), "Cooldown blocks extra shots")
	var mesh := effect._trail.mesh
	for frame in 3: effect._process(0.5)
	check(effect in attack._idle_effects and not effect.is_processing(), "Completed flight and impact work return to the reuse pool")
	attack._cooldown = 0.0
	check(attack.fire() and attack._shots[0].effect == effect and effect._trail.mesh == mesh, "Next attack reuses the same nodes, materials and ribbon mesh")
	advance(0.08)
	var first_damage := line[3].health
	advance(0.12)
	check(line[3].health == first_damage, "Same shot never damages an overlapping enemy twice")
	shot = attack._shots[0]
	var origin: Vector3 = shot.origin
	var direction: Vector3 = shot.direction
	var cooldown := attack._cooldown
	var position_on_path: Vector3 = shot.effect.head_tip_position()
	player.position += Vector3(0, 2.0, 2.0)
	player.blink_travelled.emit(Vector3.ZERO, player.position)
	camera.rotation_degrees.y += 90.0
	shot.effect._process(0.0)
	check(shot.origin == origin and shot.direction == direction and shot.effect.head_tip_position().is_equal_approx(position_on_path) and attack._cooldown == cooldown, "Blink, jumping and Q/E never drag a emitted projectile or reset attack progress")
	wave.set_combat_frozen(true)
	var travel: float = shot.effect.travelled
	var age: float = shot.effect._age
	attack._physics_process(1.0)
	advance(1.0)
	await settle(10)
	check(shot.effect.travelled == travel and shot.effect._age == age and attack._cooldown == cooldown and not attack.fire(), "Growth freeze preserves projectile, visual and cooldown clocks")
	wave.set_combat_frozen(false)
	advance(0.1)
	check(shot.effect.travelled > travel, "Frozen projectile resumes along the same path")

	clear_case()
	set_level(1)
	var close := enemy_at(Vector3(1, 0.03, 0))
	var behind := enemy_at(Vector3(5, 0.03, 0))
	await settle()
	check(attack.fire(), "Shot emits before a dynamic wall appears")
	var wall := wall_at(Vector3(2.5, 0.5, 0))
	await settle()
	advance(0.8)
	check(close.health == 988.0 and behind.health == 1000.0 and attack._shots.is_empty(), "Newly placed walls are checked live and stop damage behind them")
	check(attack._effects[0].travelled < 2.5, "Visible flight stops at the same wall boundary")
	attack._cooldown = 0.0
	close.spawn_delay = 1.0
	check(not attack.fire(), "Nearest target selection also respects walls")
	wall.free()
	await settle()
	close.spawn_delay = 0.0

	clear_case()
	set_level(1)
	var grazing := enemy_at(Vector3(4, 0.03, 0))
	var offset := enemy_at(Vector3(6, 0.03, 0.52))
	await settle()
	check(attack.fire(), "Narrow trajectory launches")
	advance(1.0)
	check(offset.health == 1000.0, "Level one misses an enemy outside its real collision width")
	attack.cancel_current()
	attack._cooldown = 0.0
	set_level(4)
	check(attack.fire(), "Widened trajectory launches")
	shot = attack._shots[0]
	check(is_equal_approx(shot.effect.trail_width, shot.effect.get_meta(&"trail_width") * 1.35), "Level four widens the visible light ribbons as well as collision")
	advance(1.0)
	check(offset.health < 1000.0 and grazing.health < 988.0, "Wider evolved projectile hits the previously missed enemy")
	check(is_equal_approx(attack.get_attack_stats(3).distance, 10.0) and is_equal_approx(attack.get_attack_stats(3).speed, 19.6), "Third level independently increases travel and speed")

	clear_case()
	set_level(1)
	var low := enemy_at(Vector3(1, 0.03, 0))
	var beyond := enemy_at(Vector3(5, 0.03, 0))
	await settle()
	check(attack.fire(), "Terrain boundary case launches")
	var cell := terrain.data.world_to_cell(Vector3(3.2, 0, 0))
	terrain.data.overlays[terrain.data._index(cell)] = TerrainData.OVERLAY_WATER
	advance(1.0)
	check(low.health == 988.0 and beyond.health == 1000.0 and attack._shots.is_empty(), "Flight stops at unbridged water instead of damaging across separated ground")
	terrain.data.overlays[terrain.data._index(cell)] = 0
	attack.cancel_current()
	attack._cooldown = 0.0
	check(attack.fire(), "Cliff boundary case launches")
	terrain.data.heights[terrain.data._index(cell)] = TerrainData.HEIGHT_OFFSET + 2
	advance(1.0)
	check(beyond.health == 1000.0 and attack._shots.is_empty(), "High disconnected terrain stops the same projectile")
	terrain.data.heights[terrain.data._index(cell)] = TerrainData.HEIGHT_OFFSET

	clear_case()
	set_level(1)
	var buffed := enemy_at(Vector3(4, 0.03, 0))
	await settle()
	check(attack.fire(), "Baseline shot emits before new modifiers")
	shot = attack._shots[0]
	wave.combat_modifiers.apply_buff(load("res://data/growth/damage.tres"))
	wave.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	wave.combat_modifiers.apply_buff(load("res://data/growth/range.tres"))
	set_level(2)
	advance(0.4)
	check(buffed.health == 988.0 and shot.stats.targets == 3, "A launched shot keeps its damage and penetration snapshot across upgrades")
	check(is_equal_approx(attack.get_attack_stats().damage, 17.28) and is_equal_approx(attack.get_attack_stats().interval, 1.15 / 1.12) and attack.get_attack_stats().distance == 8.0, "New shots apply shared damage and additive attack speed once without turning area bonus into range")
	attack.cancel_current()
	attack._cooldown = 0.0
	check(attack.fire(), "Next shot uses upgraded stats")
	advance(0.4)
	check(is_equal_approx(buffed.health, 970.72), "Actual next damage matches its growth card")
	attack.cancel_current()
	for index in 6:
		attack._cooldown = 0.0
		check(attack.fire(), "Concurrent shot is retained")
	check(attack._shots.size() == 6 and attack._effects.size() >= 6, "Concurrent required shots never silently lose damage or visuals to a fixed pool cap")
	wave._generation += 1
	advance(0.2)
	check(attack._shots.is_empty() and attack._effects.all(func(fx: LightPierceEffect): return not fx.is_processing()), "Invalidated wave generation clears all old projectiles and effects")
	wave._set_phase(WavePrototype.Phase.REST)
	check(skills.get_slots().size() == 2, "Wave rest retains all learned skills")
	wave._set_phase(WavePrototype.Phase.BATTLE)
	clear_case()
	set_level(1)
	var callback_first := enemy_at(Vector3(1, 0.03, 0))
	var callback_last := enemy_at(Vector3(3, 0.03, 0))
	await settle()
	var end_on_hit := func(_enemy: WaveEnemy, _damage: float): wave.retreat()
	attack.hit_landed.connect(end_on_hit)
	check(attack.fire(), "Reentrant end case emits a real shot")
	advance(1.0)
	check(callback_first.health < 1000.0 and callback_last.health == 1000.0 and wave.phase == WavePrototype.Phase.RESULT, "Ending the run from a hit callback prevents all remaining damage")
	check(attack._shots.is_empty() and attack._effects.all(func(fx: LightPierceEffect): return not fx.is_processing()), "Reentrant end leaves no running or pooled stale effects")
	attack.hit_landed.disconnect(end_on_hit)
	wave._finish("test", WavePrototype.Outcome.RETREAT)
	wave.retry()
	check(wave.phase == WavePrototype.Phase.READY and wave.skill_draft.initial_choice.is_open and skills.get_slots().is_empty() and not attack.is_physics_processing(), "Retry resets all skills and requests a new initial choice")
	wave.skill_draft._choose(10, &"skill:light_pierce:3")
	check(skills.get_slots().is_empty(), "Old pending callbacks cannot grant skills in the next preparation")
	wave.skill_draft.initial_choice.select_option(&"initial:fan_slash")
	wave.skill_draft.initial_choice.confirm_selection()
	fan.set_physics_process(false)
	check(fan.skill_level == 1 and attack.skill_level == 0 and wave.phase == WavePrototype.Phase.BATTLE and growth.state.level == 1, "A01 follows the same initial flow after retry")
	wave.retreat()
	wave.return_home()
	check(skills.get_slots().is_empty() and not wave.skill_draft.initial_choice.is_open and get_first_node_in_group(&"gameplay_input_blockers") == null, "Return releases choices and clears temporary skills")
	scene.free()
	await settle()
	await create_timer(0.3).timeout
	print("A02 and initial skill flow: %d checks, %d failures" % [checks, failures])
	quit.call_deferred(1 if failures else 0)
