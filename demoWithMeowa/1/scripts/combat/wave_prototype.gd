class_name WavePrototype
extends Node3D

signal changed
signal phase_changed(phase: Phase)
signal combat_frozen_changed(frozen: bool)
signal run_started
signal run_ended(reason: String)
signal enemy_defeated_at(position: Vector3, experience: int)
signal wave_clearing
signal enemy_spawned(enemy: WaveEnemy)
signal wave_cleared(number: int)

enum Phase { READY, BATTLE, REST, RESULT }
enum Outcome { NONE, VICTORY, DEFEAT, RETREAT, ERROR }
const UI_SCRIPT := preload("res://scripts/combat/wave_prototype_ui.gd")
const ATTACK_SURFACE_QUERY := preload("res://scripts/combat/attack_surface_query.gd")
var _attack_surface_query := ATTACK_SURFACE_QUERY.new()

@export_group("地图连接")
@export var player: Player
@export var terrain: Terrain
@export var loadout: LoadoutUI
@export var return_point: Marker3D
## 原有外观展示怪物在挑战期间隐藏，返回小院时恢复。
@export var preview_enemy: WaveEnemy
## 世界 XZ 范围；离开范围结束本轮。
@export var battle_area := Rect2(-12.0, 9.6, 24.0, 12.8):
	set(value):
		if battle_area == value: return
		battle_area = value
		_queue_path_rebuild()
@export_range(1.0, 5.0, 0.1) var interaction_radius := 2.5
@export var interact_key: Key = KEY_F
## 挑战界面隐藏时仍可重试。
@export var retry_key: Key = KEY_T
@export_group("灰盒界面")
## 显示挑战提示、休整按钮和结算窗口；不影响挑战逻辑或人物 HUD。
@export var show_ui := true:
	set(value):
		show_ui = value
		if is_instance_valid(_ui): _ui.visible = value
@export_group("波次配置")
@export var default_enemy: WaveEnemyDefinition
## 留空沿用下面的递增波次；配置后每波可混合不同怪物。
@export var waves: Array[WaveDefinition] = []
@export_range(1, 12, 1) var total_waves := 3
@export_range(1, 30, 1) var first_wave_enemies := 5
@export_range(0, 10, 1) var enemies_per_wave := 2
@export_range(0.2, 5.0, 0.1, "suffix:s") var spawn_interval := 1.3
@export_range(0.2, 2.0, 0.1, "suffix:s") var spawn_warning := 0.8
## 达到上限时延后生成，不丢弃怪物或提前清波。
@export_range(1, 200, 1) var max_active_enemies := 30
@export_range(1.0, 10.0, 0.1, "suffix:m") var spawn_safe_distance := 5.0
@export_group("无尽波次")
## 用已配置波次开场，之后沿用末波生成后续波次；清波仍按 F 主动继续。
@export var endless_mode := false
## 超过开场波次后，每波增加的怪物总数，按末波各组比例分配。
@export_range(0, 100, 1) var endless_enemies_per_wave := 8
## 后续每波的总数上限；不限制波数，同场上限仍由 Max Active Enemies 控制。
@export_range(1, 4096, 1) var endless_max_enemies := 160
## 后续每波减少的基础组内刷新间隔比例；总减幅最多 50%，保留组间休息。
@export_range(0.0, 0.1, 0.005) var endless_interval_reduction := 0.03
@export_range(0.05, 2.0, 0.01, "suffix:s") var endless_min_spawn_interval := 0.18
@export_group("怪物刷新")
## 配置外围 WaveSpawnZone；留空使用战斗范围的外圈。
@export var spawn_zone_root: Node3D:
	set(value):
		if spawn_zone_root == value: return
		spawn_zone_root = value
		_queue_path_rebuild()
## 入口和休整平台等禁止刷新区域，世界 XZ 坐标。
@export var spawn_excluded_areas: Array[Rect2] = []
@export_range(0.5, 4.0, 0.1, "suffix:m") var spawn_spacing := 1.2
## 没有配置刷新区域时，外圈的候选宽度，米。
@export_range(0.8, 8.0, 0.4, "suffix:m") var spawn_edge_band := 3.2:
	set(value): spawn_edge_band = value; _queue_path_rebuild()
## 每个物理帧最多成功生成几只；到期堆积也不会一帧全部出现。
@export_range(1, 8, 1) var max_spawns_per_tick := 2
## 每帧最多检查几个到期任务，避免被暂时堵住的任务阻塞其他批次。
@export_range(1, 16, 1) var max_spawn_checks_per_tick := 4
@export_range(0.1, 2.0, 0.1, "suffix:s") var spawn_retry_interval := 0.3
## 可用位置持续不足时明确中断；满员等待不计入该时间。
@export_range(2.0, 30.0, 1.0, "suffix:s") var spawn_block_timeout := 10.0
## 包含该波延迟分裂/召唤的总登记数量，防止无界追加。
@export_range(1, 4096, 1) var max_spawns_per_wave := 512
@export_group("战斗保护")
## 无路线或跌落持续达到此时间后结束挑战，可重试，避免残怪永久卡波。
@export_range(3.0, 30.0, 1.0, "suffix:s") var unreachable_timeout := 10.0
## 多个敌人共享受击间隔，避免同帧叠加伤害；不赋予跳跃或瞬移额外无敌。
@export_range(0.2, 2.0, 0.05, "suffix:s") var hurt_interval := 0.7
@export var random_seed := 12102026

