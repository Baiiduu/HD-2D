class_name WavePrototype
extends Node3D

signal changed
signal phase_changed(phase: Phase)

enum Phase { READY, BATTLE, REST, RESULT }
const ENEMY_SCRIPT := preload("res://scripts/combat/wave_enemy.gd")
const UI_SCRIPT := preload("res://scripts/combat/wave_prototype_ui.gd")

@export_group("地图连接")
@export var player: Player
@export var terrain: Terrain
@export var loadout: LoadoutUI
@export var return_point: Marker3D
## 世界 XZ 范围；离开范围结束本轮。
@export var battle_area := Rect2(-12.0, 9.6, 24.0, 12.8)
@export_range(1.0, 5.0, 0.1) var interaction_radius := 2.5
@export var interact_key: Key = KEY_F
@export_group("波次灰盒")
@export_range(1, 12, 1) var total_waves := 3
@export_range(1, 30, 1) var first_wave_enemies := 5
@export_range(0, 10, 1) var enemies_per_wave := 2
@export_range(0.2, 5.0, 0.1, "suffix:s") var spawn_interval := 1.3
@export_range(0.2, 2.0, 0.1, "suffix:s") var spawn_warning := 0.8
@export_range(1.0, 100.0, 1.0) var enemy_health := 20.0
@export_range(0.3, 4.0, 0.1) var enemy_speed := 1.35
@export_range(0.0, 30.0, 1.0) var contact_damage := 8.0
## 多个敌人共享受击间隔，避免同帧叠加伤害；不赋予跳跃或瞬移额外无敌。
@export_range(0.2, 2.0, 0.05, "suffix:s") var hurt_interval := 0.7
@export var random_seed := 12102026
@export_group("通用基础攻击")
## 只用于验证清波；没有具体技能、强化、蓝量消耗或装备攻击加成。
@export_range(1.0, 50.0, 1.0) var attack_damage := 10.0
@export_range(0.2, 3.0, 0.05, "suffix:s") var attack_interval := 0.8
@export_range(2.0, 10.0, 0.1, "suffix:m") var attack_range := 6.4

var phase := Phase.READY
var wave := 0
var completed_waves := 0
var kills := 0
var result_reason := ""
var enemies: Array[WaveEnemy] = []
var _path := TerrainPath.new()
var _spawn_points := PackedVector3Array()
var _pending := 0
var _spawn_clock := 0.0
var _hurt_clock := 0.0
var _attack_clock := 0.0
var _random := RandomNumberGenerator.new()
var _ui: WavePrototypeUI
var _notice := ""
var _notice_clock := 0.0
var _path_ready := false

func _ready() -> void:
	_random.seed = random_seed
	_ui = UI_SCRIPT.new()
	_ui.controller = self
	add_child(_ui)
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.6
	mesh.height = 0.04
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.64, 0.7)
	marker.material_override = material
	marker.position.y = 0.03
	add_child(marker)
	if loadout:
		loadout.wave_session = self
		changed.connect(loadout._queue_refresh)
		loadout._queue_refresh()
	_initialize_path.call_deferred()

func _initialize_path() -> void:
	for frame in 3: await get_tree().physics_frame
	if not terrain or not player: return
	var exclude: Array[RID] = [player.get_rid()]
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy is CollisionObject3D: exclude.append(enemy.get_rid())
	_path.build(terrain, 0.32, exclude)
	_spawn_points.clear()
	for id in _path.graph.get_point_ids():
		var point := _path.graph.get_point_position(id)
		if battle_area.grow(-0.6).has_point(Vector2(point.x, point.z)):
			_spawn_points.append(point)
	_path_ready = not _spawn_points.is_empty()
	if not _path_ready: show_notice("战斗区域没有可用地形，请调整 Battle Area。")

func _exit_tree() -> void:
	remove_from_group(&"gameplay_input_blockers")
	if is_instance_valid(loadout) and loadout.wave_session == self:
		loadout.wave_session = null

func management_allowed() -> bool:
	return phase in [Phase.READY, Phase.REST]

func _set_phase(value: Phase) -> void:
	phase = value
	if phase == Phase.RESULT:
		add_to_group(&"gameplay_input_blockers")
	else:
		remove_from_group(&"gameplay_input_blockers")
	changed.emit()
	phase_changed.emit(phase)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_ESCAPE and phase == Phase.RESULT:
		return_home()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == interact_key and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null:
		if phase == Phase.READY and start_run():
			get_viewport().set_input_as_handled()
		elif phase == Phase.REST and start_next_wave():
			get_viewport().set_input_as_handled()

func can_start_run() -> bool:
	return _path_ready and phase == Phase.READY and _inside_area(player.global_position) and TerrainPath.horizontal_distance(global_position, player.global_position) <= interaction_radius and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null

func start_run() -> bool:
	if not can_start_run(): return false
	completed_waves = 0
	kills = 0
	wave = 0
	_attack_clock = 0.0
	player.heal(player.max_health)
	_begin_wave()
	return true

func _begin_wave() -> void:
	wave += 1
	_pending = first_wave_enemies + (wave - 1) * enemies_per_wave
	_spawn_clock = 0.3
	_hurt_clock = 0.5
	_set_phase(Phase.BATTLE)

func start_next_wave() -> bool:
	if phase != Phase.REST or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return false
	if not _inside_area(player.global_position):
		show_notice("回到南侧挑战区域再开始下一波，或撤退结算。")
		return false
	_begin_wave()
	return true

func _inside_area(point: Vector3) -> bool:
	return battle_area.grow(0.2).has_point(Vector2(point.x, point.z))

