class_name Player
extends CharacterBody3D

@export var speed: float = 4.0
## 可活动范围（XZ），由场景根据地形大小设置
var bounds := Rect2(-INF, -INF, INF, INF)
@onready var sprite: Sprite3D = $Sprite

func _physics_process(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.y * speed
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0
	move_and_slide()
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)