var phase := Phase.READY
var wave := 0
var completed_waves := 0
var kills := 0
var result_reason := ""
var outcome := Outcome.NONE
var enemies: Array[WaveEnemy] = []
var _path := TerrainPath.new()
var _spawn_points := PackedVector3Array()
var _spawn_queue: Array[Dictionary] = []
var _run_waves: Array[WaveDefinition] = []
var _run_endless := false
var _endless_growth := 8
var _endless_cap := 160
var _endless_interval_reduction := 0.03
var _endless_min_interval := 0.18
var _definition_snapshots: Dictionary = {}
var _scene_validity: Dictionary = {}
var _spawn_zones: Array[WaveSpawnZone] = []
var _zone_points: Dictionary = {}
var _boundary_points := PackedVector3Array()
var _spawn_query := PhysicsShapeQueryParameters3D.new()
var _spawn_shape := SphereShape3D.new()
var _run_serial := 0
var _queue_sequence := 0
var _wave_queued_total := 0
var _spawned_this_wave := 0
var _spawned_run := 0
var _preparing_wave := false
var _starting_run := false
var _capacity_blocked := false
var _bound_data: TerrainData
var _definition_error := ""
var _pending: int:
	get: return _spawn_queue.size()
var _wave_clock := 0.0
var _hurt_clock := 0.0
var _random := RandomNumberGenerator.new()
var _ui: WavePrototypeUI
var _notice := ""
var _notice_clock := 0.0
var _path_ready := false
var _path_rebuild_pending := false
var _generation := 0
var _attack_root: Node3D
var _unreachable: Dictionary = {}
var _reachability_clock := 0.0
var _preview_state: Dictionary = {}
var combat_frozen := false
var combat_modifiers := RunCombatModifiers.new()
var _combat_nodes: Array[Node] = []
var _frozen_modes: Dictionary = {}
var _clearing_wave := false

func _ready() -> void:
	_random.seed = random_seed
	_ui = UI_SCRIPT.new()
	_ui.controller = self
	_ui.visible = show_ui
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
	_queue_path_rebuild()

func _initialize_path() -> void:
	var tree := get_tree()
	for frame in 3: await tree.physics_frame
	if not is_inside_tree() or not terrain or not terrain.data or not player: return
	var exclude: Array[RID] = [player.get_rid()]
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy is CollisionObject3D: exclude.append(enemy.get_rid())
	_path.build(terrain, 0.32, exclude, battle_area.grow(terrain.data.cell_size))
	_spawn_points.clear()
	for id in _path.graph.get_point_ids():
		var point := _path.graph.get_point_position(id)
		if battle_area.grow(-0.6).has_point(Vector2(point.x, point.z)):
			_spawn_points.append(point)
	_path_ready = not _spawn_points.is_empty()
	_path_rebuild_pending = false
	if _bound_data != terrain.data:
		if _bound_data and _bound_data.changed.is_connected(_queue_path_rebuild): _bound_data.changed.disconnect(_queue_path_rebuild)
		_bound_data = terrain.data
		_bound_data.changed.connect(_queue_path_rebuild)
	_rebuild_spawn_zones()
	if not _path_ready: show_notice("战斗区域没有可用地形，请调整 Battle Area。")

func _queue_path_rebuild() -> void:
	if not is_inside_tree() or _path_rebuild_pending: return
	_path_rebuild_pending = true
	_path_ready = false
	# 地形会重建碰撞 RID；共享导航也必须等待新碰撞体就绪。
	_initialize_path.call_deferred()

func _exit_tree() -> void:
	set_combat_frozen(false)
	_generation += 1
	_spawn_queue.clear()
	if _bound_data and _bound_data.changed.is_connected(_queue_path_rebuild): _bound_data.changed.disconnect(_queue_path_rebuild)
	remove_from_group(&"gameplay_input_blockers")
	if is_instance_valid(loadout) and loadout.wave_session == self:
		loadout.wave_session = null

func management_allowed() -> bool:
	return phase in [Phase.READY, Phase.REST]

func combat_active() -> bool:
	return not combat_frozen and phase == Phase.BATTLE and is_instance_valid(player) and player.current_health > 0.0 and _inside_area(player.global_position)

## 人物武器等独立组件登记到这里，升级时冻结各自计时而不暂停世界。
func register_combat_node(node: Node) -> void:
	if node not in _combat_nodes:
		_combat_nodes.append(node)
		node.tree_exiting.connect(unregister_combat_node.bind(node), CONNECT_ONE_SHOT)
	if combat_frozen: _freeze_node(node)

