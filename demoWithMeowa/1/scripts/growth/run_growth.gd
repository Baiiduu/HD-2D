class_name RunGrowth
extends Node3D

signal experience_collected(amount: int)
## 确认后、恢复战斗前应用本局技能；其它成长效果仍可监听同一接口。
signal growth_chosen(level: int, option_id: StringName)
signal growth_choice_skipped(level: int)

@export_group("成长连接与内容")
@export var session: Node3D
@export var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			experience_hud.visible = value
			if not value: _end_run("")
@export var rules: ExperienceRules
@export var pickup_scene: PackedScene
## 静态候选备用；正式地图通过动态来源生成武器与增益选项。
@export var choice_options: Array[GrowthChoiceOption] = []

@export_group("成长抽卡")
@export_range(1, 6, 1) var cards_per_draw := 3
## 初始技能与后续升级共用；池子已全部展示时不消耗次数。
@export_range(0, 10, 1) var rerolls_per_run := 3
## 0 每局随机；非零用于复现抽取，不影响敌人生成。
@export var draw_seed := 0

@export_group("经验吸取")
@export_range(0.1, 10.0, 0.1, "suffix:m") var attraction_radius := 2.0
@export_range(0.05, 1.0, 0.05, "suffix:m") var collection_radius := 0.3
## 触发吸取时允许的高差；已吸引的宝石继续跟随人物。
@export_range(0.1, 3.0, 0.1, "suffix:m") var height_tolerance := 1.0
@export_range(0.1, 10.0, 0.1, "suffix:m/s") var attraction_initial_speed := 2.0
@export_range(0.0, 40.0, 1.0) var attraction_acceleration := 12.0
@export_range(1.0, 20.0, 0.5, "suffix:m/s") var attraction_max_speed := 8.0
## 清波自动收取剩余经验，先完成升级选择，再休整或结算。
@export var collect_remaining_on_clear := true
## 达到场上上限后将经验并入附近一粒，保留全部经验值。
@export_range(1, 1000, 1) var max_pickups := 256

@export_group("吸收微光")
## 独立的短暂视觉反馈，不参与伤害或经验结算。
@export_range(0.0, 0.4, 0.01, "suffix:s") var absorb_duration := 0.16
@export_range(0.05, 0.8, 0.01, "suffix:m") var absorb_size := 0.24
@export_range(0.0, 1.0, 0.05) var absorb_opacity := 0.65

var state: RunGrowthState
## 可选的动态候选来源；空池明确跳过本次选择，不制造空白奖励或额外恢复。
var candidate_provider: Callable
var active := false
var _drops: Array[ExperiencePickup] = []
var _choice_level := 0
var _choice_error := false
var rerolls_left := 0
var _draft_started := false
var _draw_pool := preload("res://scripts/growth/growth_draw_pool.gd").new()
var _candidate_pool: Array[GrowthChoiceOption] = []
var _previous_draw: Array[GrowthChoiceOption] = []
var _fallback_options: Array[GrowthChoiceOption] = []
@onready var choice_ui: GrowthChoiceUI = $GrowthChoiceUI
@onready var experience_hud: ExperienceHUD = $ExperienceHUD
@onready var _absorb: Sprite3D = $AbsorbFlash
var _absorb_left := 0.0

func _ready() -> void:
	_fallback_options = choice_options.duplicate()
	state = RunGrowthState.new()
	state.rules = rules
	state.levels_gained.connect(_levels_gained)
	var loadout: LoadoutUI = (session as WavePrototype).loadout if session is WavePrototype else null
	experience_hud.bind_state(state, loadout._attribute_hud if loadout else null, loadout)
	experience_hud.visible = enabled
	experience_collected.connect(experience_hud.pulse)
	choice_ui.allow_cancel = false
	choice_ui.choice_confirmed.connect(_confirm_choice)
	choice_ui.reroll_requested.connect(_reroll_choice)
	session.run_started.connect(_start_run)
	session.run_ended.connect(_end_run)
	session.enemy_defeated_at.connect(drop_experience)
	session.wave_clearing.connect(_clear_wave)
	session.phase_changed.connect(_phase_changed)

