class_name RunSkills
extends Node

signal skills_changed
signal skill_upgraded(skill_id: StringName, level: int)

@export_group("本局技能连接")
@export var session: Node3D
## 可学习的技能组件，相对于本节点；新局全部未学习，不读取永久存档。
@export var skill_paths: Array[NodePath] = []
@export_range(1, 6, 1) var initial_cards_per_draw := 3

var _components: Dictionary[StringName, Node] = {}
var _levels: Dictionary[StringName, int] = {}
var _offered: Dictionary[StringName, Dictionary] = {}
var _growth: RunGrowth
var _initial_offered: Dictionary[StringName, StringName] = {}
var _initial_pool: Array[GrowthChoiceOption] = []
var _initial_cards: Array[GrowthChoiceOption] = []
@onready var initial_choice: GrowthChoiceUI = get_node_or_null("InitialSkillChoice")

func _ready() -> void:
	_growth = session.get_node("RunGrowth") as RunGrowth
	for path in skill_paths:
		var component := get_node_or_null(path)
		if not component or not component.has_method("get_skill_definition") or not component.has_method("apply_skill_level") or not component.has_method("describe_skill_upgrade"):
			push_error("RunSkills: 技能组件需要定义、等级应用与升级说明接口：%s" % path)
			continue
		var definition: CombatSkillDefinition = component.get_skill_definition()
		if not definition or definition.id.is_empty() or definition.levels.is_empty() or _components.has(definition.id) or definition.levels.has(null):
			push_error("RunSkills: 技能定义需要唯一 ID 与有效等级配置：%s" % path)
			continue
		_components[definition.id] = component
	_growth.candidate_provider = candidates
	_growth.growth_chosen.connect(_choose)
	session.run_ended.connect(func(_reason: String): _offered.clear())
	session.phase_changed.connect(_phase_changed)
	if initial_choice:
		initial_choice.choice_confirmed.connect(_choose_initial)
		initial_choice.reroll_requested.connect(_reroll_initial)
	reset()

func reset() -> void:
	_offered.clear()
	_initial_offered.clear()
	_initial_pool.clear()
	_initial_cards.clear()
	if initial_choice: initial_choice.close()
	_levels.clear()
	for id in _components:
		if _components[id].apply_skill_level(0): _levels[id] = 0
	_notify()

func _phase_changed(phase: int) -> void:
	if phase == session.Phase.READY: reset()
	elif initial_choice:
		initial_choice.close()
		_initial_offered.clear()
		_initial_pool.clear()
		_initial_cards.clear()

func has_learned_skill() -> bool:
	return _levels.values().any(func(level: int): return level > 0)

## 选完才调用真正的开局，不花费经验、不提前刷怪或播放战斗音效。
func present_initial_choice() -> bool:
	if session.phase != session.Phase.READY or not initial_choice or initial_choice.is_open or has_learned_skill(): return false
	# Cancelling and reopening keeps the same draw and shared reroll budget.
	if _initial_cards.is_empty():
		_initial_pool.clear()
		_initial_offered.clear()
		for id in _components:
			var definition: CombatSkillDefinition = _components[id].get_skill_definition()
			var option := GrowthChoiceOption.new()
			option.id = StringName("initial:%s" % id)
			option.title = "%s\nLv.1" % definition.display_name
			option.description = _components[id].describe_skill_upgrade(0, 1)
			option.icon = definition.icon
			option.category = GrowthChoiceOption.Category.LEARN_SKILL
			_initial_offered[option.id] = id
			_initial_pool.append(option)
		_initial_cards = _growth.draw_options(_initial_pool, initial_cards_per_draw)
	initial_choice.title = "初始技能 · 抽卡选择"
	initial_choice.choice_hint = "学习一张技能，确认后开始战斗 · Esc 返回"
	var opened := initial_choice.present_choices(_initial_cards)
	if opened: initial_choice.set_draw_status(_growth.rerolls_left, _growth.can_reroll(_initial_pool, _initial_cards))
	return opened

func _reroll_initial() -> void:
	if not initial_choice.is_open or not initial_choice.cards_revealed or has_learned_skill(): return
	var options := _growth.redraw_options(_initial_pool, _initial_cards, initial_cards_per_draw)
	if options.is_empty(): return
	_initial_cards = options
	initial_choice.present_choices(_initial_cards)
	initial_choice.set_draw_status(_growth.rerolls_left, _growth.can_reroll(_initial_pool, _initial_cards))

func _choose_initial(option_id: StringName) -> void:
	if not _initial_offered.has(option_id) or not _initial_cards.any(func(option: GrowthChoiceOption): return option.id == option_id) or has_learned_skill() or not session.can_start_run(): return
	var id := _initial_offered[option_id]
	_initial_offered.clear()
	if not _components[id].apply_skill_level(1): return
	_levels[id] = 1
	skill_upgraded.emit(id, 1)
	_notify()
	if not session.start_run(): reset()

func get_level(skill_id: StringName) -> int:
	return _levels.get(skill_id, 0)

## 后续更多技能沿用这个候选接口；已满级的技能不会再占用卡片。
func candidates() -> Array[GrowthChoiceOption]:
	_offered.clear()
	var result: Array[GrowthChoiceOption] = []
	for id in _levels:
		var definition: CombatSkillDefinition = _components[id].get_skill_definition()
		var level := get_level(id)
		if level >= definition.levels.size(): continue
		var option := GrowthChoiceOption.new()
		option.id = StringName("skill:%s:%d" % [id, level + 1])
		option.title = "%s\nLv.1" % definition.display_name if level == 0 else "%s\nLv.%d → Lv.%d" % [definition.display_name, level, level + 1]
		option.description = _components[id].describe_skill_upgrade(level, level + 1)
		option.icon = definition.icon
		option.category = GrowthChoiceOption.Category.LEARN_SKILL if level == 0 else GrowthChoiceOption.Category.UPGRADE_SKILL
		_offered[option.id] = {"skill": id, "from": level, "to": level + 1}
		result.append(option)
	var buffs := session.get_node_or_null("RunBuffs") as RunBuffs
	if buffs: result.append_array(buffs.candidates())
	return result

func _choose(_player_level: int, option_id: StringName) -> void:
	if not _growth.active or not _offered.has(option_id): return
	var selection := _offered[option_id]
	var id: StringName = selection.skill
	if get_level(id) != selection.from or not _components[id].apply_skill_level(selection.to): return
	_levels[id] = selection.to
	_offered.clear()
	skill_upgraded.emit(id, selection.to)
	_notify()

func get_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _levels:
		var definition: CombatSkillDefinition = _components[id].get_skill_definition()
		var level := get_level(id)
		if level <= 0: continue
		result.append({"id": String(id), "name": definition.display_name, "icon": definition.icon,
			"level": level, "max_level": definition.levels.size(), "description": definition.level_data(level).description})
	return result

func _notify() -> void:
	skills_changed.emit()
	session.changed.emit()

func _exit_tree() -> void:
	if is_instance_valid(_growth): _growth.candidate_provider = Callable()