func unregister_combat_node(node: Node) -> void:
	_combat_nodes.erase(node)
	if _frozen_modes.has(node):
		node.process_mode = _frozen_modes[node]
		_frozen_modes.erase(node)

## 地面攻击共享当前物理帧的地形资格缓存；动态挡墙仍实时查询。
func get_attack_surface_query() -> RefCounted:
	_attack_surface_query.configure(terrain, [player.get_rid()])
	if not tree_exiting.is_connected(_attack_surface_query.dispose):
		tree_exiting.connect(_attack_surface_query.dispose)
	return _attack_surface_query

## 武器回传其真实数值；成长卡按它实际支持的属性显示收益。
func get_attack_stats(modifiers: RunCombatModifiers = null) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for node in _combat_nodes:
		if is_instance_valid(node) and node.has_method("get_combat_stats"):
			var stats: Dictionary = node.get_combat_stats(modifiers if modifiers else combat_modifiers)
			if not stats.is_empty(): values.append(stats)
	return values

func _freeze_node(node: Node) -> void:
	if not is_instance_valid(node) or _frozen_modes.has(node): return
	_frozen_modes[node] = node.process_mode
	node.process_mode = Node.PROCESS_MODE_DISABLED

func set_combat_frozen(value: bool) -> void:
	if combat_frozen == value: return
	combat_frozen = value
	if value:
		for enemy in enemies: _freeze_node(enemy)
		for node in _combat_nodes: _freeze_node(node)
		_freeze_node(_attack_root)
	else:
		for node in _frozen_modes:
			if is_instance_valid(node): node.process_mode = _frozen_modes[node]
		_frozen_modes.clear()
	combat_frozen_changed.emit(value)

func _set_phase(value: Phase) -> void:
	phase = value
	if phase == Phase.RESULT:
		add_to_group(&"gameplay_input_blockers")
	else:
		remove_from_group(&"gameplay_input_blockers")
	var generation := _generation
	changed.emit()
	if phase == value and generation == _generation: phase_changed.emit(value)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_ESCAPE and phase == Phase.RESULT:
		return_home()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == retry_key and phase == Phase.RESULT:
		retry()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and phase in [Phase.BATTLE, Phase.REST] and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null:
		retreat()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == interact_key and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null:
		if phase == Phase.READY and start_run():
			get_viewport().set_input_as_handled()
		elif phase == Phase.REST and start_next_wave():
			get_viewport().set_input_as_handled()

func can_start_run() -> bool:
	return _path_ready and not _starting_run and not combat_frozen and is_instance_valid(player) and phase == Phase.READY and _inside_area(player.global_position) and TerrainPath.horizontal_distance(global_position, player.global_position) <= interaction_radius and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null

func start_run() -> bool:
	if not can_start_run(): return false
	_starting_run = true
	completed_waves = 0
	kills = 0
	wave = 0
	_run_serial += 1
	_spawned_run = 0
	_queue_sequence = 0
	outcome = Outcome.NONE
	result_reason = ""
	_random.seed = random_seed
	if not _prepare_run():
		_starting_run = false
		return false
	player.heal(player.max_health)
	_hide_preview()
	var generation := _generation
	combat_modifiers.reset()
	run_started.emit()
	if phase != Phase.READY or generation != _generation:
		_starting_run = false
		return false
	_begin_wave()
	_starting_run = false
	return phase == Phase.BATTLE

func wave_count() -> int:
	# 0 表示没有有限总波数，调用方用 is_endless() 区分。
	if is_endless(): return 0
	if phase != Phase.READY and not _run_waves.is_empty(): return _run_waves.size()
	return waves.size() if not waves.is_empty() else total_waves

func is_endless() -> bool:
	return endless_mode if phase == Phase.READY else _run_endless

func wave_label(number: int) -> String:
	return "第 %d 波 · 无尽" % number if is_endless() else "第 %d / %d 波" % [number, wave_count()]

