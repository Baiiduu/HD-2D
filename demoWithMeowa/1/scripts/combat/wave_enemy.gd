class_name WaveEnemy
extends CharacterBody3D

## 波次敌人的生命周期接口；移动、命中判断与招式由具体怪物实现。
signal defeated(enemy: WaveEnemy)
signal damaged(event: CombatDamageEvent)

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
var spawn_delay := 0.0
var dead := false
## 模拟怪物不扣血、不死亡，仍按真实命中发出反馈事件。
var health_loss_disabled := false
var stun_remaining := 0.0
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
var _push_wave: EnemyPushWave
var _push_layer := 0

## 聚群只改变普通移动，不调整实体碰撞体、攻击距离或导航半径。
func get_crowd_spacing() -> float:
	return spawn_clearance * 2.0

func get_crowd_body_radius() -> float:
	return spawn_clearance

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

func configure_wave(context: Dictionary, definition: WaveEnemyDefinition, _warning: float) -> void:
	self.definition = definition
	health_loss_disabled = context.get("health_loss_disabled", false)
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
	# 波次已负责生成排期；怪物实例出生后直接激活，不再追加出生预警。
	spawn_delay = 0.0
	collision_layer = 2
	collision_mask = 1
	set_occlusion_outline_allowed(context.get("enemy_occlusion_outline_enabled", true))

## 适配怪物自己的显示节点；不覆盖各 Sprite 的独立选择，也不依赖怪物类型。
func set_occlusion_outline_allowed(value: bool) -> void:
	for visual in find_children("*", "Sprite3D", true, false):
		if visual.has_method("set_occlusion_outline_allowed"):
			visual.call("set_occlusion_outline_allowed", value)

func _ready() -> void:
	if wave_mode:
		add_to_group(&"enemies")
		add_to_group(&"wave_enemies")
		commit_spatial_state()

## Call after external movement, teleport or crowd-parameter/activation edits,
## before another spatial query. Ordinary ticks and spawning already do this.
## This publishes state only; the feature still owns its movement/action rules.
func commit_spatial_state() -> void:
	if spatial_index: spatial_index.update(self)

func _exit_tree() -> void:
	if spatial_index: spatial_index.remove(self)

func _physics_process(delta: float) -> void:
	if not wave_mode or dead or not is_instance_valid(wave_target): return
	if combat_active.is_valid() and not combat_active.call(): return
	_tick_speed_boosts(delta)
	spawn_delay = maxf(spawn_delay - delta, 0.0)
	if spawn_delay <= 0.0:
		if stun_remaining > 0.0:
			stun_remaining = maxf(0.0, stun_remaining - delta)
			_stunned_tick(delta)
			if stun_remaining == 0.0: _on_stun_ended()
		elif is_orbiting():
			# 眩晕抗性独立计时；外力未结束时不恢复追击、出招或接触伤害。
			_stunned_tick(delta)
		else:
			_combat_tick(delta)
		_advance_push(delta)
	commit_spatial_state()

func _combat_tick(_delta: float) -> void:
	pass

## 同类眩晕取较长剩余时间，不叠加。外力与真实碰撞仍由怪物自身处理。
func apply_stun(base_seconds: float) -> bool:
	if not wave_mode or dead or spawn_delay > 0.0 or not definition or not is_finite(base_seconds) or base_seconds <= 0.0: return false
	if combat_active.is_valid() and not combat_active.call(): return false
	var duration := base_seconds * definition.stun_duration_multiplier
	if not is_finite(duration) or duration <= 0.0: return false
	var was_stunned := stun_remaining > 0.0
	stun_remaining = maxf(stun_remaining, duration)
	velocity.x = 0.0
	velocity.z = 0.0
	if not was_stunned: _on_stun_started()
	return true

func _on_stun_started() -> void:
	pass

func _on_stun_ended() -> void:
	pass

func _stunned_tick(_delta: float) -> void:
	pass

func take_damage(amount: float, feedback: Dictionary = {}) -> void:
	if not wave_mode or dead or spawn_delay > 0.0 or not is_finite(amount) or amount <= 0.0: return
	if combat_active.is_valid() and not combat_active.call(): return
	var before := health
	if not health_loss_disabled: health = maxf(health - amount, 0.0)
	_damage_feedback()
	if (health < before or health_loss_disabled) and damaged.has_connections():
		damaged.emit(CombatDamageEvent.from_hit(self, before - health, amount, feedback))
	if health <= 0.0:
		dead = true
		if spatial_index: spatial_index.remove(self)
		# 子类可在此登记待生成幼体；控制器不会提前清波。
		_on_defeated()
		defeated.emit(self)
		queue_free()

## 未来异形怪物可重写，显示层不识别怪物类型。
func get_damage_feedback_position() -> Vector3:
	return global_position + Vector3.UP * 0.8

func _damage_feedback() -> void:
	pass

func _on_defeated() -> void:
	pass

## 各种怪物自行决定击退反应，精英和首领可在自己的行为中减弱。
func apply_knockback(_direction: Vector3, _distance: float) -> void:
	pass

## 平滑外力接口；未来怪物可自行决定抗性，默认不把未知移动类型强行瞬移。
func apply_push_impulse(_direction: Vector3, _speed: float, _seconds: float) -> bool:
	return false

## 绕行与眩晕抗性独立；未知移动类型默认拒绝轨迹，不强行瞬移。
func apply_orbit(_region: Dictionary, _heading: Vector3, _speed: float, _seconds: float, _clockwise: bool) -> bool:
	return false

func is_orbiting() -> bool:
	return false

func receive_push_wave(wave: EnemyPushWave, region: Dictionary, heading: Vector3, speed: float, seconds: float, stun: float, layer: int) -> bool:
	var moved := apply_orbit(region, heading, speed, seconds, wave.rules.clockwise)
	if moved:
		_push_wave = wave
		_push_layer = layer
	var stunned := apply_stun(stun)
	return moved or stunned

func _advance_push(_delta: float) -> void:
	pass

func cancel() -> void:
	dead = true
	if spatial_index: spatial_index.remove(self)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	set_physics_process(false)
	queue_free()