func _start_run() -> void:
	prepare_draw()
	_close_choices()
	_clear_drops()
	state.reset()
	active = enabled
	_choice_error = false
	_reset_feedback()

func _end_run(_reason: String) -> void:
	active = false
	_close_choices()
	_clear_drops()
	state.discard_pending_choices()
	_reset_feedback()
	_draft_started = false
	_candidate_pool.clear()
	_previous_draw.clear()
	_draw_pool.clear_followup()

func _phase_changed(phase: int) -> void:
	# 在公共结算通知中的重试/返回回调之前释放自己的界面与输入。
	if phase == session.Phase.RESULT and active: _end_run("")
	if phase == session.Phase.READY and not active:
		state.reset()
		_draft_started = false
		_previous_draw.clear()

func prepare_draw() -> void:
	if _draft_started: return
	_draft_started = true
	rerolls_left = rerolls_per_run
	_draw_pool.reset(draw_seed)
	_previous_draw.clear()

func draw_options(pool: Array[GrowthChoiceOption], count: int, previous: Array[GrowthChoiceOption] = []) -> Array[GrowthChoiceOption]:
	prepare_draw()
	return _draw_pool.draw(pool, count, previous) if _draw_pool.valid_pool(pool) else []

func can_reroll(pool: Array[GrowthChoiceOption], shown: Array[GrowthChoiceOption]) -> bool:
	return rerolls_left > 0 and _draw_pool.can_redraw(pool, shown)

func redraw_options(pool: Array[GrowthChoiceOption], shown: Array[GrowthChoiceOption], count: int) -> Array[GrowthChoiceOption]:
	if not can_reroll(pool, shown): return []
	var result := draw_options(pool, count, shown)
	if not result.is_empty(): rerolls_left -= 1
	return result

func drop_experience(position: Vector3, amount: int) -> void:
	if not active or amount <= 0: return
	if _drops.size() >= max_pickups:
		var nearest := _drops[0]
		for drop in _drops:
			if drop.global_position.distance_squared_to(position) < nearest.global_position.distance_squared_to(position): nearest = drop
		nearest.amount += amount
		return
	var pickup := pickup_scene.instantiate() as ExperiencePickup
	pickup.amount = amount
	add_child(pickup)
	pickup.global_position = session._path.ground_position(position) + Vector3.UP * 0.05
	_drops.append(pickup)

func get_attraction_radius(modifiers: RunCombatModifiers = null) -> float:
	if not modifiers and is_instance_valid(session): modifiers = session.combat_modifiers
	return attraction_radius * modifiers.multiplier(GrowthBuffDefinition.Attribute.PICKUP_RADIUS) if modifiers else attraction_radius

func _physics_process(delta: float) -> void:
	if not active: return
	_try_open_choice()
	if session.combat_frozen: return
	var target: Vector3 = session.player.global_position + Vector3.UP * 0.35
	var pickup_radius := get_attraction_radius()
	for pickup: ExperiencePickup in _drops.duplicate():
		pickup.advance_visual(delta)
		if pickup.advance(delta, target, pickup_radius, collection_radius, height_tolerance, attraction_initial_speed, attraction_acceleration, attraction_max_speed):
			_drops.erase(pickup)
			var amount: int = pickup.amount
			pickup.queue_free()
			_grant_experience(amount)
			if session.combat_frozen: break

func _grant_experience(amount: int) -> void:
	state.add_experience(amount)
	experience_collected.emit(amount)
	if not active: return
	_absorb_left = absorb_duration
	_absorb.global_position = session.player.global_position + Vector3.UP * 0.45
	_absorb.pixel_size = absorb_size / _absorb.texture.get_width()
	_absorb.visible = absorb_duration > 0.0 and absorb_opacity > 0.0
	_absorb.modulate.a = absorb_opacity