func _prepare_run() -> bool:
	_run_waves.clear()
	_run_endless = endless_mode
	_endless_growth = endless_enemies_per_wave
	_endless_cap = endless_max_enemies
	_endless_interval_reduction = endless_interval_reduction
	_endless_min_interval = endless_min_spawn_interval
	_definition_snapshots.clear()
	_scene_validity.clear()
	if max_active_enemies < 1 or max_spawns_per_wave < 1 or max_spawns_per_tick < 1 or max_spawn_checks_per_tick < 1 or not battle_area.has_area():
		_finish("挑战配置错误 · 检查战斗范围与刷新数量上限")
		return false
	for value in [spawn_safe_distance, spawn_spacing, spawn_retry_interval, spawn_block_timeout, unreachable_timeout]:
		if not is_finite(value) or value <= 0:
			_finish("挑战配置错误 · 生成距离、间距及等待时间须为正数")
			return false
	if not is_finite(spawn_warning) or spawn_warning < 0:
		_finish("挑战配置错误 · 检查出场预告时间")
		return false
	if spawn_zone_root and _available_zones(PackedStringArray()).is_empty():
		_finish("挑战配置错误 · 没有启用且可通行的刷新区域")
		return false
	var definitions: Array[WaveDefinition] = []
	if waves.is_empty():
		if (not _run_endless and total_waves < 1) or first_wave_enemies < 1 or enemies_per_wave < 0 or not is_finite(spawn_interval) or spawn_interval <= 0:
			_finish("挑战配置错误 · 检查递增波次数量与间隔")
			return false
		for number in (1 if _run_endless else total_waves):
			var entry := WaveSpawnEntry.new()
			entry.enemy = default_enemy
			entry.count = first_wave_enemies + number * enemies_per_wave
			entry.interval = spawn_interval
			var definition := WaveDefinition.new()
			definition.entries.append(entry)
			definitions.append(definition)
	else:
		definitions.assign(waves)
	for definition in definitions:
		if not definition or definition.entries.is_empty():
			_finish("挑战配置错误 · 每波至少需要一组怪物")
			return false
		var snapshot := WaveDefinition.new()
		snapshot.description = definition.description
		var total := 0
		for entry in definition.entries:
			if not entry or entry.count < 1 or not is_finite(entry.start_delay) or entry.start_delay < 0 or not is_finite(entry.interval) or entry.interval <= 0 or not is_finite(entry.warning_seconds) or entry.warning_seconds < -1:
				_finish("挑战配置错误 · 检查怪物组数量、时间与预告")
				return false
			total += entry.count
			if total > max_spawns_per_wave:
				_finish("挑战配置错误 · 本波数量超过生成预算")
				return false
			for id in entry.spawn_zone_ids:
				if not _spawn_zones.any(func(zone: WaveSpawnZone): return String(zone.get_zone_id()) == id):
					_finish("挑战配置错误 · 未找到刷新区域 " + id)
					return false
			var enemy := _snapshot_definition(entry.enemy)
			if not enemy:
				_finish("挑战配置错误 · " + _definition_error)
				return false
			var copy := entry.duplicate() as WaveSpawnEntry
			copy.enemy = enemy
			copy.spawn_zone_ids = entry.spawn_zone_ids.duplicate()
			snapshot.entries.append(copy)
		_run_waves.append(snapshot)
	if _run_endless:
		var last_total := _wave_total(_run_waves[-1])
		if _endless_growth < 0 or _endless_cap < last_total or _endless_cap > max_spawns_per_wave or not is_finite(_endless_interval_reduction) or _endless_interval_reduction < 0.0 or _endless_interval_reduction > 0.1 or not is_finite(_endless_min_interval) or _endless_min_interval <= 0.0:
			_finish("挑战配置错误 · 检查无尽每波增量、数量上限与最短刷新间隔")
			return false
	return true

func _wave_total(definition: WaveDefinition) -> int:
	var total := 0
	for entry in definition.entries: total += entry.count
	return total

func _endless_total(number: int) -> int:
	var initial := _wave_total(_run_waves[-1])
	# 先限制递增步数，极大波数也不会产生无界数量或整数溢出。
	var steps := mini(maxi(number - _run_waves.size(), 0), _endless_cap)
	return mini(initial + steps * _endless_growth, _endless_cap)

## 只保存开场模板；后续波次按需生成，内存不会随波数持续增长。
func _definition_for_wave(number: int) -> WaveDefinition:
	if number < 1 or _run_waves.is_empty(): return null
	if number <= _run_waves.size(): return _run_waves[number - 1]
	if not _run_endless: return null
	var template := _run_waves[-1]
	var base_total := _wave_total(template)
	var total := _endless_total(number)
	var interval_scale := 1.0 - minf(0.5, (number - _run_waves.size()) * _endless_interval_reduction)
	var definition := WaveDefinition.new()
	definition.description = "%d 只 · 末波分区与增援节奏" % total
	var cumulative := 0
	var allocated := 0
	for index in template.entries.size():
		var entry := template.entries[index]
		var copy := entry.duplicate() as WaveSpawnEntry
		cumulative += entry.count
		var next_allocation := roundi(float(cumulative) * total / base_total)
		copy.count = next_allocation - allocated
		allocated = next_allocation
		# 基础间隔已短于下限时保持原值，不把无尽增长变成减速。
		copy.interval = minf(entry.interval, maxf(_endless_min_interval, entry.interval * interval_scale))
		if index > 0:
			var previous := template.entries[index - 1]
			var gap := entry.start_delay - previous.start_delay - (previous.count - 1) * previous.interval
			if gap >= 0.0:
				var previous_copy := definition.entries[index - 1]
				copy.start_delay = previous_copy.start_delay + (previous_copy.count - 1) * previous_copy.interval + gap
		definition.entries.append(copy)
	return definition

