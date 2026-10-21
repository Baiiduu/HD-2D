class_name RunSkillManager
extends Node
## 局内可选技能：学习等级、有效候选、临时启停和模拟装配；不持有人物固有技能或输入。

signal skills_changed
signal choice_pool_changed
signal skill_upgraded(skill_id: StringName, level: int)
signal skill_registered(skill_id: StringName, component: Node)
signal skill_unregistered(skill_id: StringName)

const SYSTEMS := preload("res://scripts/core/game_system_settings.gd")
@export_group("系统开关")
## 本地开关；编辑器 Game Manager 的项目开关也须开启。
@export var enabled := true:
	set(value):
		if enabled == value: return
		enabled = value
		if is_node_ready(): _sync_enabled()

@export_group("本局技能连接")
## 可学习的技能组件，相对于本节点；新局全部未学习，不读取永久存档。
@export var skill_paths: Array[NodePath] = []

var _components: Dictionary[StringName, Node] = {}
## 配置只读；运行启停、学习资格与学习等级各自独立。
var _available: Dictionary[StringName, bool] = {}
var _levels: Dictionary[StringName, int] = {}
var _offered: Dictionary[StringName, Dictionary] = {}
var _simulation_enabled: Dictionary[StringName, bool] = {}
var _simulation_available: Dictionary[StringName, bool] = {}
var _project_enabled := true
var _suspended_enabled: Dictionary[StringName, Variant] = {}

func _enter_tree() -> void:
	_project_enabled = SYSTEMS.is_enabled(SYSTEMS.RUN_SKILLS)

func is_enabled() -> bool:
	return enabled and _project_enabled

func _apply_system_to_component(id: StringName) -> void:
	var component := get_skill(id)
	if not is_enabled():
		if not _suspended_enabled.has(id): _suspended_enabled[id] = component.get("enabled")
		if component.get("enabled") != null: component.set("enabled", false)
		component.apply_skill_level(0)
	elif _suspended_enabled.has(id):
		if _suspended_enabled[id] != null: component.set("enabled", _suspended_enabled[id])
		_suspended_enabled.erase(id)
		component.apply_skill_level(get_level(id))

func _sync_enabled() -> void:
	for id in _components: _apply_system_to_component(id)
	_invalidate_choices()
	_notify()

func _ready() -> void:
	for path in skill_paths: register_skill(get_node_or_null(path))
	reset()

## 新技能只实现定义、等级应用与升级说明；注册后共用学习、成长、冻结和清理。
func register_skill(component: Node) -> bool:
	if not is_instance_valid(component) or not component.has_method("get_skill_definition") or not component.has_method("apply_skill_level") or not component.has_method("describe_skill_upgrade"):
		push_error("RunSkillManager: 技能组件需要定义、等级应用与升级说明接口")
		return false
	var definition: CombatSkillDefinition = component.get_skill_definition()
	if not definition or definition.id.is_empty() or definition.id in [&"body_ricochet", &"dash", &"basic_sword", &"blink"] or definition.levels.is_empty() or definition.levels.has(null):
		push_error("RunSkillManager: 技能定义需要唯一 ID 与有效等级配置")
		return false
	if _components.get(definition.id) == component: return true
	if not _register(definition.id, component): return false
	var enabled: Variant = component.get("enabled")
	_available[definition.id] = enabled == null or enabled == true
	if is_node_ready():
		component.apply_skill_level(0)
		_levels[definition.id] = 0
		_apply_system_to_component(definition.id)
		_invalidate_choices()
		_notify()
	skill_registered.emit(definition.id, component)
	return true

func _register(id: StringName, component: Node) -> bool:
	if _components.has(id):
		if _components[id] == component: return true
		push_error("RunSkillManager: 重复技能 ID：%s" % id)
		return false
	_components[id] = component
	var cleanup := _remove_component.bind(id, component)
	if not component.tree_exiting.is_connected(cleanup):
		component.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
	return true

func _remove_component(id: StringName, component: Node) -> void:
	if _components.get(id) == component: _detach_skill(id)

func unregister_skill(id: StringName) -> void:
	_detach_skill(id)

func _detach_skill(id: StringName) -> void:
	var component := get_skill(id)
	if not component: return
	if _components.has(id):
		component.apply_skill_level(0)
		if _simulation_enabled.has(id): component.set("enabled", _simulation_enabled[id])
		elif _suspended_enabled.has(id) and _suspended_enabled[id] != null:
			component.set("enabled", _suspended_enabled[id])
	_available.erase(id)
	_components.erase(id)
	_levels.erase(id)
	_simulation_enabled.erase(id)
	_simulation_available.erase(id)
	_suspended_enabled.erase(id)
	_invalidate_choices()
	skill_unregistered.emit(id)
	if is_node_ready() and not is_queued_for_deletion(): _notify()

func _invalidate_choices() -> void:
	_offered.clear()
	choice_pool_changed.emit()

func get_skill(id: StringName) -> Node:
	return _components.get(id)

func get_registered_ids() -> Array[StringName]:
	return _components.keys()

func is_skill_enabled(id: StringName) -> bool:
	if not is_enabled(): return false
	var component := get_skill(id)
	if not is_instance_valid(component): return false
	var enabled: Variant = component.get("enabled")
	return enabled == null or enabled == true

func set_skill_enabled(id: StringName, enabled: bool) -> bool:
	if not is_enabled(): return false
	var component := get_skill(id)
	if not is_instance_valid(component): return false
	if component.get("enabled") == null: return false
	component.set("enabled", enabled)
	if not enabled and component.has_method("cancel_current"): component.cancel_current()
	_notify()
	return true

