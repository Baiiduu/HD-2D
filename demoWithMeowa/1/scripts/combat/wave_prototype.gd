class_name WavePrototype
extends Node3D

const CROWD_BATCH_INDEX = preload("res://scripts/combat/crowd_batch_enemy_spatial_index.gd")
const SPAWN_QUEUE = preload("res://scripts/combat/wave_spawn_queue.gd")
const ENEMY_ROSTER = preload("res://scripts/combat/wave_enemy_roster.gd")
const ENEMY_UPDATE_BATCH = preload("res://scripts/combat/enemy_update_batch.gd")
const NATIVE_SWARM = preload("res://scripts/combat/native_swarm_loader.gd")
const SPAWN_SHADOWS = preload("res://scripts/combat/wave_spawn_shadows.gd")
var _spawn_state := SPAWN_QUEUE.new()
var _spawn_services := SPAWN_QUEUE.Services.new()
var _enemy_roster := ENEMY_ROSTER.new()

signal changed
signal phase_changed(phase: Phase)
signal combat_frozen_changed(frozen: bool)
signal run_started
signal run_ended(reason: String)
signal enemy_defeated_at(position: Vector3, experience: int)
signal enemy_defeated(enemy: WaveEnemy)
signal wave_clearing
signal enemy_spawned(enemy: WaveEnemy)
signal batch_spawned(count: int, point: Vector3)
signal wave_cleared(number: int)

enum Phase { READY, BATTLE, REST, RESULT }
enum Outcome { NONE, VICTORY, DEFEAT, RETREAT, ERROR }
const UI_SCRIPT := preload("res://scripts/combat/wave_prototype_ui.gd")
const ATTACK_SURFACE_QUERY := preload("res://scripts/combat/attack_surface_query.gd")
const HORDE_PLANNER := preload("res://scripts/combat/wave_horde_planner.gd")
const SCHEDULE_PLANNER := preload("res://scripts/combat/wave_schedule_planner.gd")
var _attack_surface_query := ATTACK_SURFACE_QUERY.new()
var run_skill_manager: RunSkillManager:
	get: return get_node_or_null("RunSkillManager") as RunSkillManager
var skill_draft: RunSkillDraft:
	get: return get_node_or_null("SkillDraft") as RunSkillDraft

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
## World 在战区内任意位置开战；其它地图默认保留入口距离要求。
@export var start_requires_proximity := true
@export var interact_key: Key = KEY_F
## 挑战界面隐藏时仍可重试。
@export var retry_key: Key = KEY_T
@export_group("灰盒界面")
## 显示挑战提示、休整按钮和结算窗口；不影响挑战逻辑或人物 HUD。
@export var show_ui := true:
	set(value):
		show_ui = value
		if is_instance_valid(_ui): _ui.visible = value
## 旧灰盒入口圆台；正式地图用像素按键提示替代，其它地图保留自身显示。
@export var show_start_marker := true
@export_group("波次配置")
@export var default_enemy: WaveEnemyDefinition
@export var enemy_catalog: WaveEnemyCatalog
## 数量档位为空时沿用现有参数；正式地图用 horde_128，更大档位须单独压测，下一轮开始时生效。
@export var population_rules: WavePopulationRules
## 地图独立的生成前剪影；空资源保留原有立即生成规则。
@export var spawn_shadow_settings: WaveSpawnShadowSettings
## One ordered driver for known wave actors; disable for the original callbacks.
@export var centralized_enemy_updates := false:
	set(value):
		centralized_enemy_updates = value
		_sync_enemy_updates()
## Optional CPU prototype. Missing binaries select the original script path.
@export var native_swarm_enabled := false:
	set(value):
		native_swarm_enabled = value
		_sync_native_swarm()
## 普通避让在当前物理步统一计算精确成对力；关闭恢复逐怪实时累计。
## 只冻结本步避让规划，真实墙体移动和战斗空间查询继续立即提交／读取。
@export var batch_crowd_enabled := false:
	set(value):
		batch_crowd_enabled = value
		_sync_batch_crowd_index()
## 达到同场数量后只降低普通决策频率；0 保留原频率。
@export_range(0, 4096, 1) var pursuit_throttle_threshold := 0:
	set(value):
		pursuit_throttle_threshold = maxi(0, value)
		_sync_batch_crowd_index()
## 普通追击用原生局部寻路，减少目标移动时的整图构建；关闭恢复共享追击树。
@export var native_chase_enabled := false:
	set(value):
		native_chase_enabled = value
		_sync_native_chase_paths()
## 所有怪物的普通平地追击；关闭恢复旧移动，冲锋、退步和预告不受影响。
@export var slime_ground_movement_enabled := false:
	set(value):
		slime_ground_movement_enabled = value
		for enemy in enemies:
			if enemy is SlimeEnemy: enemy.ground_movement_enabled = value
## 仅无尽模式应用；新挑战建立快照，当前局不受 Inspector 修改影响。
@export var health_growth_rules: WaveHealthGrowthRules
## 控制现有和后续生成的全部波次怪物；各 Sprite 自身关闭时仍保持关闭，不影响玩家。
@export var enemy_occlusion_outline_enabled := false:
	set(value):
		enemy_occlusion_outline_enabled = value
		for enemy in enemies:
			if is_instance_valid(enemy): enemy.set_occlusion_outline_allowed(value)
## 留空沿用下面的递增波次；配置后每波可混合不同怪物。
@export var waves: Array[WaveDefinition] = []
@export_range(1, 12, 1) var total_waves := 3
@export_range(1, 30, 1) var first_wave_enemies := 5
@export_range(0, 10, 1) var enemies_per_wave := 2
@export_range(0.2, 5.0, 0.1, "suffix:s") var spawn_interval := 1.3
## 旧资源兼容字段；出生预警已取消，不再用于生成。
@export_storage var spawn_warning := 0.0
## 达到上限时延后生成，不丢弃怪物或提前清波。
@export_range(1, 4096, 1) var max_active_enemies := 30
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
## 场景装配前的配置校验结果；空字符串表示通过，失败时不打开选卡或部分启动。
var configuration_error := ""
var enemies: Array[WaveEnemy]:
	get: return _enemy_roster.enemies
var _path := TerrainPath.new()
var _paths_by_radius: Dictionary = {}
var _spawn_points := PackedVector3Array()
var _spawn_queue: Array[Dictionary]:
	get: return _spawn_state.jobs
## 只保留当前到期怪潮的剩余容量；分帧创建期间不被后续散兵抢占。
var _reserved_batch: Dictionary:
	get: return _spawn_state.reserved_batch
var _run_waves: Array[WaveDefinition] = []
var _run_endless := false
var _endless_growth := 8
var _endless_cap := 160
var _endless_interval_reduction := 0.03
var _endless_min_interval := 0.18
var _definition_snapshots: Dictionary = {}
var _catalog_snapshots: Dictionary = {}
var _horde_pool: Array[WaveEnemyDefinition] = []
var _horde_usage: Dictionary = {}
var _run_population: WavePopulationRules
var _run_health_growth: WaveHealthGrowthRules
var _spatial_index: WaveEnemySpatialIndex:
	get: return _enemy_roster.spatial_index
	set(value): _enemy_roster.spatial_index = value
var _alive_by_definition: Dictionary:
	get: return _enemy_roster.by_definition
var _alive_by_role: PackedInt32Array:
	get: return _enemy_roster.by_role
var _population_cost: int:
	get: return _enemy_roster.cost
var _capacity_waiting: int:
	get: return _spawn_state.capacity_waiting
var _largest_spawn_clearance := 0.0
var _scene_validity: Dictionary = {}
var _spawn_zones: Array[WaveSpawnZone] = []
var _zone_points: Dictionary = {}
var _boundary_points := PackedVector3Array()
var _spawn_query := PhysicsShapeQueryParameters3D.new()
var _spawn_shape := SphereShape3D.new()
var _run_serial := 0
var _queue_sequence: int:
	get: return _spawn_state.sequence
	set(value): _spawn_state.sequence = value
var _wave_queued_total: int:
	get: return _spawn_state.queued_total
	set(value): _spawn_state.queued_total = value
