@tool
class_name TerrainSurfaceStamp
extends Resource

## 完整图块的中心、角度与覆盖尺寸；坐标均为 Terrain 本地 XZ 米数。
@export_range(0, 257, 1) var code := 0:
	set(value): code = clampi(value, 0, 257); emit_changed()
@export var position := Vector2.ZERO:
	set(value): position = value; emit_changed()
@export var rotation_degrees := 0.0:
	set(value): rotation_degrees = value; emit_changed()
## 仅用于保留既有铺装边界；空值不限制自由图块。
@export var clip_rect := Rect2():
	set(value): clip_rect = value; emit_changed()
@export var flip_h := false:
	set(value): flip_h = value; emit_changed()
@export var layer_order := 0:
	set(value): layer_order = value; emit_changed()
@export var size_meters := Vector2(1.6, 1.6):
	set(value): size_meters = value.max(Vector2(0.025, 0.025)); emit_changed()

func uv_at(point: Vector2) -> Vector2:
	var uv := (point - position).rotated(-deg_to_rad(rotation_degrees)) / size_meters + Vector2.ONE * 0.5
	if flip_h: uv.x = 1.0 - uv.x
	return uv

func contains_point(point: Vector2) -> bool:
	if clip_rect.has_area() and not clip_rect.has_point(point): return false
	var uv := uv_at(point)
	return uv.x >= 0.0 and uv.y >= 0.0 and uv.x < 1.0 and uv.y < 1.0

func get_rect() -> Rect2:
	var half := size_meters * 0.5
	var angle := deg_to_rad(rotation_degrees)
	var cosine := absf(cos(angle))
	var sine := absf(sin(angle))
	var extent := Vector2(half.x * cosine + half.y * sine, half.x * sine + half.y * cosine)
	var rect := Rect2(position - extent, extent * 2.0)
	return rect.intersection(clip_rect) if clip_rect.has_area() else rect

func get_corners() -> PackedVector2Array:
	var half := size_meters * 0.5
	var result := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		result.append(position + corner.rotated(deg_to_rad(rotation_degrees)))
	return result