func _snapshot_definition(definition: WaveEnemyDefinition) -> WaveEnemyDefinition:
	if definition and _definition_snapshots.has(definition): return _definition_snapshots[definition]
	if not definition or not definition.scene or not is_finite(definition.health) or definition.health <= 0 or not is_finite(definition.move_speed) or definition.move_speed < 0 or not is_finite(definition.attack_damage) or definition.attack_damage < 0 or not is_finite(definition.spawn_clearance) or definition.spawn_clearance <= 0:
		_definition_error = "怪物资源及生命、移动、伤害或碰撞留空参数无效"
		return null
	if not _scene_validity.has(definition.scene):
		var instance := definition.scene.instantiate()
		_scene_validity[definition.scene] = instance is WaveEnemy
		if instance: instance.free()
	if not _scene_validity[definition.scene]:
		_definition_error = "怪物根节点须继承 WaveEnemy"
		return null
	var snapshot := definition.duplicate() as WaveEnemyDefinition
	_definition_snapshots[definition] = snapshot
	_definition_snapshots[snapshot] = snapshot
	return snapshot

func _begin_wave() -> void:
	if phase not in [Phase.READY, Phase.REST] or _preparing_wave: return
	var definition := _definition_for_wave(wave + 1)
	if not definition: return
	_clearing_wave = false
	_preparing_wave = true
	wave += 1
	_generation += 1
	_wave_clock = 0.0
	_wave_queued_total = 0
	_spawned_this_wave = 0
	_capacity_blocked = false
	_unreachable.clear()
	_reachability_clock = 0.0
	_attack_root = Node3D.new()
	_attack_root.name = "EnemyAttacks"
	add_child(_attack_root)
	_hurt_clock = 0.5
	for entry in definition.entries:
		for index in entry.count:
			if not queue_spawn(entry.enemy, 1, entry.start_delay + index * entry.interval, Vector3.INF, entry.spawn_zone_ids, entry.warning_seconds):
				_preparing_wave = false
				return
	_preparing_wave = false
	# 队列全部登记后再通知，监听者不能把尚未登记的波次当作空波。
	_set_phase(Phase.BATTLE)

## 所有延迟出怪先登记在同一队列，分裂和召唤也阻止清波。
func queue_spawn(definition: WaveEnemyDefinition, count := 1, delay := 0.0, position := Vector3.INF, zone_ids := PackedStringArray(), warning := -1.0) -> bool:
	if phase != Phase.BATTLE and not _preparing_wave: return false
	var snapshot := _snapshot_definition(definition)
	if not snapshot or count <= 0 or _wave_queued_total + count > max_spawns_per_wave or not is_finite(delay) or delay < 0.0 or (position != Vector3.INF and not position.is_finite()) or not is_finite(warning) or warning < -1:
		_finish("挑战配置错误 · 检查怪物资源与待生成数量")
		return false
	for index in count:
		_queue_sequence += 1
		_spawn_queue.append({"id":_queue_sequence, "enemy": snapshot, "due": _wave_clock + delay, "position": position,
			"zones":zone_ids.duplicate(), "warning":warning, "next_attempt":0.0, "blocked_since":-1.0})
	_wave_queued_total += count
	_spawn_queue.sort_custom(func(a: Dictionary, b: Dictionary): return a.due < b.due or (a.due == b.due and a.id < b.id))
	return true

func _request_spawn(definition: WaveEnemyDefinition, count: int, delay: float, position: Vector3, generation: int) -> bool:
	if generation != _generation: return false
	return queue_spawn(definition, count, delay, position)

func start_next_wave() -> bool:
	if phase != Phase.REST or not _path_ready or combat_frozen or _preparing_wave or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return false
	if not _inside_area(player.global_position):
		show_notice("回到南侧挑战区域再开始下一波，或撤退结算。")
		return false
	_begin_wave()
	return phase == Phase.BATTLE

func _inside_area(point: Vector3) -> bool:
	return battle_area.grow(0.2).has_point(Vector2(point.x, point.z))

func _physics_process(delta: float) -> void:
	_notice_clock = maxf(_notice_clock - delta, 0.0)
	if phase != Phase.BATTLE or combat_frozen: return
	if player.current_health <= 0.0:
		_finish("挑战失败 · 生命耗尽", Outcome.DEFEAT)
		return
	if not _inside_area(player.global_position):
		_finish("本轮结束 · 离开战斗区域", Outcome.RETREAT)
		return
	if not _path_ready: return
	_wave_clock += delta
	_process_spawns()
	if phase != Phase.BATTLE or combat_frozen: return
	_hurt_clock = maxf(_hurt_clock - delta, 0.0)
	_check_reachability(delta)
	if phase != Phase.BATTLE: return
	if player.current_health <= 0.0:
		_finish("挑战失败 · 生命耗尽", Outcome.DEFEAT)
	elif _pending == 0 and enemies.is_empty():
		_clear_wave()

