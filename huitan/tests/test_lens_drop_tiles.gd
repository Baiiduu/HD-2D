extends SceneTree
## 无界面候选覆盖／顺序验证；不采样 GPU、不渲染或截图。
const TILES = preload("res://scripts/rendering/lens_drop_tiles.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 8: printerr("FAIL: ", message)

func candidates(cells: PackedVector4Array, uv: Vector2) -> Array[int]:
	var tile := Vector2i(clampi(int(uv.x * TILES.GRID.x), 0, TILES.GRID.x - 1), clampi(int(uv.y * TILES.GRID.y), 0, TILES.GRID.y - 1))
	var packed := cells[tile.y * TILES.GRID.x + tile.x]
	var result: Array[int] = []
	for slot in TILES.MAX_DROPS:
		var index := ((int(packed[slot / 3]) >> ((slot % 3) * 4)) & 15) - 1
		if index < 0: break
		result.append(index)
	return result

func hits(drops: PackedVector4Array, indices: Array[int], uv: Vector2, screen: Vector2) -> Array[int]:
	var result: Array[int] = []
	for index in indices:
		var drop := drops[index]
		if drop.w <= 0.0: continue
		var point := (uv - Vector2(drop.x, drop.y)) * screen / maxf(drop.z * screen.y / 900.0, 1.0)
		if point.length_squared() <= 6.25: result.append(index)
	return result

func coverage_checks() -> void:
	var tiles := TILES.new()
	var drops := PackedVector4Array([
		Vector4(0.02, 0.05, 34.0, 1.0), Vector4(0.5, 0.5, 28.0, 1.0),
		Vector4(0.51, 0.49, 18.0, 0.3), Vector4(0.98, 1.02, 34.0, 1.0),
		Vector4(-0.01, 0.6, 36.0, 0.5), Vector4(0.6, 0.2, 0.0, 1.0),
		Vector4(0.4, 0.9, 50.0, 0.00001), Vector4(0.5, 0.5, 500.0, 0.0),
		Vector4(0.8, 0.75, 40.0, 1.0), Vector4(1.5, 1.5, 1.0, 1.0),
		Vector4(0.125, 0.25, 22.0, 1.0), Vector4(1.0, 0.0, 22.0, 1.0),
	])
	var all_indices: Array[int] = []
	for index in TILES.MAX_DROPS: all_indices.append(index)
	for screen in [Vector2(1440, 900), Vector2(2560, 1440), Vector2(900, 1440), Vector2(64, 40), Vector2(8, 8)]:
		var cells: PackedVector4Array = tiles.build(drops, screen)
		check(cells.size() == 192, "候选表保持固定的小尺寸")
		for y in TILES.GRID.y + 1:
			for x in TILES.GRID.x + 1:
				for offset in [Vector2.ZERO, Vector2(0.000001, 0.000001), Vector2(-0.000001, -0.000001), Vector2(0.5 / TILES.GRID.x, 0.5 / TILES.GRID.y)]:
					var uv: Vector2 = (Vector2(float(x) / TILES.GRID.x, float(y) / TILES.GRID.y) + offset).clamp(Vector2.ZERO, Vector2.ONE)
					var indices := candidates(cells, uv)
					check(hits(drops, indices, uv, screen) == hits(drops, all_indices, uv, screen), "不同分辨率、屏幕边界与格线两侧保留全部原候选及其叠加顺序")
		# 在旧圆形早退的边界上再取样，避免小水滴恰好漏过格线。
		for index in TILES.MAX_DROPS:
			var drop := drops[index]
			if drop.w <= 0.0: continue
			var extent: Vector2 = Vector2.ONE * maxf(drop.z * screen.y / 900.0, 1.0) * 2.5 / screen
			for angle in 48:
				var uv: Vector2 = Vector2(drop.x, drop.y) + Vector2.from_angle(TAU * angle / 48.0) * extent
				if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0: continue
				check(index in candidates(cells, uv), "圆形剔除边界上的雨滴不会被候选表提前移除")

func packing_checks() -> void:
	var tiles := TILES.new()
	var drops := PackedVector4Array()
	for index in 14: drops.append(Vector4(0.5, 0.5, 10000.0, 1.0))
	var cells: PackedVector4Array = tiles.build(drops, Vector2(1440, 900))
	var expected: Array[int] = []
	for index in 12: expected.append(index)
	check(candidates(cells, Vector2(0.5, 0.5)) == expected, "12 颗完全重叠时保留顺序且不读取第 13／14 个输入")
	check(cells[0] == Vector4(0x321, 0x654, 0x987, 0xcba), "打包编号经 float32 存储后可逐项精确还原")
	var sparse: PackedVector4Array = tiles.build(PackedVector4Array([Vector4(0.1, 0.1, 20.0, 1.0)]), Vector2(1440, 900))
	check(candidates(sparse, Vector2(0.1, 0.1)) == [0] and candidates(sparse, Vector2(0.9, 0.9)).is_empty(), "空白区域直接得到空候选，不遍历整份雨滴列表")
	var moved: PackedVector4Array = tiles.build(PackedVector4Array([Vector4(0.9, 0.9, 20.0, 1.0)]), Vector2(1440, 900))
	check(candidates(moved, Vector2(0.1, 0.1)).is_empty() and candidates(moved, Vector2(0.9, 0.9)) == [0], "移动水滴时撤销旧覆盖并登记新覆盖")
	check(candidates(sparse, Vector2(0.1, 0.1)) == [0] and candidates(sparse, Vector2(0.9, 0.9)).is_empty(), "后续重建不串改已经提交的 Packed 快照")
	var empty: PackedVector4Array = tiles.build(PackedVector4Array(), Vector2(1440, 900))
	check(candidates(empty, Vector2(0.9, 0.9)).is_empty(), "移除全部雨滴不会遗留候选")
	var invisible: PackedVector4Array = tiles.build(PackedVector4Array([Vector4(0.5, 0.5, 10000.0, 0.0)]), Vector2(1440, 900))
	check(candidates(invisible, Vector2(0.5, 0.5)).is_empty(), "完全淡出的雨滴不再进入候选")
	var invalid: PackedVector4Array = tiles.build(drops, Vector2.ZERO)
	check(candidates(invalid, Vector2(0.5, 0.5)).is_empty(), "无效视口不计算覆盖，交由 shader 尺寸校验回退")

func run() -> void:
	coverage_checks()
	packing_checks()
	print("Lens drop tiles: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