func _process(delta: float) -> void:
	if _absorb_left <= 0.0: return
	_absorb_left = maxf(0.0, _absorb_left - delta)
	_absorb.modulate.a = absorb_opacity * _absorb_left / maxf(absorb_duration, 0.001)
	_absorb.visible = _absorb_left > 0.0
	if is_instance_valid(session) and is_instance_valid(session.player):
		_absorb.global_position = session.player.global_position + Vector3.UP * 0.45

func _reset_feedback() -> void:
	_absorb_left = 0.0
	_absorb.hide()
	experience_hud.clear_feedback()

func collect_all() -> void:
	if not active: return
	var amount := 0
	for pickup in _drops: amount += pickup.amount
	_clear_drops()
	if amount > 0: _grant_experience(amount)

func _clear_wave() -> void:
	if collect_remaining_on_clear: collect_all()

func _levels_gained(_count: int) -> void:
	_try_open_choice()

func _try_open_choice() -> void:
	if not active or state.pending_choices <= 0 or choice_ui.is_open or _choice_error: return
	if get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return
	while state.pending_choices > 0:
		_candidate_pool = candidate_provider.call() if candidate_provider.is_valid() else _fallback_options.duplicate()
		if not _draw_pool.valid_pool(_candidate_pool):
			_choice_error = true
			push_error("RunGrowth: 成长池需要有效且 ID 唯一的候选；经验保留，未冻结战斗。")
			session.set_combat_frozen(false)
			return
		if _candidate_pool.any(func(option: GrowthChoiceOption): return option.enabled): break
		var skipped_level := state.next_choice_level()
		state.complete_choice()
		growth_choice_skipped.emit(skipped_level)
		if not active: return
	if state.pending_choices == 0:
		session.set_combat_frozen(false)
		return
	choice_options = draw_options(_candidate_pool, cards_per_draw, _previous_draw)
	_choice_level = state.next_choice_level()
	choice_ui.title = "等级 %d · 成长选择" % _choice_level
	choice_ui.confirm_text = "领取成长"
	choice_ui.choice_hint = "本次领取一张" if state.pending_choices == 1 else "本次领取一张 · 还有 %d 次成长待选" % (state.pending_choices - 1)
	if not choice_ui.present_choices(choice_options):
		_choice_error = true
		push_error("RunGrowth: 需要至少一个有效、可选择且 ID 唯一的成长候选；本轮经验保留，未冻结战斗。")
		session.set_combat_frozen(false)
		return
	session.set_combat_frozen(true)
	_update_draw_status()

func _update_draw_status() -> void:
	choice_ui.set_draw_status(rerolls_left, can_reroll(_candidate_pool, choice_options))

func _reroll_choice() -> void:
	if not active or not choice_ui.is_open or not choice_ui.cards_revealed: return
	var options := redraw_options(_candidate_pool, choice_options, cards_per_draw)
	if options.is_empty(): return
	choice_options = options
	choice_ui.present_choices(choice_options)
	_update_draw_status()

func _confirm_choice(option_id: StringName) -> void:
	if not active or state.pending_choices <= 0: return
	var accepted := false
	for option in choice_options:
		if option and option.enabled and option.id == option_id: accepted = true; break
	if not accepted: _try_open_choice(); return
	var chosen_level := _choice_level
	_draw_pool.record_choice(option_id, choice_options)
	_previous_draw = choice_options.duplicate()
	state.complete_choice()
	growth_chosen.emit(chosen_level, option_id)
	if not active: return
	if state.pending_choices > 0:
		_try_open_choice()
	else:
		session.set_combat_frozen(false)

func refresh_candidates(options: Array[GrowthChoiceOption]) -> void:
	_fallback_options = options.duplicate()
	_choice_error = false
	if choice_ui.is_open: choice_ui.close()
	_try_open_choice()
	if not choice_ui.is_open: session.set_combat_frozen(false)

func _close_choices() -> void:
	choice_ui.close()
	_choice_level = 0
	if is_instance_valid(session): session.set_combat_frozen(false)

func _clear_drops() -> void:
	for pickup in _drops:
		remove_child(pickup)
		pickup.queue_free()
	_drops.clear()

func _exit_tree() -> void:
	active = false
	if is_instance_valid(choice_ui): _close_choices()
