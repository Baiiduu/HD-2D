class_name WaveEnemy
extends CharacterBody3D

## 波次敌人的生命周期接口；移动、命中判断与招式由具体怪物实现。
signal defeated(enemy: WaveEnemy)

var wave_mode := false
var wave_target: Player
var navigation: TerrainPath
var health := 20.0
var max_health := 20.0
var health_multiplier := 1.0
var spawn_wave := 0
var move_speed := 1.35
var attack_damage := 8.0
var spawn_clearance := 0.35
var experience_reward := 0
var spawn_delay := 0.8
var dead := false
var definition: WaveEnemyDefinition
var spatial_index: WaveEnemySpatialIndex
## 弹丸与危险区放在此节点下，清波或结束时统一清理。
var attack_root: Node3D
var damage_player: Callable
## 昂贵命中查询前先检查共享受击保护；实际扣血仍由 damage_player 再次校验。
var can_damage_player: Callable
## 分裂或召唤必须先登记，再结束母体生命周期。
var request_spawn: Callable
var request_spawn_by_id: Callable
var combat_active: Callable
var _speed_boosts: Dictionary[int, Dictionary] = {}

## 鼓舞按来源保存并取最强值；不改写基础移速，不叠乘。
func add_speed_boost(source: WaveEnemy, multiplier: float, seconds: float) -> void:
	if dead or not is_instance_valid(source) or source.dead or not is_finite(multiplier) or not is_finite(seconds) or multiplier <= 1.0 or seconds <= 0.0: return
	_speed_boosts[source.get_instance_id()] = {"source": weakref(source), "multiplier": multiplier, "remaining": seconds}

func remove_speed_boost(source_id: int) -> void:
	_speed_boosts.erase(source_id)

func effective_move_speed() -> float:
	if _speed_boosts.is_empty(): return move_speed
	var multiplier := 1.0
	for boost in _speed_boosts.values():
		var source: WaveEnemy = boost.source.get_ref()
		if is_instance_valid(source) and not source.dead: multiplier = maxf(multiplier, boost.multiplier)
	return move_speed * multiplier

func _tick_speed_boosts(delta: float) -> void:
	if _speed_boosts.is_empty(): return
	for id in _speed_boosts.keys():
		var boost := _speed_boosts[id]
		boost.remaining -= delta
		var source: WaveEnemy = boost.source.get_ref()
		if boost.remaining <= 0.0 or not is_instance_valid(source) or source.dead: _speed_boosts.erase(id)

func configure_wave(context: Dictionary, definition: WaveEnemyDefinition, warning: float) -> void:
	self.definition = definition
	spatial_index = context.get("spatial_index")
	wave_mode = true
	wave_target = context.player
	navigation = context.navigation
	attack_root = context.attack_root
	damage_player = context.damage_player
	can_damage_player = context.get("can_damage_player", Callable())
	request_spawn = context.request_spawn
	request_spawn_by_id = context.get("request_spawn_by_id", Callable())
	combat_active = context.get("combat_active", Callable())
	health_multiplier = clampf(context.get("health_multiplier", 1.0), 1.0, WaveHealthGrowthRules.HARD_MAX_MULTIPLIER)
	spawn_wave = context.get("wave", 0)
	max_health = definition.health * health_multiplier
	health = max_health
	move_speed = definition.move_speed
	attack_damage = definition.attack_damage
	spawn_clearance = definition.spawn_clearance
	experience_reward = definition.experience_reward
	spawn_delay = maxf(warning, 0.0)
	collision_layer = 2
	collision_mask = 1

func _ready() -> void:
	if wave_mode:
		add_to_group(&"enemies")
		add_to_group(&"wave_enemies")
		if spatial_index: spatial_index.update(self)

func _exit_tree() -> void:
	if spatial_index: spatial_index.remove(self)

func _physics_process(delta: float) -> void:
	if not wave_mode or dead or not is_instance_valid(wave_target): return
	_tick_speed_boosts(delta)
	spawn_delay = maxf(spawn_delay - delta, 0.0)
	if spawn_delay <= 0.0: _combat_tick(delta)
	if spatial_index: spatial_index.update(self)

func _combat_tick(_delta: float) -> void:
	pass

func take_damage(amount: float) -> void:
	if not wave_mode or dead or spawn_delay > 0.0 or not is_finite(amount) or amount <= 0.0: return
	if combat_active.is_valid() and not combat_active.call(): return
	health = maxf(health - amount, 0.0)
	_damage_feedback()
	if health <= 0.0:
		dead = true
		if spatial_index: spatial_index.remove(self)
		# 子类可在此登记待生成幼体；控制器不会提前清波。
		_on_defeated()
		defeated.emit(self)
		queue_free()

func _damage_feedback() -> void:
	pass

func _on_defeated() -> void:
	pass

## 各种怪物自行决定击退反应，精英和首领可在自己的行为中减弱。
func apply_knockback(_direction: Vector3, _distance: float) -> void:
	pass

func cancel() -> void:
	dead = true
	if spatial_index: spatial_index.remove(self)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	set_physics_process(false)
	queue_free()