func _physics_process(delta: float) -> void:
	_notice_clock = maxf(_notice_clock - delta, 0.0)
	if phase != Phase.BATTLE: return
	if player.current_health <= 0.0:
		_finish("挑战失败 · 生命耗尽")
		return
	if not _inside_area(player.global_position):
		_finish("本轮结束 · 离开战斗区域")
		return
	_spawn_clock -= delta
	if _pending > 0 and _spawn_clock <= 0.0:
		if _spawn_enemy(): _pending -= 1
		_spawn_clock = spawn_interval
		if phase != Phase.BATTLE: return
	_attack_clock = maxf(_attack_clock - delta, 0.0)
	if _attack_clock <= 0.0 and _attack():
		_attack_clock = attack_interval
	_hurt_clock = maxf(_hurt_clock - delta, 0.0)
	if _hurt_clock <= 0.0:
		for enemy in enemies:
			if enemy.dead or enemy.spawn_delay > 0.0: continue
			if TerrainPath.horizontal_distance(enemy.global_position, player.global_position) < 0.85 and absf(enemy.global_position.y - player.global_position.y) < 0.8 and _line_clear(enemy.global_position + Vector3.UP * 0.45, player.global_position + Vector3.UP * 0.6):
				player.take_damage(contact_damage)
				_hurt_clock = hurt_interval
				show_notice("受击 -%d" % ceili(contact_damage))
				break
	if player.current_health <= 0.0:
		_finish("挑战失败 · 生命耗尽")
	elif _pending == 0 and enemies.is_empty():
		_clear_wave()

func _spawn_enemy() -> bool:
	var spawn := Vector3.ZERO
	var found := false
	var goal := _ground_target()
	for attempt in 40:
		var point := _spawn_points[_random.randi_range(0, _spawn_points.size() - 1)]
		if TerrainPath.horizontal_distance(point, player.global_position) < 5.0: continue
		if _path.route(point, goal).is_empty(): continue
		spawn = point
		found = true
		break
	if not found:
		_finish("挑战无法继续 · 调整战斗范围与生成距离")
		return false
	var enemy: WaveEnemy = ENEMY_SCRIPT.new()
	enemy.target = player
	enemy.path = _path
	enemy.health = enemy_health
	enemy.move_speed = enemy_speed
	enemy.spawn_delay = spawn_warning
	enemy.defeated.connect(_enemy_defeated)
	add_child(enemy)
	enemy.global_position = spawn + Vector3.UP * 0.03
	enemy.reset_physics_interpolation()
	enemies.append(enemy)
	return true

func _ground_target() -> Vector3:
	var point := player.global_position
	var cell := terrain.data.world_to_cell(terrain.to_local(point))
	point.y = terrain.global_position.y + terrain.data.get_level(cell) * terrain.data.layer_height
	return point

func _enemy_defeated(enemy: WaveEnemy) -> void:
	enemies.erase(enemy)
	kills += 1

func _line_clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _nearest_target() -> WaveEnemy:
	var nearest: WaveEnemy
	var distance := attack_range
	for enemy in enemies:
		var gap := TerrainPath.horizontal_distance(enemy.global_position, player.global_position)
		if enemy.dead or enemy.spawn_delay > 0.0 or gap > distance or absf(enemy.global_position.y - player.global_position.y) >= 1.6: continue
		if not _line_clear(player.global_position + Vector3.UP * 0.6, enemy.global_position + Vector3.UP * 0.45): continue
		nearest = enemy
		distance = gap
	return nearest

func _attack() -> bool:
	var target := _nearest_target()
	if not target: return false
	target.take_damage(attack_damage)
	return true

func _clear_wave() -> void:
	if phase != Phase.BATTLE: return
	completed_waves = wave
	if completed_waves >= total_waves:
		_finish("挑战完成")
	else:
		_set_phase(Phase.REST)

func retreat() -> void:
	if phase == Phase.REST: _finish("本轮结束 · 主动撤退")

func _finish(reason: String) -> void:
	if phase == Phase.RESULT: return
	_pending = 0
	for enemy in enemies:
		enemy.dead = true
		enemy.queue_free()
	enemies.clear()
	result_reason = reason
	_set_phase(Phase.RESULT)

func retry() -> void:
	if phase != Phase.RESULT: return
	player.global_position = global_position + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	_set_phase(Phase.READY)
	start_run()

func return_home() -> void:
	if phase != Phase.RESULT: return
	player.heal(player.max_health)
	player.global_position = return_point.global_position if return_point else global_position + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if player.movement_camera is FollowCamera: (player.movement_camera as FollowCamera).snap_to_target()
	_set_phase(Phase.READY)

func show_notice(words: String) -> void:
	_notice = words
	_notice_clock = 2.5

func status_text() -> String:
	match phase:
		Phase.BATTLE: return "第 %d / %d 波   ·   待出现 %d   ·   场上 %d   ·   击败 %d\n%s" % [wave, total_waves, _pending, enemies.size(), kills, _notice if _notice_clock > 0.0 else "基础自动攻击 · 走位生存 · 离开南侧区域结束本轮"]
		Phase.REST: return "第 %d 波已完成 · 安全休整，无倒计时\nTab 查看背包 · 准备好后主动继续" % wave
		Phase.READY: return "南侧灰盒挑战 · 到小圆台附近按 F 开始\n基础攻击与波次测试 · 技能和成长待后续讨论"
		_: return "波次循环灰盒 · 天气与世界继续运行"

func get_skill_slots() -> Array[String]:
	return ["", "", "", ""]
