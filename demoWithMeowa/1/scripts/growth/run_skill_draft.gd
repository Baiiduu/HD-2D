class_name RunSkillDraft
extends Node
## 本局抽卡与技能核心之间的连接；地图、UI 和波次依赖不进入 RunSkillManager。

const SYSTEMS := preload("res://scripts/core/game_system_settings.gd")
@export_group("系统开关")
## 本地抽卡开关；不关闭经验积累、已学技能或固有技能。
@export var enabled := true:
	set(value):
		if enabled == value: return
		enabled = value
		if is_node_ready(): _sync_enabled()

@export_group("本局技能抽卡连接")
@export var session: Node3D
@export var manager: RunSkillManager
@export var growth: RunGrowth
@export var buffs: RunBuffs
@export var initial_choice: GrowthChoiceUI
@export_range(1, 6, 1) var initial_cards_per_draw := 3

var _initial_offered: Dictionary[StringName, StringName] = {}
var _initial_pool: Array[GrowthChoiceOption] = []
var _initial_cards: Array[GrowthChoiceOption] = []
var _combat_components: Dictionary[StringName, Node] = {}
var _connections: Array[Dictionary] = []
var _project_enabled := true

func _enter_tree() -> void:
	_project_enabled = SYSTEMS.is_enabled(SYSTEMS.DRAFT)

func is_enabled() -> bool:
	return enabled and _project_enabled

func _sync_enabled() -> void:
	if not is_enabled(): _clear_initial()
	growth.set_draft_enabled(is_enabled())

func should_offer_initial_choice() -> bool:
	if not is_enabled() or not manager.is_enabled() or manager.has_learned_skill(): return false
	return manager.get_registered_ids().any(func(id: StringName): return manager.is_skill_available(id))

func _ready() -> void:
	assert(session and manager and growth, "RunSkillDraft 需要明确连接 session、manager 和 growth")
	growth.candidate_provider = candidates
	_connect(growth.growth_chosen, _choose)
	_connect(session.run_ended, _end_run)
	_connect(session.phase_changed, _phase_changed)
	_connect(manager.choice_pool_changed, _invalidate_choices)
	_connect(manager.skills_changed, _notify)
	_connect(manager.skill_registered, _register_component)
	_connect(manager.skill_unregistered, _unregister_component)
	for id in manager.get_registered_ids(): _register_component(id, manager.get_skill(id))
	if initial_choice:
		_connect(initial_choice.choice_confirmed, _choose_initial)
		_connect(initial_choice.reroll_requested, _reroll_initial)
	_sync_enabled()

func _connect(source: Signal, callback: Callable) -> void:
	if source.is_connected(callback): return
	source.connect(callback)
	_connections.append({"source": source, "callback": callback})

func _register_component(id: StringName, component: Node) -> void:
	_combat_components[id] = component
	if session.has_method("register_combat_node"): session.register_combat_node(component)

func _unregister_component(id: StringName) -> void:
	var component := _combat_components.get(id) as Node
	if is_instance_valid(component) and session.has_method("unregister_combat_node"):
		session.unregister_combat_node(component)
	_combat_components.erase(id)

func _clear_initial() -> void:
	_initial_offered.clear()
	_initial_pool.clear()
	_initial_cards.clear()
	if is_instance_valid(initial_choice) and initial_choice.is_open: initial_choice.close()

func _invalidate_choices() -> void:
	_clear_initial()
	_refresh_growth_choices.call_deferred()

func _refresh_growth_choices() -> void:
	if not is_inside_tree() or not is_instance_valid(growth) or not growth.active: return
	if growth.state.pending_choices > 0: growth.refresh_candidates(candidates())

func _end_run(_reason: String) -> void:
	_clear_initial()

func _phase_changed(phase: int) -> void:
	if phase == session.Phase.READY or (phase == session.Phase.RESULT and manager.has_simulation_loadout()):
		manager.reset()
	else:
		_clear_initial()

## 选完才请求真正开局，不花费经验、不提前刷怪或播放战斗音效。
func present_initial_choice() -> bool:
	if not is_enabled() or not manager.is_enabled() or session.phase != session.Phase.READY or not initial_choice or initial_choice.is_open or manager.has_learned_skill(): return false
	# 取消再打开保留原牌与共用重抽次数。
	if _initial_cards.is_empty():
		_initial_pool.clear()
		_initial_offered.clear()
		for id in manager.get_registered_ids():
			if not manager.is_skill_available(id): continue
			var component := manager.get_skill(id)
			var definition: CombatSkillDefinition = component.get_skill_definition()
			var option := GrowthChoiceOption.new()
			option.id = StringName("initial:%s" % id)
			option.title = "%s\nLv.1" % definition.display_name
			option.description = component.describe_skill_upgrade(0, 1)
			option.icon = definition.icon
			option.category = GrowthChoiceOption.Category.LEARN_SKILL
			_initial_offered[option.id] = id
			_initial_pool.append(option)
		_initial_cards = growth.draw_options(_initial_pool, initial_cards_per_draw)
	initial_choice.title = "初始技能 · 抽卡选择"
	initial_choice.choice_hint = "学习一张技能，确认后开始战斗 · Esc 返回"
	var opened := initial_choice.present_choices(_initial_cards)
	if opened: initial_choice.set_draw_status(growth.rerolls_left, growth.can_reroll(_initial_pool, _initial_cards))
	return opened

func _reroll_initial() -> void:
	if not is_enabled() or not manager.is_enabled() or not initial_choice.is_open or not initial_choice.cards_revealed or manager.has_learned_skill(): return
	var options := growth.redraw_options(_initial_pool, _initial_cards, initial_cards_per_draw)
	if options.is_empty(): return
	_initial_cards = options
	initial_choice.present_choices(_initial_cards)
	initial_choice.set_draw_status(growth.rerolls_left, growth.can_reroll(_initial_pool, _initial_cards))

func _choose_initial(option_id: StringName) -> void:
	if not is_enabled() or not manager.is_enabled() or not _initial_offered.has(option_id) or not _initial_cards.any(func(option: GrowthChoiceOption): return option.id == option_id) or manager.has_learned_skill() or not session.can_start_run(): return
	var id := _initial_offered[option_id]
	_initial_offered.clear()
	if not manager.set_skill_level(id, 1): return
	if not session.start_run(): manager.reset()

func candidates() -> Array[GrowthChoiceOption]:
	if not is_enabled(): return []
	var result := manager.candidates()
	if buffs: result.append_array(buffs.candidates())
	return result

func _choose(_player_level: int, option_id: StringName) -> void:
	if is_enabled() and growth.active: manager.apply_upgrade_choice(option_id)

func _notify() -> void:
	if is_instance_valid(session): session.changed.emit()

func _exit_tree() -> void:
	for connection in _connections:
		var source: Signal = connection.source
		if not source.is_null() and source.is_connected(connection.callback): source.disconnect(connection.callback)
	_connections.clear()
	if is_instance_valid(growth) and growth.candidate_provider == candidates: growth.candidate_provider = Callable()
	for id in _combat_components.keys(): _unregister_component(id)
	_clear_initial()