var _spawned_this_wave := 0
var _spawned_run := 0
var _spawn_shadows: WaveSpawnShadows
var _preparing_wave := false
var _starting_run := false
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
var _retired_presentations: Array[Node3D] = []
var _enemy_update_batch: Node
var _enemy_update_revision := 0
var _native_kernel: RefCounted
var _unreachable: Dictionary = {}
var _reachability_clock := 0.0
var _reachability_queue: Array[WaveEnemy] = []
var _reachability_cursor := 0
var _reachability_budget := 0.0
var _reachability_last: Dictionary[int, float] = {}
var _preview_state: Dictionary = {}
var combat_frozen := false
var combat_modifiers := RunCombatModifiers.new()
@export var growth_rules: RunGrowthRules
var _survival := RunSurvival.new()
var _strike_speed_tier := -1
var _strike_flight_serial := -1

var _combat_nodes: Array[Node] = []
var _frozen_modes: Dictionary = {}
var _clearing_wave := false
var _wave_finish_deadline := 0
var _prepared_feedback: EnemyFeedbackPool

## 出手时读取剩余动能；飞行弹丸与千手后续刀使用同一份快照。
func attack_snapshot(flight_sword := false, remaining_speed := -1.0) -> CombatAttackSnapshot:
	var snapshot := CombatAttackSnapshot.new()
	var body := player.body_ricochet if is_instance_valid(player) else null
	var flying := (body != null and body.flying) or remaining_speed >= 0.0
	snapshot.remaining_speed = maxf(0.0, remaining_speed if remaining_speed >= 0.0 else body.flight_speed if flying else 0.0)
	snapshot.speed_damage_multiplier = combat_modifiers.speed_damage_multiplier(snapshot.remaining_speed, flying)
	if growth_rules and flying:
		if body and body.flight_serial != _strike_flight_serial:
			_strike_speed_tier = -1
			_strike_flight_serial = body.flight_serial
		_strike_speed_tier = growth_rules.speed_tier(snapshot.remaining_speed, _strike_speed_tier)
	else: _strike_speed_tier = -1
	snapshot.strikes = combat_modifiers.strike_count(_strike_speed_tier, flying and flight_sword)
	if growth_rules: snapshot.additional_strike_damage_ratio = growth_rules.additional_strike_damage_ratio
	return snapshot

func _growth_damage(event: CombatDamageEvent) -> void:
	if not growth_rules or not combat_active() or not is_instance_valid(player) or player.current_health <= 0.0: return
	_survival.rules = growth_rules
	player.heal(_survival.recovery(event, combat_modifiers, player.max_health, player.max_health - player.current_health))

func _init() -> void:
	_enemy_roster.spatial_index = CROWD_BATCH_INDEX.new()
	_spawn_services.alive_count = _spawn_alive_count
	_spawn_services.has_capacity = _spawn_has_capacity
	_spawn_services.spawn = _spawn_job
	_spawn_services.prepare = _prepare_spawn_warning
	_spawn_state.warning_started.connect(_spawn_warning_started)
	_spawn_state.warning_finished.connect(_spawn_warning_finished)
	_spawn_services.synchronize = _synchronize_spawn_index
	_spawn_services.current = _spawn_generation_current
	_spawn_services.frozen = _spawn_frozen
	_spawn_services.changed = _spawn_changed
	_spawn_services.blocked = show_notice.bind("等待安全刷新位置 · 已登记怪物不会丢失")
	_spawn_services.timed_out = _finish.bind("挑战中断 · 刷新位置持续不可用，请检查区域或重试")

func _ready() -> void:
	_sync_batch_crowd_index()
	_sync_native_swarm()
	_random.seed = random_seed
	_ui = UI_SCRIPT.new()
	_ui.controller = self
	_ui.visible = show_ui
	add_child(_ui)
	if show_start_marker:
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
	_prepare_spawn_shadows()
	_prepare_feedback_pool()

func _prepare_feedback_pool() -> void:
	if phase not in [Phase.READY, Phase.REST]: return
	if is_instance_valid(_prepared_feedback) or not is_instance_valid(player) or not player.action_visuals: return
	var visuals := player.action_visuals
	if visuals.feedback_prewarm_deaths <= 0 and visuals.feedback_prewarm_contacts <= 0: return
	var reserve := Node3D.new()
	reserve.name = "EnemyFeedbackReserve"
	add_child(reserve)
	_prepared_feedback = EnemyFeedbackPool.new()
	_prepared_feedback.terrain = terrain
	_prepared_feedback.name = "EnemyFeedbackPool"
	reserve.add_child(_prepared_feedback)
	_prepared_feedback.start_prewarm(visuals, visuals.feedback_prewarm_deaths, visuals.feedback_prewarm_contacts)

func feedback_prewarm_ready() -> bool:
	return not is_instance_valid(_prepared_feedback) or _prepared_feedback.prewarm_ready()

func _sync_batch_crowd_index() -> void:
	_spatial_index.pursuit_throttle_threshold = pursuit_throttle_threshold
	if _spatial_index is CROWD_BATCH_INDEX:
		(_spatial_index as CROWD_BATCH_INDEX).batch_enabled = batch_crowd_enabled

func _native_for(enemy: WaveEnemy) -> RefCounted:
	if not native_swarm_enabled or not _native_kernel or not enemy is SlimeEnemy: return null
	if enemy.get_script().resource_path not in ["res://scripts/enemies/slime.gd", "res://scripts/enemies/creature_enemy.gd", "res://scripts/enemies/leaf_charger.gd", "res://scripts/enemies/lantern_spitter.gd", "res://scripts/enemies/pot_brood.gd", "res://scripts/enemies/bell_frog.gd", "res://scripts/enemies/mini_slime.gd"]: return null
	return _native_kernel

func _sync_native_swarm() -> void:
	if not is_inside_tree(): return
	if native_swarm_enabled and not _native_kernel: _native_kernel = NATIVE_SWARM.create()
	if _spatial_index is CROWD_BATCH_INDEX:
		(_spatial_index as CROWD_BATCH_INDEX).native_kernel = _native_kernel if native_swarm_enabled else null
	for enemy in enemies:
		if is_instance_valid(enemy): enemy._native_swarm = _native_for(enemy)

func _sync_enemy_updates() -> void:
	if not is_inside_tree(): return
	if not centralized_enemy_updates:
		if is_instance_valid(_enemy_update_batch): _enemy_update_batch.release_all()
		return
	if not is_instance_valid(_attack_root): return
	_ensure_enemy_update_batch()
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree(): _enemy_update_batch.track(enemy)

func _ensure_enemy_update_batch() -> void:
	if is_instance_valid(_enemy_update_batch): return
	_enemy_update_batch = ENEMY_UPDATE_BATCH.new()
	_enemy_update_batch.name = "EnemyUpdates"
	_enemy_update_batch.session = self
	add_child(_enemy_update_batch)
	_enemy_update_batch.set_physics_process(false)

func _initialize_path() -> void:
	var tree := get_tree()
	for frame in 3: await tree.physics_frame
	if not is_inside_tree() or not terrain or not terrain.data or not player: return
	var exclude: Array[RID] = [player.get_rid()]
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy is CollisionObject3D: exclude.append(enemy.get_rid())
	_path.build(terrain, 0.32, exclude, battle_area.grow(terrain.data.cell_size))
	for radius: float in _paths_by_radius:
		_paths_by_radius[radius].build(terrain, radius, exclude, battle_area.grow(terrain.data.cell_size))
	_spawn_points.clear()
	for id in _path.graph.get_point_ids():
		var point := _path.graph.get_point_position(id)
		if battle_area.grow(-0.6).has_point(Vector2(point.x, point.z)):
			_spawn_points.append(point)
	_path_ready = not _spawn_points.is_empty()
	if terrain.obstacle_certificates_enabled and terrain.ground_collision_body():
		terrain.obstacle_field()
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
	_spawn_state.clear()
	if is_instance_valid(_spawn_shadows): _spawn_shadows.clear()
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
		var cleanup := unregister_combat_node.bind(node)
		if not node.tree_exiting.is_connected(cleanup): node.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
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
	var manager := run_skill_manager
	var values: Array[Dictionary] = []
	if manager: values = manager.get_attack_stats(modifiers if modifiers else combat_modifiers)
	for node in _combat_nodes:
		if manager and manager.is_registered(node): continue
		if is_instance_valid(node) and node.has_method("get_combat_stat_variants"):
			values.append_array(node.get_combat_stat_variants(modifiers if modifiers else combat_modifiers))
		elif is_instance_valid(node) and node.has_method("get_combat_stats"):
			var stats: Dictionary = node.get_combat_stats(modifiers if modifiers else combat_modifiers)
			if not stats.is_empty(): values.append(stats)
	return values

