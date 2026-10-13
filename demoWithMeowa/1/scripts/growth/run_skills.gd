class_name RunSkills
extends Node

signal skills_changed
signal skill_upgraded(skill_id: StringName, level: int)

@export_group("本局技能连接")
@export var session: Node3D
## 当前出战自带的技能组件，相对于本节点；不读取旧学习目录或永久存档。
@export var skill_paths: Array[NodePath] = []

var _components: Dictionary[StringName, Node] = {}
var _levels: Dictionary[StringName, int] = {}
var _offered: Dictionary[StringName, Dictionary] = {}
var _growth: RunGrowth

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
	session.run_started.connect(reset)
	session.run_ended.connect(func(_reason: String): _offered.clear())
	session.phase_changed.connect(_phase_changed)
	reset()

func reset() -> void:
	_offered.clear()
	_levels.clear()
	for id in _components:
		if _components[id].apply_skill_level(1): _levels[id] = 1
	_notify()

func _phase_changed(phase: int) -> void:
	if phase == session.Phase.READY: reset()

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
		option.title = "%s  Lv.%d → %d" % [definition.display_name, level, level + 1]
		option.description = _components[id].describe_skill_upgrade(level, level + 1)
		option.icon = definition.icon
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
		result.append({"id": String(id), "name": definition.display_name, "icon": definition.icon,
			"level": level, "max_level": definition.levels.size(), "description": definition.level_data(level).description})
	return result

func _notify() -> void:
	skills_changed.emit()
	session.changed.emit()

func _exit_tree() -> void:
	if is_instance_valid(_growth): _growth.candidate_provider = Callable()
