class_name WaveEnemy
extends CharacterBody3D

signal defeated(enemy: WaveEnemy)

var target: Player
var path: TerrainPath
var health := 20.0
var move_speed := 1.35
var spawn_delay := 0.8
var dead := false
var _route := PackedVector3Array()
var _route_clock := 0.0
var _waypoint := 0
var _body: MeshInstance3D
var _material: StandardMaterial3D
var _health_label: Label3D
var _flash := 0.0

func _ready() -> void:
	add_to_group(&"wave_enemies")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 0.8
	collision.shape = capsule
	collision.position.y = 0.4
	add_child(collision)
	_body = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.8
	_body.mesh = mesh
	_body.position.y = 0.4
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.65, 0.68, 0.72)
	_body.material_override = _material
	add_child(_body)
	_health_label = Label3D.new()
	_health_label.position.y = 1.05
	_health_label.font_size = 32
	_health_label.pixel_size = 0.009
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_health_label)

func take_damage(amount: float) -> void:
	if dead or spawn_delay > 0.0: return
	health = maxf(health - amount, 0.0)
	_flash = 0.15
	if health <= 0.0:
		dead = true
		defeated.emit(self)
		queue_free()

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(target): return
	spawn_delay = maxf(spawn_delay - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_material.albedo_color = Color.WHITE if _flash > 0.0 else Color(0.65, 0.68, 0.72)
	_body.scale = Vector3.ONE * (0.35 if spawn_delay > 0.0 else 1.0)
	_health_label.text = "…" if spawn_delay > 0.0 else str(ceili(health))
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	var direction := Vector3.ZERO
	if spawn_delay <= 0.0 and path and TerrainPath.horizontal_distance(global_position, target.global_position) > 0.65:
		_route_clock -= delta
		if _route_clock <= 0.0:
			_route_clock = 0.45
			var goal := target.global_position
			var cell := path.data.world_to_cell(path.terrain.to_local(goal))
			goal.y = path.terrain.global_position.y + path.data.get_level(cell) * path.data.layer_height
			_route = path.route(global_position, goal)
			_waypoint = 1 if _route.size() > 1 else 0
		if not _route.is_empty():
			while _waypoint < _route.size() - 1 and TerrainPath.horizontal_distance(global_position, _route[_waypoint]) < 0.2:
				_waypoint += 1
			direction = _route[_waypoint] - global_position
			direction.y = 0.0
			direction = direction.normalized()
			var separation := Vector3.ZERO
			for other in get_tree().get_nodes_in_group(&"wave_enemies"):
				if other == self or other.dead: continue
				var offset: Vector3 = global_position - other.global_position
				offset.y = 0.0
				if offset.length() > 0.01 and offset.length() < 0.75:
					separation += offset.normalized() * (0.75 - offset.length())
			direction = (direction + separation * 1.5).normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	move_and_slide()