func _freeze_node(node: Node) -> void:
	if not is_instance_valid(node) or _frozen_modes.has(node): return
	_frozen_modes[node] = node.process_mode
	node.process_mode = Node.PROCESS_MODE_DISABLED

func set_combat_frozen(value: bool) -> void:
	if combat_frozen == value: return
	_enemy_update_revision += 1
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
	if value != Phase.BATTLE: _wave_finish_deadline = 0
	_enemy_update_revision += 1
	phase = value
	if phase in [Phase.READY, Phase.REST]: _prepare_feedback_pool()
	if phase == Phase.RESULT:
		add_to_group(&"gameplay_input_blockers")
	else:
		remove_from_group(&"gameplay_input_blockers")
	var generation := _generation
	changed.emit()
	if phase == value and generation == _generation: phase_changed.emit(value)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	# Maps with settings reserve Escape for that UI and its active child dialogs.
	if (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE) and get_parent().has_node("GameSettingsUI"): return
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
	if not _path_ready or _starting_run or combat_frozen or not is_instance_valid(player) or phase != Phase.READY: return false
	if not _inside_area(player.global_position) or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return false
	return not start_requires_proximity or TerrainPath.horizontal_distance(global_position, player.global_position) <= interaction_radius

func start_run() -> bool:
	if not can_start_run(): return false
	if not _configuration_valid(): return false
	if spawn_shadow_settings and not spawn_shadow_settings.validation_error().is_empty():
		_finish("挑战配置错误 · " + spawn_shadow_settings.validation_error())
		return false
	var skills := get_node_or_null("RunSkillManager") as RunSkillManager
	if not is_horde_simulation() and skill_draft and skill_draft.should_offer_initial_choice():
		return skill_draft.present_initial_choice()
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
	_survival.reset()
	_strike_speed_tier = -1
	combat_modifiers.damage_disabled = _run_population != null and _run_population.simulation_mode
	if combat_modifiers.damage_disabled and skills and skills.is_enabled() and not skills.apply_simulation_loadout(_run_population.simulation_skills):
		_finish("挑战配置错误 · 无法应用模拟技能配置")
		return false
	run_started.emit()
	if phase != Phase.READY or generation != _generation:
		_starting_run = false
		return false
	_begin_wave()
	_starting_run = false
	return phase == Phase.BATTLE

func wave_count() -> int:
	if is_horde_simulation(): return 1
	# 0 表示没有有限总波数，调用方用 is_endless() 区分。
	if is_endless(): return 0
	if phase != Phase.READY and not _run_waves.is_empty(): return _run_waves.size()
	return waves.size() if not waves.is_empty() else total_waves

func is_endless() -> bool:
	if is_horde_simulation(): return false
	return endless_mode if phase == Phase.READY else _run_endless

func is_horde_simulation() -> bool:
	var rules := population_rules if phase == Phase.READY else _run_population
	return rules != null and rules.simulation_mode

func wave_label(number: int) -> String:
	if is_horde_simulation():
		var rules := population_rules if phase == Phase.READY else _run_population
		return "巨量怪潮模拟 · %d / %d 只" % [enemies.size(), rules.simulation_enemy_count] if phase == Phase.BATTLE else "巨量怪潮模拟 · %d 只" % rules.simulation_enemy_count
	return "第 %d 波 · 无尽" % number if is_endless() else "第 %d / %d 波" % [number, wave_count()]

func _prepare_run() -> bool:
	if not _configuration_valid(): return false
	_run_waves.clear()
	_reserved_batch.clear()
	_run_endless = endless_mode
	_endless_growth = endless_enemies_per_wave
	_endless_cap = endless_max_enemies
	_endless_interval_reduction = endless_interval_reduction
	_endless_min_interval = endless_min_spawn_interval
	_definition_snapshots.clear()
	_catalog_snapshots.clear()
	_horde_pool.clear()
	_horde_usage.clear()
	for enemy in _enemy_roster.take_all(): enemy.cancel()
	_largest_spawn_clearance = 0.0
	_paths_by_radius.clear()
	_run_population = null
	_run_health_growth = null
	if health_growth_rules:
		var error := health_growth_rules.validation_error()
		if not error.is_empty():
			_finish("挑战配置错误 · " + error)
			return false
		_run_health_growth = health_growth_rules.duplicate() as WaveHealthGrowthRules
	if population_rules:
		var error := population_rules.validation_error()
		if not error.is_empty():
			_finish("挑战配置错误 · " + error)
			return false
		_run_population = population_rules.duplicate(true) as WavePopulationRules
		_endless_growth = _run_population.enemies_per_wave_increment
		_endless_cap = _run_population.max_wave_enemies
		_endless_interval_reduction = _run_population.interval_reduction_per_wave
		_endless_min_interval = _run_population.min_spawn_interval
		if _run_population.simulation_mode:
			_configure_simulation_population()
			var skills := get_node_or_null("RunSkillManager") as RunSkillManager
			var skill_error := skills.simulation_loadout_error(_run_population.simulation_skills) if skills else ("当前场景缺少技能组件" if not _run_population.simulation_skills.is_empty() else "")
			if not skill_error.is_empty():
				_finish("挑战配置错误 · " + skill_error)
				return false
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
	if enemy_catalog:
		var error := enemy_catalog.validation_error()
		if not error.is_empty():
			_finish("挑战配置错误 · " + error)
			return false
		for enemy in enemy_catalog.enemies:
			var snapshot := _snapshot_definition(enemy)
			if not snapshot:
				_finish("挑战配置错误 · " + _definition_error)
				return false
			_catalog_snapshots[enemy.enemy_id] = snapshot
			if snapshot.horde_weight > 0.0: _horde_pool.append(snapshot)
	var definitions: Array[WaveDefinition] = []
	if _run_population and _run_population.simulation_mode:
		var entry := WaveSpawnEntry.new()
		entry.mixed_horde = not _horde_pool.is_empty()
		entry.enemy = default_enemy if not entry.mixed_horde else null
		entry.count = _run_population.simulation_enemy_count
		entry.batch_size = entry.count
		var definition := WaveDefinition.new()
		definition.description = "%d 只 · 集中怪潮模拟 · 真实伤害飘字 · 双方不扣血" % entry.count
		definition.entries.append(entry)
		definitions.append(definition)
	elif waves.is_empty():
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
			if not entry or entry.count < 1 or entry.batch_size < 1 or not is_finite(entry.start_delay) or entry.start_delay < 0 or not is_finite(entry.interval) or entry.interval <= 0 or not is_finite(entry.warning_seconds) or entry.warning_seconds < -1:
				_finish("挑战配置错误 · 检查怪物组数量、时间与预告")
				return false
			total += entry.count
			if total > _spawn_budget_limit():
				_finish("挑战配置错误 · 本波数量超过生成预算")
				return false
			for id in entry.spawn_zone_ids:
				if not _spawn_zones.any(func(zone: WaveSpawnZone): return String(zone.get_zone_id()) == id):
					_finish("挑战配置错误 · 未找到刷新区域 " + id)
					return false
			var enemy: WaveEnemyDefinition
			var batch_count := mini(entry.batch_size, entry.count)
			var batch_limit := 0
			if entry.mixed_horde:
				if _horde_pool.is_empty():
					_finish("挑战配置错误 · 混合怪潮需要目录中至少一种怪潮权重大于 0 的怪物")
					return false
				batch_limit = _plan_horde(batch_count, _run_waves.size() + 1, {}).size()
			else:
				enemy = _resolve_entry_enemy(entry)
				if not enemy:
					_finish("挑战配置错误 · " + _definition_error)
					return false
				batch_limit = _batch_capacity_limit(enemy, _run_waves.size() + 1)
			if batch_count > batch_limit:
				_finish("挑战配置错误 · 怪潮每批数量超过可用容量")
				return false
			var copy := entry.duplicate() as WaveSpawnEntry
			copy.enemy = enemy
			copy.spawn_zone_ids = entry.spawn_zone_ids.duplicate()
			snapshot.entries.append(copy)
		_run_waves.append(snapshot)
	if _run_endless:
		var last_total := _wave_total(_run_waves[-1])
		if _endless_growth < 0 or _endless_cap < last_total or _endless_cap > _spawn_budget_limit() or not is_finite(_endless_interval_reduction) or _endless_interval_reduction < 0.0 or _endless_interval_reduction > 0.1 or not is_finite(_endless_min_interval) or _endless_min_interval <= 0.0:
			_finish("挑战配置错误 · 检查无尽每波增量、数量上限与最短刷新间隔")
			return false
	# 按通行尺寸预热共享导航，出怪帧不临时烘焙大型怪物路径。
	for definition: WaveEnemyDefinition in _definition_snapshots.values():
		_navigation_for(definition)
	_prepare_spawn_shadows()
	return true

