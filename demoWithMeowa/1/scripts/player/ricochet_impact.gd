class_name RicochetImpact
extends RefCounted

## 同一真实反弹的快照；表现消费者不改写碰撞或本体速度。
var point: Vector3
var normal: Vector3
var incoming_velocity: Vector3
var outgoing_velocity: Vector3
var serial: int
var flight_id: int
var seconds: float

func _init(contact := Vector3.ZERO, wall_normal := Vector3.ZERO, incoming := Vector3.ZERO, outgoing := Vector3.ZERO, event_serial := 0, flight := 0, time := 0.0) -> void:
	point = contact
	normal = wall_normal
	incoming_velocity = incoming
	outgoing_velocity = outgoing
	serial = event_serial
	flight_id = flight
	seconds = time

func strength(reference_speed := 12.0) -> float:
	return pow(clampf(-incoming_velocity.dot(normal) / maxf(reference_speed, 0.001), 0.0, 1.0), 1.15)

func turn_side(fallback := 1.0) -> float:
	var turn := incoming_velocity.cross(outgoing_velocity).y
	return signf(turn) if absf(turn) > 0.001 else fallback
