class_name EnemyOrbitPath
extends RefCounted

## 沿固定怪群轮廓汇向后沿；按空间长度细分，低帧率也逐段检测真实障碍。
const STEP := 0.12
var region: Dictionary
var points := PackedVector3Array()
var distances := PackedFloat32Array()
var length := 0.0
var duration := 0.0
var initial_speed := 0.0
var travelled := 0.0
var cursor := 1

func _init(outline: Dictionary, start: Vector3, heading: Vector3, clockwise: bool, speed: float, minimum_seconds: float, resistance: float, body_radius := 0.28) -> void:
	region = outline
	var center: Vector3 = region.center
	var u: Vector3 = region.u
	var v: Vector3 = region.v
	var radii: Vector2 = region.radii
	var offset := start - center
	var local := Vector2(offset.dot(u) / radii.x, offset.dot(v) / radii.y)
	var radius := local.length()
	if radius < 0.00001:
		var fallback := Vector3(heading.z, 0.0, -heading.x) * (1.0 if clockwise else -1.0)
		local = Vector2(fallback.dot(u) / radii.x, fallback.dot(v) / radii.y)
	var angle := local.angle()
	if not region.has("arrival_angle"): region["arrival_angle"] = angle + PI
	var arrival: float = region.arrival_angle
	var slot: int = region.get("arrival_count", 0)
	region["arrival_count"] = slot + 1
	var half_span: float = region.get("arrival_span", PI * 0.5) * 0.5
	var spacing: float = region.get("arrival_spacing", body_radius * 2.1)
	var edge_width := Vector2(radii.x * sin(arrival), radii.y * cos(arrival)).length()
	var half_columns := maxi(1, floori(half_span * edge_width / spacing))
	var columns := half_columns * 2 + 1
	var column := slot % columns
	var lane := ceili(column * 0.5) * (1 if column % 2 == 1 else -1)
	var destination_angle := arrival + lane * half_span / half_columns
	var row := slot / columns
	var edge_radius := Vector2(radii.x * cos(destination_angle), radii.y * sin(destination_angle)).length()
	# 一排略向内，其余向后错开；保留厚度，避免整群摊成空心椭圆或叠成一个点。
	var depth := -1 if row == 1 else maxi(0, row - 1)
	var landing_radius := maxf(0.6, 1.0 + depth * spacing / edge_radius)
	var rotation := 1.0 if clockwise else -1.0
	var turn := fposmod((destination_angle - angle) * rotation, TAU)
	if absf(wrapf(angle - arrival, -PI, PI)) <= half_span and turn > PI:
		# 已在后沿的同伴就近收势，不为了排位绕完整一圈。
		turn = 0.0
	turn *= minf(resistance, 1.0) * rotation
	var steps := maxi(32, ceili((absf(turn) * maxf(radii.x, radii.y) * maxf(radius, landing_radius) + (absf(radius - 1.0) + absf(landing_radius - 1.0)) * maxf(radii.x, radii.y)) / STEP))
	points.append(start)
	distances.append(0.0)
	for index in range(1, steps + 1):
		var progress := float(index) / steps
		# 内排先平滑并入外沿，避免瞬移；之后沿同一椭圆抵达对侧。
		var radial := lerpf(radius, 1.0, smoothstep(0.0, 0.25, progress))
		radial = lerpf(radial, landing_radius, smoothstep(0.8, 1.0, progress))
		var theta := angle + turn * progress
		var point := center + (u * radii.x * cos(theta) + v * radii.y * sin(theta)) * radial
		point.y = start.y
		length += TerrainPath.horizontal_distance(points[-1], point)
		points.append(point)
		distances.append(length)
	# 缓冲时长是附加收势，时长成长在大小怪群中都有效，不会被路程下限吞掉。
	duration = minimum_seconds + 2.0 * length / (speed * resistance)
	initial_speed = 2.0 * length / duration

func distance_at(age: float) -> float:
	var time := clampf(age / duration, 0.0, 1.0)
	return length * time * (2.0 - time)

func speed_at(distance: float) -> float:
	return initial_speed * sqrt(maxf(0.0, 1.0 - distance / maxf(length, 0.000001)))