func _configuration_valid() -> bool:
	if configuration_error.is_empty(): return true
	_finish("挑战配置错误 · " + configuration_error)
	return false

func _configure_simulation_population() -> void:
	_run_endless = false
	var count := _run_population.simulation_enemy_count
	_run_population.first_active_limit = count
	_run_population.max_active = count
	_run_population.active_growth_per_wave = 0
	_run_population.role_limits.fill(count)
	var largest_cost := default_enemy.population_cost if default_enemy else 1
	if enemy_catalog:
		for enemy in enemy_catalog.enemies:
			if enemy: largest_cost = maxi(largest_cost, enemy.population_cost)
	_run_population.max_population_cost = count * largest_cost
	_run_population.max_wave_enemies = count
	_run_population.max_queued_per_wave = count

func _sync_native_chase_paths() -> void:
	if _path: _path.native_chase_enabled = native_chase_enabled
	for path: TerrainPath in _paths_by_radius.values(): path.native_chase_enabled = native_chase_enabled

func _navigation_for(definition: WaveEnemyDefinition) -> TerrainPath:
	if is_equal_approx(definition.navigation_radius, 0.32): return _path
	if not _paths_by_radius.has(definition.navigation_radius):
		var path := TerrainPath.new()
		path.native_chase_enabled = native_chase_enabled
		var exclude: Array[RID] = [player.get_rid()]
		for enemy in enemies: exclude.append(enemy.get_rid())
		path.build(terrain, definition.navigation_radius, exclude, battle_area.grow(terrain.data.cell_size))
		_paths_by_radius[definition.navigation_radius] = path
	return _paths_by_radius[definition.navigation_radius]

func _wave_total(definition: WaveDefinition) -> int:
	return SCHEDULE_PLANNER.total(definition)

func _endless_total(number: int) -> int:
	return SCHEDULE_PLANNER.endless_total(_wave_total(_run_waves[-1]), _run_waves.size(), number, _endless_growth, _endless_cap)

## 只保存开场模板；后续波次按需生成，内存不会随波数持续增长。
func _definition_for_wave(number: int) -> WaveDefinition:
	if number < 1 or _run_waves.is_empty(): return null
	if number <= _run_waves.size(): return _run_waves[number - 1]
	if not _run_endless: return null
	var reduction_cap := _run_population.max_interval_reduction if _run_population else 0.5
	var interval_scale := 1.0 - minf(reduction_cap, (number - _run_waves.size()) * _endless_interval_reduction)
	return SCHEDULE_PLANNER.extend_wave(_run_waves[-1], _endless_total(number), interval_scale, _endless_min_interval,
		func(entry: WaveSpawnEntry) -> int: return _endless_batch_limit(entry, number))

func _endless_batch_limit(entry: WaveSpawnEntry, number: int) -> int:
	var active := _run_population.active_limit(number) if _run_population else max_active_enemies
	var limit := active if entry.mixed_horde else _batch_capacity_limit(entry.enemy, number)
	# 为场上怪群和特殊怪保留空间；混合批次继续使用真实分类与成本规划。
	limit = mini(limit, maxi(entry.batch_size, floori(active * 0.5)))
	return _plan_horde(limit, number, {}).size() if entry.mixed_horde else limit

func _snapshot_definition(definition: WaveEnemyDefinition) -> WaveEnemyDefinition:
	if definition and _definition_snapshots.has(definition): return _definition_snapshots[definition]
	if not definition:
		_definition_error = "怪物资源为空"
		return null
	_definition_error = definition.validation_error()
	if not _definition_error.is_empty(): return null
	if _run_population and (definition.population_cost > _run_population.max_population_cost or _run_population.role_limits[definition.role] < 1):
		_definition_error = "怪物容量成本或分类限制使其永远无法出场：" + definition.display_name
		return null
	if not _scene_validity.has(definition.scene):
		var instance := definition.scene.instantiate()
		_scene_validity[definition.scene] = instance is WaveEnemy
		if instance: instance.free()
	if not _scene_validity[definition.scene]:
		_definition_error = "怪物根节点须继承 WaveEnemy"
		return null
	var snapshot := definition.duplicate(true) as WaveEnemyDefinition
	# 场景和美术继续共享，专属配置子资源建立本局副本。
	snapshot.scene = definition.scene
	_largest_spawn_clearance = maxf(_largest_spawn_clearance, snapshot.spawn_clearance)
	_definition_snapshots[definition] = snapshot
	_definition_snapshots[snapshot] = snapshot
	return snapshot

func _resolve_entry_enemy(entry: WaveSpawnEntry) -> WaveEnemyDefinition:
	if entry.enemy_id == &"": return _snapshot_definition(entry.enemy)
	if not _catalog_snapshots.has(entry.enemy_id):
		_definition_error = "未登记怪物 Enemy Id：" + String(entry.enemy_id)
		return null
	var snapshot: WaveEnemyDefinition = _catalog_snapshots[entry.enemy_id]
	if entry.enemy and _snapshot_definition(entry.enemy) != snapshot:
		_definition_error = "Enemy 与 Enemy Id 指向不同怪物：" + String(entry.enemy_id)
		return null
	return snapshot

func get_active_enemy_limit() -> int:
	return _run_population.active_limit(wave) if _run_population else max_active_enemies

func get_enemy_health_multiplier(number := -1) -> float:
	if number < 0: number = wave
	return _run_health_growth.multiplier(number) if _run_endless and _run_health_growth else 1.0

func _spawn_budget_limit() -> int:
	return _run_population.max_queued_per_wave if _run_population else max_spawns_per_wave

func _batch_capacity_limit(definition: WaveEnemyDefinition, number: int) -> int:
	var limit := _run_population.active_limit(number) if _run_population else max_active_enemies
	if definition.max_alive > 0: limit = mini(limit, definition.max_alive)
	if _run_population:
		limit = mini(limit, _run_population.role_limits[definition.role])
		limit = mini(limit, floori(float(_run_population.max_population_cost) / definition.population_cost))
	return limit

func _has_enemy_capacity(definition: WaveEnemyDefinition, count := 1, batch: Dictionary = {}) -> bool:
	return _enemy_roster.can_fit(definition, count, get_active_enemy_limit(), _run_population, _reserved_batch, batch)

func _plan_horde(count: int, number: int, usage: Dictionary) -> Array[WaveEnemyDefinition]:
	var limit := _run_population.active_limit(number) if _run_population else max_active_enemies
	var roles := _run_population.role_limits if _run_population else PackedInt32Array([limit, limit, limit, limit])
	var cost := _run_population.max_population_cost if _run_population else limit * 128
	return HORDE_PLANNER.plan(_horde_pool, count, limit, cost, roles, usage)