func is_skill_available(id: StringName) -> bool:
	return is_enabled() and _components.has(id) and _available.get(id, false)

## 改变本局学习资格；临时禁招只用 set_skill_enabled，不改变抽卡内容。
func set_skill_available(id: StringName, available: bool) -> bool:
	if not _components.has(id): return false
	if _available.get(id) == available: return true
	_available[id] = available
	if is_enabled(): set_skill_enabled(id, available)
	elif _suspended_enabled.has(id): _suspended_enabled[id] = available
	_invalidate_choices()
	return true

func is_registered(component: Node) -> bool:
	return component in _components.values()

func get_attack_stats(modifiers: RunCombatModifiers = null) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for id in _components:
		var component := get_skill(id)
		if not is_skill_enabled(id): continue
		if component.has_method("get_combat_stat_variants"):
			values.append_array(component.get_combat_stat_variants(modifiers))
		elif component.has_method("get_combat_stats"):
			var stats: Dictionary = component.get_combat_stats(modifiers)
			if not stats.is_empty(): values.append(stats)
	return values

## 仅管理局内学习等级；角色固有技能不属于此注册表。
func set_skill_level(id: StringName, level: int) -> bool:
	if not _components.has(id) or level < 0: return false
	if level > 0 and not is_skill_available(id): return false
	var definition: CombatSkillDefinition = _components[id].get_skill_definition()
	if level > definition.levels.size() or not _components[id].apply_skill_level(level): return false
	var previous := get_level(id)
	_levels[id] = level
	_invalidate_choices()
	if level > previous: skill_upgraded.emit(id, level)
	_notify()
	return true

func reset() -> void:
	_suspended_enabled.clear()
	for id in _simulation_available: _available[id] = _simulation_available[id]
	_simulation_available.clear()
	for id in _simulation_enabled:
		_components[id].enabled = _simulation_enabled[id]
	_simulation_enabled.clear()
	_levels.clear()
	for id in _components:
		if _components[id].get("enabled") != null: _components[id].enabled = _available.get(id, false)
		if _components[id].apply_skill_level(0): _levels[id] = 0
	_sync_enabled()

func has_learned_skill() -> bool:
	return _levels.values().any(func(level: int): return level > 0)

func has_simulation_loadout() -> bool:
	return not _simulation_enabled.is_empty()

func simulation_loadout_error(entries: Array[SimulationSkillEntry]) -> String:
	for entry in entries:
		var id := entry.skill_definition.id
		if not _components.has(id): return "模拟技能未接入当前场景：" + entry.skill_definition.display_name
		var definition: CombatSkillDefinition = _components[id].get_skill_definition()
		if entry.skill_level > definition.levels.size(): return "模拟技能等级超出当前组件范围：" + definition.display_name
	return ""

func apply_simulation_loadout(entries: Array[SimulationSkillEntry]) -> bool:
	if not is_enabled(): return false
	if not simulation_loadout_error(entries).is_empty(): return false
	reset()
	for entry in entries:
		if entry.skill_level == 0: continue
		var id := entry.skill_definition.id
		_simulation_enabled[id] = _components[id].enabled
		_simulation_available[id] = _available[id]
		_available[id] = true
		_components[id].enabled = true
		if not _components[id].apply_skill_level(entry.skill_level):
			reset()
			return false
		_levels[id] = entry.skill_level
	_notify()
	return true

func get_level(skill_id: StringName) -> int:
	return _levels.get(skill_id, 0)

## 后续更多技能沿用这个候选接口；已满级的技能不会再占用卡片。
func candidates() -> Array[GrowthChoiceOption]:
	_offered.clear()
	var result: Array[GrowthChoiceOption] = []
	if not is_enabled(): return result
	for id in _levels:
		if not is_skill_available(id): continue
		var definition: CombatSkillDefinition = _components[id].get_skill_definition()
		var level := get_level(id)
		if level >= definition.levels.size(): continue
		var option := GrowthChoiceOption.new()
		option.id = StringName("skill:%s:%d" % [id, level + 1])
		option.title = "%s\nLv.1" % definition.display_name if level == 0 else "%s\nLv.%d → Lv.%d" % [definition.display_name, level, level + 1]
		option.description = _components[id].describe_skill_upgrade(level, level + 1)
		option.icon = definition.icon
		option.illustration = definition.illustration
		option.category = GrowthChoiceOption.Category.LEARN_SKILL if level == 0 else GrowthChoiceOption.Category.UPGRADE_SKILL
		_offered[option.id] = {"skill": id, "from": level, "to": level + 1}
		result.append(option)
	return result

func apply_upgrade_choice(option_id: StringName) -> bool:
	if not _offered.has(option_id): return false
	var selection := _offered[option_id]
	var id: StringName = selection.skill
	return get_level(id) == selection.from and set_skill_level(id, selection.to)

func get_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_enabled(): return result
	for id in _levels:
		var definition: CombatSkillDefinition = _components[id].get_skill_definition()
		var level := get_level(id)
		if level <= 0: continue
		result.append({"id": String(id), "name": definition.display_name, "icon": definition.icon,
			"level": level, "max_level": definition.levels.size(), "description": definition.level_data(level).description})
	return result

func _notify() -> void:
	skills_changed.emit()

func _exit_tree() -> void:
	_suspended_enabled.clear()
	_available.clear()
	_components.clear()
	_levels.clear()
	_simulation_enabled.clear()
	_simulation_available.clear()
