class_name DamageNumbers
extends CanvasLayer

## 伤害事件 → 样式 → 世界锚点投影 → 复用数字。没有技能或伤害公式依赖。
@export_group("伤害数字连接")
@export var session: WavePrototype
@export var enabled := true:
	set(value):
		enabled = value
		if not value and is_node_ready(): clear()
## 标签缺失时回退 normal；可追加自定义标签，新增技能无需改显示代码。
@export var number_styles: Array[DamageNumberStyle] = []

@export_group("密集命中与复用")
@export_range(1, 9, 1) var number_stack_columns := 5
## 同一目标的错位间距，逻辑像素；不合并数值或丢弃有效伤害。
@export var number_stack_spacing := Vector2(16.0, 10.0)
@export_range(0, 256, 1) var number_prewarm := 24
## 仅限制闲置池；激活数字可按实际命中数扩展，结束后回收多余节点。
@export_range(0, 1024, 1) var number_idle_limit := 128:
	set(value):
		number_idle_limit = maxi(value, 0)
		if is_node_ready():
			while _idle.size() > number_idle_limit: _idle.pop_back().queue_free()

var _active: Array[DamageNumber] = []
var _idle: Array[DamageNumber] = []
var _lanes: Dictionary[int, Dictionary] = {}
var _fallback := DamageNumberStyle.new()
var _created := 0
var _reused := 0
var _peak_active := 0
var _last_tick := 0
var _holes := 0
var _clear_revision := 0

func _ready() -> void:
	layer = 5
	set_process(false)
	for index in mini(number_prewarm, number_idle_limit): _idle.append(_create_number())
	if not session: return
	session.enemy_spawned.connect(_watch_enemy)
	session.run_started.connect(clear)
	session.run_ended.connect(_on_run_ended)
	session.combat_frozen_changed.connect(_frozen_changed)
	session.register_combat_node(self)
	for enemy in session.enemies: _watch_enemy(enemy)

func _watch_enemy(enemy: WaveEnemy) -> void:
	if not enemy.damaged.is_connected(present): enemy.damaged.connect(present)

func _on_run_ended(_reason: String) -> void:
	clear()

## 也可供独立预览或其它已结算的伤害来源接入；不会反向修改战斗。
func present(event: CombatDamageEvent) -> void:
	if not enabled or not is_inside_tree() or not event or not event.world_position.is_finite(): return
	var amount := event.display_amount()
	if not is_finite(amount) or amount <= 0.0: return
	var profile := style_for(event.style)
	var state: Dictionary = _lanes.get(event.target_id, {"next": 0, "active": 0})
	var slot := int(state.next) % maxi(number_stack_columns, 1)
	state.next = slot + 1
	state.active += 1
	_lanes[event.target_id] = state
	var number: DamageNumber
	if _idle.is_empty(): number = _create_number()
	else:
		number = _idle.pop_back()
		_reused += 1
	number.begin(event, profile, slot, number_stack_spacing, get_viewport().get_camera_3d())
	_active.append(number)
	_peak_active = maxi(_peak_active, _active.size() - _holes)
	if not is_processing(): _last_tick = Time.get_ticks_usec()
	set_process(true)

func style_for(id: StringName) -> DamageNumberStyle:
	var normal := _fallback
	for profile in number_styles:
		if not profile: continue
		if profile.style_id == id: return profile
		if profile.style_id == &"normal": normal = profile
	return normal

func _create_number() -> DamageNumber:
	var number := DamageNumber.new()
	add_child(number)
	_created += 1
	return number

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := maxf(0.0, (now - _last_tick) / 1000000.0) if _last_tick > 0 else 0.0
	_last_tick = now
	var camera := get_viewport().get_camera_3d()
	# 切入短顿的一帧仍可能带有旧 delta，不能用新倍率反推真实时长。
	if camera is FollowCamera and camera.hit_stop_active: delta = real_delta
	var revision := _clear_revision
	for index in range(_active.size() - 1, -1, -1):
		var number := _active[index]
		var alive := number.advance(delta, camera)
		if revision != _clear_revision: return
		if not alive:
			# 保留原逆序更新／回收时机；空位在整轮末尾稳定压紧一次。
			_active[index] = null
			_holes += 1
			_recycle(number)
			if revision != _clear_revision: return
	if _holes > 0:
		var write := 0
		for number in _active:
			if number == null: continue
			_active[write] = number
			write += 1
		_active.resize(write)
		_holes = 0
	if _active.is_empty(): set_process(false)

func _frozen_changed(_frozen: bool) -> void:
	_last_tick = Time.get_ticks_usec()

func _recycle(number: DamageNumber) -> void:
	var id := number.event.target_id
	var state: Dictionary = _lanes[id]
	state.active -= 1
	if state.active <= 0: _lanes.erase(id)
	number.release()
	if _idle.size() < maxi(number_idle_limit, 0): _idle.append(number)
	else: number.queue_free()

func clear() -> void:
	_clear_revision += 1
	for number in _active:
		if number != null: _recycle(number)
	_active.clear()
	_holes = 0
	_lanes.clear()
	_last_tick = 0
	set_process(false)

func get_pool_stats() -> Dictionary:
	return {"active": _active.size() - _holes, "idle": _idle.size(), "created": _created, "reused": _reused, "peak_active": _peak_active, "targets": _lanes.size()}