func _make_batch(members: Array[WaveEnemyDefinition], id: int) -> Dictionary:
	return SPAWN_QUEUE.make_batch(members, id)

func _has_batch_capacity(batch: Dictionary) -> bool:
	return _enemy_roster.can_fit_batch(batch, get_active_enemy_limit(), _run_population)



## 出场、追击和攻击共用的局部候选查询；精确命中仍由招式判断。
func get_nearby_enemies(point: Vector3, radius: float) -> Array[WaveEnemy]:
	return _spatial_index.nearby(point, radius)

## Hot loops own and reuse result; do not retain/iterate it across a callback
## which can query into the same buffer. Ordering matches the allocating query.
func get_nearby_enemies_into(point: Vector3, radius: float,
		excluded: Dictionary[int, bool], result: Array[WaveEnemy]) -> void:
	_spatial_index.nearby_into(point, radius, excluded, result)

## Capture for delayed attacks; compare again after callbacks/resume. This
## identifies attack-root lifetime, not geometry/position cache validity.
func get_combat_generation() -> int:
	return _generation

func queue_spawn_by_id(id: StringName, count := 1, delay := 0.0, position := Vector3.INF) -> bool:
	if phase != Phase.BATTLE and not _preparing_wave: return false
	if not _catalog_snapshots.has(id):
		_finish("挑战配置错误 · 未登记召唤怪物 " + String(id))
		return false
	return queue_spawn(_catalog_snapshots[id], count, delay, position)

func _request_spawn_by_id(id: StringName, count: int, delay: float, position: Vector3, generation: int) -> bool:
	return queue_spawn_by_id(id, count, delay, position) if generation == _generation else false

func _begin_wave() -> void:
	if phase not in [Phase.READY, Phase.REST] or _preparing_wave: return
	var definition := _definition_for_wave(wave + 1)
	if not definition: return
	_clearing_wave = false
	_preparing_wave = true
	wave += 1
	_generation += 1
	_wave_clock = 0.0
	_spawn_state.clear()
	if is_instance_valid(_spawn_shadows): _spawn_shadows.clear()
	_wave_queued_total = 0
	_spawned_this_wave = 0
	_reset_reachability()
	if is_instance_valid(_prepared_feedback):
		# 整个预热根节点直接成为攻击根；不重入树，保留材质和附属节点生命周期。
		_attack_root = _prepared_feedback.get_parent() as Node3D
		_prepared_feedback.finish_prewarm()
		_prepared_feedback = null
	else:
		_attack_root = Node3D.new()
		add_child(_attack_root)
	_attack_root.name = "EnemyAttacks"
	# Keep the same object/ID layout for both A/B arms, after projectile handlers.
	_ensure_enemy_update_batch()
	_hurt_clock = 0.5
	for source_entry in definition.entries:
		var entry: WaveSpawnEntry = source_entry
		if _surround_spawns():
			entry = source_entry.duplicate() as WaveSpawnEntry
			entry.spawn_zone_ids = PackedStringArray()
		var queued := _queue_horde(entry) if entry.mixed_horde else queue_spawn(entry.enemy, entry.count, entry.start_delay, Vector3.INF, entry.spawn_zone_ids, entry.warning_seconds, entry.interval, entry.batch_size)
		if not queued:
			_preparing_wave = false
			return
	_sort_spawn_queue()
	_preparing_wave = false
	# 队列全部登记后再通知，监听者不能把尚未登记的波次当作空波。
	_set_phase(Phase.BATTLE)

## 所有延迟出怪先登记在同一队列，分裂和召唤也阻止清波。
func queue_spawn(definition: WaveEnemyDefinition, count := 1, delay := 0.0, position := Vector3.INF, zone_ids := PackedStringArray(), warning := -1.0, interval := 0.0, batch_size := 1) -> bool:
	if phase != Phase.BATTLE and not _preparing_wave: return false
	var snapshot := _snapshot_definition(definition)
	if not snapshot or count <= 0 or batch_size < 1 or _wave_queued_total + count > _spawn_budget_limit() or not is_finite(delay) or delay < 0.0 or not is_finite(interval) or interval < 0.0 or (position != Vector3.INF and not position.is_finite()) or not is_finite(warning) or warning < -1:
		_finish("挑战配置错误 · 检查怪物资源与待生成数量")
		return false
	if mini(batch_size, count) > _batch_capacity_limit(snapshot, wave):
		_finish("挑战配置错误 · 怪潮每批数量超过可用容量")
		return false
	var members: Array[WaveEnemyDefinition] = []
	members.resize(count)
	members.fill(snapshot)
	_queue_members(members, delay, position, zone_ids, warning, interval, batch_size)
	return true

func _queue_horde(entry: WaveSpawnEntry) -> bool:
	var members: Array[WaveEnemyDefinition] = []
	if _wave_queued_total + entry.count > _spawn_budget_limit():
		_finish("挑战配置错误 · 本波数量超过生成预算")
		return false
	while members.size() < entry.count:
		var count := mini(entry.batch_size, entry.count - members.size())
		var batch := _plan_horde(count, wave, _horde_usage)
		if batch.size() != count:
			_finish("挑战配置错误 · 混合怪潮超过同场、种类、分类或容量点预算")
			return false
		members.append_array(batch)
	_queue_members(members, entry.start_delay, Vector3.INF, entry.spawn_zone_ids, entry.warning_seconds, entry.interval, entry.batch_size)
	return true

func _queue_members(members: Array[WaveEnemyDefinition], delay: float, position: Vector3, zone_ids: PackedStringArray, warning: float, interval: float, batch_size: int) -> void:
	_spawn_state.enqueue(members, _wave_clock, delay, position, zone_ids, warning, interval, batch_size)
	if not _preparing_wave: _sort_spawn_queue()

func _sort_spawn_queue() -> void:
	_spawn_state.sort_jobs()

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
	# 最后一击已完成；收尾镜头不延长有效战斗时间或影响计时得分。
	if is_wave_finish_pending(): return
	_wave_clock += delta
	_survival.advance(delta)
	if is_instance_valid(_spawn_shadows): _spawn_shadows.advance(_wave_clock)
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
	_spawn_services.active_limit = get_active_enemy_limit()
	_spawn_services.check_budget = _run_population.checks_per_tick if _run_population else max_spawn_checks_per_tick
	_spawn_services.spawn_budget = _run_population.spawns_per_tick if _run_population else max_spawns_per_tick
	_spawn_services.retry_interval = spawn_retry_interval
	_spawn_services.block_timeout = spawn_block_timeout
	_spawn_services.warning_seconds = spawn_shadow_settings.warning_seconds if spawn_shadow_settings and spawn_shadow_settings.enabled else 0.0
	_spawn_state.process_due(_wave_clock, _generation, _spawn_services)

func _spawn_alive_count() -> int:
	return enemies.size()

func _spawn_has_capacity(job: Dictionary) -> bool:
	if _spawn_services.warning_seconds > 0.0 or not _spawn_state.prepared_jobs.is_empty():
		return _enemy_roster.can_fit_batch(_spawn_state.capacity_reservation(job), get_active_enemy_limit(), _run_population)
	return _has_batch_capacity(job.batch) if not job.batch.is_empty() else _has_enemy_capacity(job.enemy)

func _spawn_job(job: Dictionary) -> bool:
	if job.has("spawn_point"):
		var point: Vector3 = job.spawn_point
		if not terrain.data.has_cell(terrain.data.world_to_cell(terrain.to_local(point))): return false
		if not _path.ground_position(point).is_equal_approx(point): return false
		if not _valid_spawn(point, job.enemy, _ground_target(), job.position.is_finite(), int(job.id)): return false
		return _materialize_enemy(job.enemy, point, job.batch)
	return _spawn_enemy(job.enemy, job.position, job.zones, job.warning, job.batch)

func _prepare_spawn_warning(job: Dictionary) -> bool:
	var point := _find_spawn(job.enemy, job.position, job.zones, job.batch)
	if not point.is_finite(): return false
	job.spawn_point = point
	return true