func _process_spawns() -> void:
	if combat_frozen or not _path_ready: return
	if enemies.size() >= max_active_enemies:
		if not _capacity_blocked:
			for job in _spawn_queue: job.blocked_since = -1.0
		_capacity_blocked = true
		return
	_capacity_blocked = false
	var generation := _generation
	var checked := 0
	var spawned := 0
	# 副本固定本帧任务，怪物 _ready 或通知追加队列也不破坏当前迭代。
	for job in _spawn_queue.duplicate():
		if job.due > _wave_clock: break
		if job.next_attempt > _wave_clock: continue
		if checked >= max_spawn_checks_per_tick or spawned >= max_spawns_per_tick or enemies.size() >= max_active_enemies: break
		checked += 1
		var success := _spawn_enemy(job.enemy, job.position, job.zones, job.warning)
		if generation != _generation or phase != Phase.BATTLE: return
		if success:
			_spawn_queue.erase(job)
			spawned += 1
			changed.emit()
			if generation != _generation or phase != Phase.BATTLE or combat_frozen: return
		else:
			if job.blocked_since < 0: job.blocked_since = _wave_clock
			job.next_attempt = _wave_clock + spawn_retry_interval
			show_notice("等待安全刷新位置 · 已登记怪物不会丢失")
			if _wave_clock - float(job.blocked_since) >= spawn_block_timeout:
				_finish("挑战中断 · 刷新位置持续不可用，请检查区域或重试")
				return

## 接触、弹丸、区域命中共用受击保护，命中判断留在怪物及其攻击对象。
func _damage_player(amount: float, generation: int) -> bool:
	if combat_frozen or generation != _generation or phase != Phase.BATTLE or _hurt_clock > 0.0 or player.current_health <= 0.0 or not is_finite(amount) or amount <= 0.0: return false
	player.take_damage(amount)
	_hurt_clock = hurt_interval
	show_notice("受击 -%d" % ceili(amount))
	return true

func _rebuild_spawn_zones() -> void:
	for zone in _spawn_zones:
		if is_instance_valid(zone) and zone.settings_changed.is_connected(_queue_path_rebuild): zone.settings_changed.disconnect(_queue_path_rebuild)
	_spawn_zones.clear()
	_zone_points.clear()
	_boundary_points.clear()
	for point in _spawn_points:
		var xz := Vector2(point.x, point.z)
		var distance := minf(minf(xz.x-battle_area.position.x, battle_area.end.x-xz.x), minf(xz.y-battle_area.position.y, battle_area.end.y-xz.y))
		if distance <= spawn_edge_band: _boundary_points.append(point)
	if not spawn_zone_root: return
	for marker in spawn_zone_root.find_children("*", "Marker3D", true, false):
		if not marker is WaveSpawnZone: continue
		var zone := marker as WaveSpawnZone
		_spawn_zones.append(zone)
		zone.settings_changed.connect(_queue_path_rebuild)
		var points := PackedVector3Array()
		for point in _spawn_points:
			if TerrainPath.horizontal_distance(point, zone.global_position) <= zone.radius: points.append(point)
		_zone_points[zone] = points

func _available_zones(ids: PackedStringArray) -> Array[WaveSpawnZone]:
	var available: Array[WaveSpawnZone] = []
	if not spawn_zone_root: return available
	for zone in _spawn_zones:
		if not is_instance_valid(zone) or not zone.enabled or zone.weight <= 0 or not is_finite(zone.weight): continue
		if not ids.is_empty() and not String(zone.get_zone_id()) in ids: continue
		if not _zone_points.get(zone, PackedVector3Array()).is_empty(): available.append(zone)
	return available

func _pick_zone(zones: Array[WaveSpawnZone]) -> WaveSpawnZone:
	var total := 0.0
	for zone in zones: total += zone.weight
	var value := _random.randf() * total
	for zone in zones:
		value -= zone.weight
		if value <= 0: return zone
	return zones.back()

