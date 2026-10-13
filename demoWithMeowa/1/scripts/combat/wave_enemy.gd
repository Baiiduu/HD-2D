class_name WaveEnemy
extends CharacterBody3D

## 波次敌人的生命周期接口；移动、命中判断与招式由具体怪物实现。
signal defeated(enemy: WaveEnemy)

var wave_mode := false
var wave_target: Player
var navigation: TerrainPath
var health := 20.0
var move_speed := 1.35
var attack_damage := 8.0
var spawn_clearance := 0.35
var experience_reward := 0
var spawn_delay := 0.8
var dead := false
## 弹丸与危险区放在此节点下，清波或结束时统一清理。
var attack_root: Node3D
var damage_player: Callable
## 分裂或召唤必须先登记，再结束母体生命周期。
var request_spawn: Callable
var combat_active: Callable

func configure_wave(context: Dictionary, definition: WaveEnemyDefinition, warning: float) -> void:
	wave_mode = true
	wave_target = context.player
	navigation = context.navigation
	attack_root = context.attack_root
	damage_player = context.damage_player
	request_spawn = context.request_spawn
	combat_active = context.get("combat_active", Callable())
	health = definition.health
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

func _physics_process(delta: float) -> void:
	if not wave_mode or dead or not is_instance_valid(wave_target): return
	spawn_delay = maxf(spawn_delay - delta, 0.0)
	if spawn_delay <= 0.0: _combat_tick(delta)

func _combat_tick(_delta: float) -> void:
	pass

func take_damage(amount: float) -> void:
	if not wave_mode or dead or spawn_delay > 0.0 or not is_finite(amount) or amount <= 0.0: return
	if combat_active.is_valid() and not combat_active.call(): return
	health = maxf(health - amount, 0.0)
	_damage_feedback()
	if health <= 0.0:
		dead = true
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
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	set_physics_process(false)
	queue_free()