func _prepare_spawn_shadows() -> void:
	if not spawn_shadow_settings or not spawn_shadow_settings.enabled: return
	if not is_instance_valid(_spawn_shadows):
		_spawn_shadows = SPAWN_SHADOWS.new()
		_spawn_shadows.name = "SpawnShadows"
		add_child(_spawn_shadows)
	var scenes: Array[PackedScene] = []
	if default_enemy: scenes.append(default_enemy.scene)
	if enemy_catalog:
		for definition in enemy_catalog.enemies: scenes.append(definition.scene)
	for definition: WaveEnemyDefinition in _definition_snapshots.values(): scenes.append(definition.scene)
	_spawn_shadows.configure(spawn_shadow_settings, scenes, battle_area)

func _spawn_warning_started(job: Dictionary, seconds: float) -> void:
	if not is_instance_valid(_spawn_shadows) or not _spawn_shadows.atlas.records.has(job.enemy.scene): _prepare_spawn_shadows()
	if is_instance_valid(_spawn_shadows): _spawn_shadows.begin(int(job.id), job.enemy.scene, job.spawn_point, seconds, _wave_clock)

func _spawn_warning_finished(id: int, spawned: bool) -> void:
	if is_instance_valid(_spawn_shadows): _spawn_shadows.end(id, spawned)

func _synchronize_spawn_index() -> void:
	_spatial_index.synchronize(enemies)

func _spawn_generation_current(generation: int) -> bool:
	return generation == _generation and phase == Phase.BATTLE

func _spawn_frozen() -> bool:
	return combat_frozen

func _spawn_changed() -> void:
	changed.emit()

## 接触、弹丸、区域命中共用受击保护，命中判断留在怪物及其攻击对象。
func _can_damage_player(amount: float, generation: int) -> bool:
	return not combat_frozen and generation == _generation and phase == Phase.BATTLE and _hurt_clock <= 0.0 and player.current_health > 0.0 and is_finite(amount) and amount > 0.0

func _damage_player(amount: float, generation: int) -> bool:
	if not _can_damage_player(amount, generation): return false
	_enemy_update_revision += 1
	if is_horde_simulation():
		# 保留怪物命中资格、真实碰撞与共享受击间隔，只跳过最终扣血。
		_hurt_clock = hurt_interval
		return true
	_survival.rules = growth_rules
	amount = _survival.incoming_damage(amount, player.body_ricochet != null and player.body_ricochet.flying and player.body_ricochet.orbiting)
	player.take_damage(amount)
	_hurt_clock = hurt_interval
	show_notice("受击 -%d" % ceili(amount))
	return true

func _rebuild_spawn_zones() -> void:
	for job in _spawn_queue:
		job.batch.erase("points")
		job.batch.erase("zone")
		job.batch.erase("front_points")
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

