extends RefCounted
## 每格按原顺序打包最多 12 个候选，四个 float32 各保存三个 4-bit 编号。
const GRID := Vector2i(16, 12)
const MAX_DROPS := 12
var _counts := PackedByteArray()

func _init() -> void:
	_counts.resize(GRID.x * GRID.y)

func build(drops: PackedVector4Array, screen_size: Vector2) -> PackedVector4Array:
	# Packed 数组按引用传递；每次输出独立快照，不改写渲染端尚在使用的上一份。
	var cells := PackedVector4Array()
	cells.resize(GRID.x * GRID.y)
	_counts.fill(0)
	if screen_size.x <= 0.0 or screen_size.y <= 0.0: return cells
	for index in mini(drops.size(), MAX_DROPS):
		var drop := drops[index]
		if drop.w <= 0.0: continue
		# 包住原 shader 的 dot(point, point) <= 6.25；留一像素浮点舍入余量。
		var radius := maxf(drop.z * screen_size.y / 900.0, 1.0)
		var extent := Vector2.ONE * (radius * 2.5 + 1.0) / screen_size
		var center := Vector2(drop.x, drop.y)
		var low := center - extent
		var high := center + extent
		if high.x < 0.0 or high.y < 0.0 or low.x > 1.0 or low.y > 1.0: continue
		var start := Vector2i(clampi(floori(low.x * GRID.x), 0, GRID.x - 1), clampi(floori(low.y * GRID.y), 0, GRID.y - 1))
		var end := Vector2i(clampi(floori(high.x * GRID.x), 0, GRID.x - 1), clampi(floori(high.y * GRID.y), 0, GRID.y - 1))
		for y in range(start.y, end.y + 1):
			for x in range(start.x, end.x + 1):
				var cell := y * GRID.x + x
				var slot := int(_counts[cell])
				var packed := cells[cell]
				packed[slot / 3] = float(int(packed[slot / 3]) | ((index + 1) << ((slot % 3) * 4)))
				cells[cell] = packed
				_counts[cell] = slot + 1
	return cells