func _valid_spawn(point: Vector3, definition: WaveEnemyDefinition, goal: Vector3) -> bool:
	var xz := Vector2(point.x, point.z)
	if not battle_area.grow(-maxf(0.6, definition.spawn_clearance)).has_point(xz): return false
	if TerrainPath.horizontal_distance(point, player.global_position) < maxf(spawn_safe_distance, definition.spawn_clearance + 0.3): return false
	for excluded in spawn_excluded_areas:
		if excluded.grow(definition.spawn_clearance).has_point(xz): return false
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and TerrainPath.horizontal_distance(point, enemy.global_position) < maxf(spawn_spacing, definition.spawn_clearance + enemy.spawn_clearance): return false
	_spawn_shape.radius = definition.spawn_clearance
	_spawn_query.shape = _spawn_shape
	_spawn_query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (_spawn_shape.radius + 0.08))
	_spawn_query.collision_mask = 1
	_spawn_query.exclude = [player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(_spawn_query, 1).is_empty(): return false
	return not _path.route(point, goal).is_empty()

func _find_spawn(definition: WaveEnemyDefinition, requested_position: Vector3, ids: PackedStringArray) -> Vector3:
	var zones := _available_zones(ids)
	if not requested_position.is_finite() and spawn_zone_root and zones.is_empty(): return Vector3.INF
	if not requested_position.is_finite() and not spawn_zone_root and _boundary_points.is_empty(): return Vector3.INF
	var goal := _ground_target()
	for attempt in 40:
		var point: Vector3
		if requested_position.is_finite():
			# 分裂和召唤留在指定位置附近；阻塞时不能跳到地图另一端。
			var offset := Vector3.ZERO if attempt == 0 else Vector3.RIGHT.rotated(Vector3.UP, _random.randf() * TAU) * _random.randf_range(0.4, 3.2)
			point = requested_position + offset
		elif spawn_zone_root:
			var zone := _pick_zone(zones)
			var points: PackedVector3Array = _zone_points[zone]
			point = points[_random.randi_range(0, points.size() - 1)]
		else:
			point = _boundary_points[_random.randi_range(0, _boundary_points.size() - 1)]
		if not terrain.data.has_cell(terrain.data.world_to_cell(terrain.to_local(point))): continue
		point = _path.ground_position(point)
		if _valid_spawn(point, definition, goal): return point
	return Vector3.INF

func _spawn_enemy(definition: WaveEnemyDefinition = null, requested_position := Vector3.INF, zone_ids := PackedStringArray(), warning := -1.0) -> bool:
	if phase != Phase.BATTLE or combat_frozen or not _path_ready: return false
	if not definition: definition = default_enemy
	definition = _snapshot_definition(definition)
	if not definition:
		_finish("挑战配置错误 · " + _definition_error)
		return false
	var spawn := _find_spawn(definition, requested_position, zone_ids)
	if not spawn.is_finite(): return false
	var generation := _generation
	var instance := definition.scene.instantiate()
	if not instance is WaveEnemy:
		instance.free()
		_finish("挑战配置错误 · 怪物根节点须继承 WaveEnemy")
		return false
	var enemy := instance as WaveEnemy
	enemy.configure_wave({
		"player": player, "terrain": terrain, "camera": player.movement_camera,
		"navigation": _path, "attack_root": _attack_root,
		"damage_player": _damage_player.bind(_generation),
		"request_spawn": _request_spawn.bind(_generation),
		"combat_active": combat_active,
	}, definition, spawn_warning if warning < 0 else warning)
	if phase != Phase.BATTLE or generation != _generation:
		enemy.free()
		return false
	enemy.defeated.connect(_enemy_defeated)
	enemy.tree_exiting.connect(_enemy_exiting.bind(enemy))
	enemy.position = to_local(spawn + Vector3.UP * 0.03)
	enemies.append(enemy)
	_spawned_this_wave += 1
	_spawned_run += 1
	add_child(enemy)
	if phase != Phase.BATTLE or generation != _generation: return false
	enemy.reset_physics_interpolation()
	enemy_spawned.emit(enemy)
	return true

func _ground_target() -> Vector3:
	return _path.ground_position(player.global_position)

func _enemy_defeated(enemy: WaveEnemy) -> void:
	if not enemies.has(enemy): return
	enemies.erase(enemy)
	_unreachable.erase(enemy.get_instance_id())
	kills += 1
	enemy_defeated_at.emit(enemy.global_position, enemy.experience_reward)
	changed.emit()

func _enemy_exiting(enemy: WaveEnemy) -> void:
	# 非死亡销毁也不能留下悬空引用；此类异常结束挑战，不伪造击杀或清波。
	if enemies.has(enemy):
		enemies.erase(enemy)
		if is_queued_for_deletion() or (owner and owner.is_queued_for_deletion()): return
		if phase == Phase.BATTLE: _finish("挑战中断 · 怪物意外移除，请重试")

func _check_reachability(delta: float) -> void:
	_reachability_clock += delta
	if _reachability_clock < 1.0: return
	var elapsed := _reachability_clock
	_reachability_clock = 0.0
	var goal := _ground_target()
	for enemy in enemies:
		if enemy.dead or enemy.spawn_delay > 0.0: continue
		var id := enemy.get_instance_id()
		var closest := _path.graph.get_point_position(_path.graph.get_closest_point(enemy.global_position))
		var on_map := TerrainPath.horizontal_distance(enemy.global_position, closest) <= terrain.data.cell_size
		var reachable := on_map and enemy.global_position.y >= _path.ground_position(enemy.global_position).y - 1.5 and not _path.route(enemy.global_position, goal).is_empty()
		_unreachable[id] = 0.0 if reachable else float(_unreachable.get(id, 0.0)) + elapsed
		if _unreachable[id] >= unreachable_timeout:
			_finish("挑战中断 · 残余怪物无法到达，请重试")
			return

func _clear_wave() -> void:
	if _preparing_wave or phase != Phase.BATTLE or _pending > 0 or not enemies.is_empty(): return
	if not _clearing_wave:
		_clearing_wave = true
		_cleanup_attacks()
		var generation := _generation
		wave_clearing.emit()
		if phase != Phase.BATTLE or generation != _generation: return
	if combat_frozen: return
	var cleared := wave
	var serial := _run_serial
	completed_waves = wave
	if not _run_endless and completed_waves >= wave_count():
		_finish("挑战完成", Outcome.VICTORY)
	else:
		_set_phase(Phase.REST)
	if serial == _run_serial: wave_cleared.emit(cleared)

func retreat() -> void:
	if phase in [Phase.BATTLE, Phase.REST]: _finish("本轮结束 · 主动撤退", Outcome.RETREAT)

func _finish(reason: String, result := Outcome.ERROR) -> void:
	if phase == Phase.RESULT: return
	combat_modifiers.reset()
	_preparing_wave = false
	_starting_run = false
	set_combat_frozen(false)
	_spawn_queue.clear()
	_cleanup_attacks()
	var remaining := enemies.duplicate()
	enemies.clear()
	for enemy in remaining: enemy.cancel()
	result_reason = reason
	outcome = result
	var generation := _generation
	_set_phase(Phase.RESULT)
	if phase == Phase.RESULT and generation == _generation: run_ended.emit(reason)

func _cleanup_attacks() -> void:
	_generation += 1
	if is_instance_valid(_attack_root):
		_attack_root.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(_attack_root)
		_attack_root.queue_free()
	_attack_root = null

func _hide_preview() -> void:
	if not is_instance_valid(preview_enemy) or not _preview_state.is_empty(): return
	_preview_state = {"visible": preview_enemy.visible, "mode": preview_enemy.process_mode, "layer": preview_enemy.collision_layer}
	preview_enemy.hide()
	preview_enemy.process_mode = Node.PROCESS_MODE_DISABLED
	preview_enemy.collision_layer = 0

func _restore_preview() -> void:
	if is_instance_valid(preview_enemy) and not _preview_state.is_empty():
		preview_enemy.visible = _preview_state.visible
		preview_enemy.process_mode = _preview_state.mode
		preview_enemy.collision_layer = _preview_state.layer
	_preview_state.clear()

func retry() -> void:
	if phase != Phase.RESULT: return
	player.global_position = _path.ground_position(global_position) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	_set_phase(Phase.READY)
	start_run()
	if player.movement_camera is FollowCamera: (player.movement_camera as FollowCamera).snap_to_target()

func return_home() -> void:
	if phase != Phase.RESULT: return
	player.heal(player.max_health)
	player.global_position = return_point.global_position if return_point else global_position + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if player.movement_camera is FollowCamera: (player.movement_camera as FollowCamera).snap_to_target()
	_restore_preview()
	_set_phase(Phase.READY)

func show_notice(words: String) -> void:
	_notice = words
	_notice_clock = 2.5

func next_wave_description() -> String:
	if phase != Phase.READY and wave < _run_waves.size(): return _run_waves[wave].description
	if phase != Phase.READY and _run_endless and not _run_waves.is_empty(): return "%d 只 · 末波分区与增援节奏" % _endless_total(wave + 1)
	if waves.is_empty() or wave >= waves.size() or not waves[wave]: return ""
	return waves[wave].description

## 后续 HUD、成长与结算读取该状态，不靠解析提示文字判断清波或成功。
func get_run_state() -> Dictionary:
	var warning_count := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.spawn_delay > 0: warning_count += 1
	return {"run_id":_run_serial, "phase":phase, "outcome":outcome, "wave":wave, "wave_count":wave_count(), "endless":is_endless(), "completed_waves":completed_waves,
		"pending":_pending, "alive":enemies.size(), "warning":warning_count, "queued_this_wave":_wave_queued_total,
		"spawned_this_wave":_spawned_this_wave, "spawned_total":_spawned_run, "kills":kills,
		"spawn_complete":_pending == 0, "clearing":phase == Phase.BATTLE and _clearing_wave, "combat_frozen":combat_frozen, "navigation_ready":_path_ready,
		"wave_elapsed":_wave_clock, "reason":result_reason}

func status_text() -> String:
	match phase:
		Phase.BATTLE: return "%s   ·   待出现 %d   ·   场上 %d   ·   击败 %d\n%s" % [wave_label(wave), _pending, enemies.size(), kills, _notice if _notice_clock > 0.0 else "基础自动攻击 · 走位生存 · 离开南侧区域结束本轮"]
		Phase.REST: return "%s已完成 · 安全休整，无倒计时\nTab 查看背包 · 准备好后主动继续%s" % [wave_label(wave), "\n下一波：" + next_wave_description() if not next_wave_description().is_empty() else ""]
		Phase.READY: return "南侧%s挑战 · 到小圆台附近按 F 开始\n自动攻击 · 经验升级 · 清波休整" % ("无尽" if is_endless() else "波次")
		_: return "波次循环灰盒 · 天气与世界继续运行"

func get_skill_slots() -> Array[String]:
	var result: Array[String] = []
	for slot in get_run_skill_slots(): result.append(slot.id)
	while result.size() < 4: result.append("")
	return result

func get_run_skill_slots() -> Array[Dictionary]:
	var skills := get_node_or_null("RunSkills") as RunSkills
	return skills.get_slots() if skills else []