func _valid_spawn(point: Vector3, definition: WaveEnemyDefinition, goal: Vector3, local_spawn := false, reservation_id := -1) -> bool:
	var xz := Vector2(point.x, point.z)
	if not battle_area.grow(-maxf(0.6, definition.spawn_clearance)).has_point(xz): return false
	# 分裂／召唤来自已进入战区的母体，保留近身留空；普通外围刷新使用完整安全距离。
	var safe_distance := definition.spawn_clearance + 0.3 if local_spawn else maxf(spawn_safe_distance, definition.spawn_clearance + 0.3)
	if TerrainPath.horizontal_distance(point, player.global_position) < safe_distance: return false
	# 入口禁刷区防止外围增援直接刷入休整点，不阻止走进该区的母体原地分裂。
	# 否则局部搜索圆可能完全落在禁刷矩形里，所有重试都不可能成功。
	if not local_spawn:
		for excluded in spawn_excluded_areas:
			if excluded.grow(definition.spawn_clearance).has_point(xz): return false
	var spacing := _run_population.spawn_spacing if _run_population else spawn_spacing
	for job: Dictionary in _spawn_state.prepared_jobs.values():
		if int(job.id) == reservation_id: continue
		if TerrainPath.horizontal_distance(point, job.spawn_point) < maxf(spacing, definition.spawn_clearance + job.enemy.spawn_clearance): return false
	for enemy in _spatial_index.nearby(point, maxf(spacing, definition.spawn_clearance + _largest_spawn_clearance)):
		if TerrainPath.horizontal_distance(point, enemy.global_position) < maxf(spacing, definition.spawn_clearance + enemy.spawn_clearance): return false
	_spawn_shape.radius = definition.spawn_clearance
	_spawn_query.shape = _spawn_shape
	_spawn_query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (_spawn_shape.radius + 0.08))
	_spawn_query.collision_mask = 1
	_spawn_query.exclude = [player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(_spawn_query, 1).is_empty(): return false
	return _navigation_for(definition).shared_reachable(point, goal)

func _batch_spawn_points(batch: Dictionary, zones: Array[WaveSpawnZone]) -> PackedVector3Array:
	if batch.has("points"): return batch.points
	var center: Vector3
	var radius := spawn_edge_band
	if not zones.is_empty():
		var zone := _pick_zone(zones)
		batch.zone = zone.get_zone_id()
		center = zone.global_position
		radius = zone.radius
	else:
		center = _boundary_points[_random.randi_range(0, _boundary_points.size() - 1)]
	var spacing := _run_population.spawn_spacing if _run_population else spawn_spacing
	radius = maxf(radius, sqrt(float(batch.size)) * maxf(spacing, float(batch.clearance) * 2.0) * 1.25)
	var points := PackedVector3Array()
	for point in _spawn_points:
		if TerrainPath.horizontal_distance(point, center) <= radius: points.append(point)
	batch.points = points
	return points

func _surround_spawns() -> bool:
	return _run_endless and _run_population != null and _run_population.surround_start_wave > 0 and wave >= _run_population.surround_start_wave

## 仅在一批真正尝试进场时建立扇区；世界方位随人物位置确定，不读取相机朝向。
func _surround_spawn_points(batch: Dictionary) -> Array:
	if batch.has("front_points"): return batch.front_points
	var count := mini(int(batch.size), mini(_run_population.surround_max_fronts, maxi(2, floori(float(get_active_enemy_limit()) / 16.0))))
	var sectors: Array[PackedVector3Array] = []
	for index in count: sectors.append(PackedVector3Array())
	var origin := player.global_position
	var phase_angle := _random.randf() * TAU
	var safe := maxf(spawn_safe_distance, float(batch.clearance) + 0.3)
	var inset := battle_area.grow(-maxf(0.6, float(batch.clearance)))
	for point in _boundary_points:
		var xz := Vector2(point.x, point.z)
		if not inset.has_point(xz): continue
		var excluded := false
		for area in spawn_excluded_areas:
			if area.grow(float(batch.clearance)).has_point(xz):
				excluded = true
				break
		if excluded: continue
		var offset := Vector2(point.x - origin.x, point.z - origin.z)
		if offset.length_squared() < safe * safe: continue
		var sector := mini(count - 1, floori(fposmod(offset.angle() - phase_angle, TAU) * count / TAU))
		sectors[sector].append(point)
	var spacing := maxf(_run_population.spawn_spacing, float(batch.clearance) * 2.0)
	var radius := maxf(spawn_edge_band, sqrt(ceilf(float(batch.size) / count)) * spacing * 1.25)
	var fronts: Array[PackedVector3Array] = []
	for index in count:
		var points := sectors[index]
		if points.is_empty(): continue
		var direction := Vector2.from_angle(phase_angle + (index + 0.5) * TAU / count)
		var center := points[0]
		var best := -INF
		for point in points:
			var offset := Vector2(point.x - origin.x, point.z - origin.z)
			var score := offset.normalized().dot(direction)
			if score > best:
				best = score
				center = point
		var compact := PackedVector3Array()
		for point in points:
			if TerrainPath.horizontal_distance(point, center) <= radius: compact.append(point)
		fronts.append(compact)
	if not fronts.is_empty(): batch.front_points = fronts
	return fronts

func _find_spawn(definition: WaveEnemyDefinition, requested_position: Vector3, ids: PackedStringArray, batch: Dictionary = {}) -> Vector3:
	var surround := _surround_spawns() and not requested_position.is_finite() and ids.is_empty()
	var zones := _available_zones(ids)
	if surround and _boundary_points.is_empty(): return Vector3.INF
	if not surround and not requested_position.is_finite() and spawn_zone_root and zones.is_empty(): return Vector3.INF
	if not requested_position.is_finite() and not spawn_zone_root and _boundary_points.is_empty(): return Vector3.INF
	var goal := _ground_target()
	var batch_points := PackedVector3Array()
	var fronts: Array = []
	if surround and not batch.is_empty():
		fronts = _surround_spawn_points(batch)
		if fronts.is_empty(): return Vector3.INF
	elif not batch.is_empty() and not requested_position.is_finite():
		batch_points = _batch_spawn_points(batch, zones)
		if batch_points.is_empty(): return Vector3.INF
	for attempt in (_run_population.position_attempts if _run_population else 40):
		var point: Vector3
		var front := -1
		if requested_position.is_finite():
			# 分裂和召唤留在指定位置附近；阻塞时不能跳到地图另一端。
			var offset := Vector3.ZERO if attempt == 0 else Vector3.RIGHT.rotated(Vector3.UP, _random.randf() * TAU) * _random.randf_range(0.4, 3.2)
			point = requested_position + offset
		elif not fronts.is_empty():
			front = (int(batch.get("next_front", 0)) + attempt) % fronts.size()
			var points: PackedVector3Array = fronts[front]
			point = points[_random.randi_range(0, points.size() - 1)]
		elif surround:
			point = _boundary_points[_random.randi_range(0, _boundary_points.size() - 1)]
		elif not batch_points.is_empty():
			point = batch_points[_random.randi_range(0, batch_points.size() - 1)]
		elif spawn_zone_root:
			var zone := _pick_zone(zones)
			var points: PackedVector3Array = _zone_points[zone]
			point = points[_random.randi_range(0, points.size() - 1)]
		else:
			point = _boundary_points[_random.randi_range(0, _boundary_points.size() - 1)]
		if not terrain.data.has_cell(terrain.data.world_to_cell(terrain.to_local(point))): continue
		point = _path.ground_position(point)
		if _valid_spawn(point, definition, goal, requested_position.is_finite()):
			if front >= 0: batch.next_front = (front + 1) % fronts.size()
			return point
	# 人物移动或新墙阻塞旧扇区时，下次重试重新选合法外围；保留整批容量与已出生成员。
	if surround: batch.erase("front_points")
	return Vector3.INF

func _spawn_enemy(definition: WaveEnemyDefinition = null, requested_position := Vector3.INF, zone_ids := PackedStringArray(), warning := -1.0, batch: Dictionary = {}) -> bool:
	if phase != Phase.BATTLE or combat_frozen or not _path_ready: return false
	if not definition: definition = default_enemy
	definition = _snapshot_definition(definition)
	if not definition:
		_finish("挑战配置错误 · " + _definition_error)
		return false
	if not _has_enemy_capacity(definition, 1, batch): return false
	var spawn := _find_spawn(definition, requested_position, zone_ids, batch)
	if not spawn.is_finite(): return false
	return _materialize_enemy(definition, spawn, batch)

func _materialize_enemy(definition: WaveEnemyDefinition, spawn: Vector3, batch: Dictionary) -> bool:
	var generation := _generation
	var instance := definition.scene.instantiate()
	if not instance is WaveEnemy:
		instance.free()
		_finish("挑战配置错误 · 怪物根节点须继承 WaveEnemy")
		return false
	var enemy := instance as WaveEnemy
	enemy.configure_wave({
		"native_swarm": _native_for(enemy),
		"health_loss_disabled":combat_modifiers.damage_disabled,
		"enemy_occlusion_outline_enabled":enemy_occlusion_outline_enabled,
		"wave":wave, "health_multiplier":get_enemy_health_multiplier() if definition.health_growth_enabled else 1.0,
		"player": player, "terrain": terrain, "camera": player.movement_camera,
		"navigation": _navigation_for(definition), "attack_root": _attack_root,
		"damage_player": _damage_player.bind(_generation),
		"can_damage_player": _can_damage_player.bind(_generation),
		"request_spawn": _request_spawn.bind(_generation),
		"request_spawn_by_id": _request_spawn_by_id.bind(_generation),
		"spatial_index": _spatial_index,
		"combat_active": combat_active,
	}, definition, 0.0)
	if phase != Phase.BATTLE or generation != _generation:
		enemy.free()
		return false
	enemy.defeated.connect(_enemy_defeated)
	enemy.damaged.connect(_growth_damage)
	enemy.tree_exiting.connect(_enemy_exiting.bind(enemy))
	enemy.position = to_local(spawn + Vector3.UP * 0.03)
	if enemy is SlimeEnemy: enemy.ground_movement_enabled = slime_ground_movement_enabled
	_enemy_roster.register(enemy)
	_reachability_last[enemy.get_instance_id()] = _reachability_clock
	_spawned_this_wave += 1
	_spawned_run += 1
	_spawn_state.complete_member(batch, definition)
	add_child(enemy)
	if phase != Phase.BATTLE or generation != _generation: return false
	if centralized_enemy_updates: _enemy_update_batch.track(enemy)
	enemy.reset_physics_interpolation()
	enemy_spawned.emit(enemy)
	if not batch.is_empty() and batch.remaining == batch.size - 1 and phase == Phase.BATTLE and generation == _generation:
		batch_spawned.emit(int(batch.size), enemy.global_position)
	return true

func _ground_target() -> Vector3:
	return _path.ground_position(player.global_position)

func _enemy_defeated(enemy: WaveEnemy) -> void:
	if not _enemy_roster.remove(enemy): return
	_unreachable.erase(enemy.get_instance_id())
	_reachability_last.erase(enemy.get_instance_id())
	kills += 1
	enemy_defeated.emit(enemy)
	enemy_defeated_at.emit(enemy.global_position, enemy.experience_reward)
	changed.emit()

func _enemy_exiting(enemy: WaveEnemy) -> void:
	# 非死亡销毁也不能留下悬空引用；此类异常结束挑战，不伪造击杀或清波。
	if _enemy_roster.remove(enemy):
		_unreachable.erase(enemy.get_instance_id())
		_reachability_last.erase(enemy.get_instance_id())
		if is_queued_for_deletion() or (owner and owner.is_queued_for_deletion()): return
		if phase == Phase.BATTLE: _finish("挑战中断 · 怪物意外移除，请重试")

func _reset_reachability() -> void:
	_unreachable.clear()
	_reachability_last.clear()
	_reachability_queue.clear()
	_reachability_cursor = 0
	_reachability_budget = 0.0
	_reachability_clock = 0.0

## 每秒轮转一遍当前怪物，将真实碰撞查询分散到各物理帧；不在长帧补查同一怪物。
func _check_reachability(delta: float) -> void:
	if phase != Phase.BATTLE or combat_frozen or delta <= 0.0: return
	var generation := _generation
	_reachability_clock += delta
	if _reachability_queue.is_empty():
		if enemies.is_empty():
			_reachability_budget = 0.0
			return
		_reachability_queue = enemies.duplicate()
		_reachability_cursor = 0
	_reachability_budget += _reachability_queue.size() * delta
	var count := mini(_reachability_queue.size() - _reachability_cursor, floori(_reachability_budget + 0.000001))
	if count == 0: return
	_reachability_budget = maxf(0.0, _reachability_budget - count)
	var goal := Vector3.ZERO
	var goal_ready := false
	for index in count:
		var enemy := _reachability_queue[_reachability_cursor]
		_reachability_cursor += 1
		if not is_instance_valid(enemy) or enemy.dead or not enemy.is_inside_tree(): continue
		var id := enemy.get_instance_id()
		var elapsed := maxf(0.0, _reachability_clock - float(_reachability_last.get(id, _reachability_clock - delta)))
		_reachability_last[id] = _reachability_clock
		if enemy.spawn_delay > 0.0: continue
		if not goal_ready:
			goal = _ground_target()
			goal_ready = true
		_check_enemy_reachability(enemy, goal, elapsed)
		if phase != Phase.BATTLE or generation != _generation: return
	if _reachability_cursor == _reachability_queue.size():
		_reachability_queue.clear()
		_reachability_cursor = 0
		_reachability_budget = fmod(_reachability_budget, 1.0)

func _check_enemy_reachability(enemy: WaveEnemy, goal: Vector3, elapsed: float) -> void:
	var id := enemy.get_instance_id()
	var closest := _path.graph.get_point_position(_path.closest_point(enemy.global_position))
	var on_map := TerrainPath.horizontal_distance(enemy.global_position, closest) <= terrain.data.cell_size
	var reachable: bool = on_map and enemy.global_position.y >= _path.ground_position(enemy.global_position).y - 1.5 and enemy.navigation.shared_reachable(enemy.global_position, goal)
	_unreachable[id] = 0.0 if reachable else float(_unreachable.get(id, 0.0)) + elapsed
	if _unreachable[id] >= unreachable_timeout:
		push_warning("Wave unreachable timeout: wave=%d enemy=%s position=%s target=%s on_map=%s ground_y=%.3f" % [wave, enemy.definition.enemy_id if enemy.definition else enemy.name, enemy.global_position, goal, on_map, _path.ground_position(enemy.global_position).y])
		_finish("挑战中断 · 残余怪物无法到达，请重试")

## 仅延后清波／选卡，死亡与计分即时结算；真实时间上限防止视觉对象退出后卡局。
func hold_wave_finish(seconds: float) -> bool:
	if seconds <= 0.0:
		_wave_finish_deadline = 0
		return true
	if phase != Phase.BATTLE or _pending > 0 or not enemies.is_empty(): return false
	_wave_finish_deadline = Time.get_ticks_usec() + int(clampf(seconds, 0.0, 5.0) * 1000000.0)
	return true

func is_wave_finish_pending() -> bool:
	return phase == Phase.BATTLE and Time.get_ticks_usec() < _wave_finish_deadline

func _clear_wave() -> void:
	if _preparing_wave or phase != Phase.BATTLE or _pending > 0 or not enemies.is_empty(): return
	if is_wave_finish_pending(): return
	if not _clearing_wave:
		_clearing_wave = true
		_cleanup_attacks(true)
		var generation := _generation
		wave_clearing.emit()
		if phase != Phase.BATTLE or generation != _generation: return
	if combat_frozen: return
	var cleared := wave
	var serial := _run_serial
	completed_waves = wave
	if not _run_endless and completed_waves >= wave_count():
		_finish("挑战完成", Outcome.VICTORY, true)
	else:
		_set_phase(Phase.REST)
	if serial == _run_serial: wave_cleared.emit(cleared)

func retreat() -> void:
	if phase in [Phase.BATTLE, Phase.REST]: _finish("本轮结束 · 主动撤退", Outcome.RETREAT)

func _finish(reason: String, result := Outcome.ERROR, keep_presentations := false) -> void:
	if phase == Phase.RESULT: return
	combat_modifiers.reset()
	_survival.reset()
	_strike_speed_tier = -1
	_preparing_wave = false
	_starting_run = false
	set_combat_frozen(false)
	_spawn_state.clear()
	_cleanup_attacks(keep_presentations)
	var remaining := _enemy_roster.take_all()
	_reset_reachability()
	for enemy in remaining: enemy.cancel()
	result_reason = reason
	outcome = result
	var generation := _generation
	_set_phase(Phase.RESULT)
	if phase == Phase.RESULT and generation == _generation: run_ended.emit(reason)

func _cleanup_attacks(keep_presentations := false) -> void:
	if is_instance_valid(_spawn_shadows): _spawn_shadows.clear()
	if not keep_presentations:
		for retired in _retired_presentations:
			if is_instance_valid(retired):
				retired.process_mode = Node.PROCESS_MODE_DISABLED
				retired.queue_free()
		_retired_presentations.clear()
	else:
		_retired_presentations = _retired_presentations.filter(is_instance_valid)
		var feedback := _attack_root.get_node_or_null("EnemyFeedbackPool") as EnemyFeedbackPool if is_instance_valid(_attack_root) else null
		if feedback and feedback.preserve_on_clear:
			# 留住原父节点，避免节点重入树重置共享材质生命周期；危险对象先全部停用。
			for child in _attack_root.get_children():
				if child != feedback:
					child.process_mode = Node.PROCESS_MODE_DISABLED
					child.queue_free()
			_attack_root.name = "RetiredPresentations"
			register_combat_node(_attack_root)
			_retired_presentations.append(_attack_root)
			feedback.presentations_finished.connect(_attack_root.queue_free, CONNECT_ONE_SHOT)
			feedback.retire_presentations()
			_attack_root = null
	_enemy_update_revision += 1
	_generation += 1
	if is_instance_valid(_enemy_update_batch):
		_enemy_update_batch.release_all()
		remove_child(_enemy_update_batch)
		_enemy_update_batch.queue_free()
	_enemy_update_batch = null
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
	_restore_player_home()
	_set_phase(Phase.READY)

## End only run-owned work; keep map geometry and navigation ready for another visit.
func reset_for_menu() -> void:
	if phase in [Phase.BATTLE, Phase.REST]: retreat()
	elif phase == Phase.READY:
		set_combat_frozen(false)
		_cleanup_attacks()
		combat_modifiers.reset()
	_survival.reset()
	_strike_speed_tier = -1
	_spawn_state.clear()
	wave = 0
	completed_waves = 0
	kills = 0
	_spawned_this_wave = 0
	_spawned_run = 0
	_wave_queued_total = 0
	_queue_sequence = 0
	_wave_clock = 0.0
	_hurt_clock = 0.0
	_notice = ""
	_notice_clock = 0.0
	_clearing_wave = false
	result_reason = ""
	outcome = Outcome.NONE
	_restore_player_home()
	_set_phase(Phase.READY)

func _restore_player_home() -> void:
	player.heal(player.max_health)
	player.global_position = return_point.global_position if return_point else global_position + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	if player.movement_camera is FollowCamera: (player.movement_camera as FollowCamera).snap_to_target()
	_restore_preview()

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
		"active_limit":get_active_enemy_limit(), "population_cost":_population_cost, "alive_by_role":_alive_by_role.duplicate(), "capacity_waiting":_capacity_waiting,
		"enemy_health_multiplier":get_enemy_health_multiplier(), "simulation":is_horde_simulation(),
		"pending":_pending, "alive":enemies.size(), "warning":warning_count, "queued_this_wave":_wave_queued_total,
		"spawned_this_wave":_spawned_this_wave, "spawned_total":_spawned_run, "kills":kills,
		"spawn_complete":_pending == 0, "clearing":phase == Phase.BATTLE and _clearing_wave, "combat_frozen":combat_frozen, "navigation_ready":_path_ready,
		"wave_elapsed":_wave_clock, "reason":result_reason}

func status_text() -> String:
	match phase:
		Phase.BATTLE: return "%s   ·   待出现 %d   ·   场上 %d   ·   击败 %d\n%s" % [wave_label(wave), _pending, enemies.size(), kills, _notice if _notice_clock > 0.0 else "基础自动攻击 · 走位生存 · 离开南侧区域结束本轮"]
		Phase.REST: return "%s已完成 · 安全休整，无倒计时\nTab 查看背包 · 准备好后主动继续%s" % [wave_label(wave), "\n下一波：" + next_wave_description() if not next_wave_description().is_empty() else ""]
		Phase.READY: return "%s挑战 · %s按 %s 开始\n自动攻击 · 经验升级 · 清波休整" % ["无尽" if is_endless() else "波次", "到入口附近" if start_requires_proximity else "", OS.get_keycode_string(interact_key)]
		_: return "波次循环灰盒 · 天气与世界继续运行"

func get_skill_slots() -> Array[String]:
	var result: Array[String] = []
	for slot in get_run_skill_slots(): result.append(slot.id)
	while result.size() < 4: result.append("")
	return result

func get_run_skill_slots() -> Array[Dictionary]:
	var skills := get_node_or_null("RunSkillManager") as RunSkillManager
	return skills.get_slots() if skills else []
