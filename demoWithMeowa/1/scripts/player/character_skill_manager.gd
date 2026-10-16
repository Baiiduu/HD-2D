class_name CharacterSkillManager
extends Node
## 角色固有技能。只持有弹射和 Dash 的运行开关与输入，不依赖波次、抽卡或学习等级。

signal skills_changed
signal skill_registered(skill_id: StringName, component: Node)
signal skill_unregistered(skill_id: StringName)

const BODY_RICOCHET: StringName = &"body_ricochet"
const DASH: StringName = &"dash"

@export_group("角色固有技能连接")
@export var body_ricochet: PlayerRicochet
@export var dash: PlayerBlink

var combat_frozen := false
var _components: Dictionary[StringName, Node] = {}
var _configured_enabled: Dictionary[StringName, bool] = {}
var _enabled: Dictionary[StringName, bool] = {}

func configure(ricochet_enabled: bool, dash_enabled: bool) -> void:
	register_skill(BODY_RICOCHET, body_ricochet, ricochet_enabled)
	register_skill(DASH, dash, dash_enabled)

func register_skill(id: StringName, component: Node, configured_enabled: bool) -> bool:
	if id not in [BODY_RICOCHET, DASH] or not is_instance_valid(component): return false
	if _components.has(id): return _components[id] == component
	_components[id] = component
	_configured_enabled[id] = configured_enabled
	_enabled[id] = configured_enabled
	component.tree_exiting.connect(_remove_component.bind(id, component), CONNECT_ONE_SHOT)
	skill_registered.emit(id, component)
	return true

func _remove_component(id: StringName, component: Node) -> void:
	if _components.get(id) == component: _detach(id)

func unregister_skill(id: StringName) -> void:
	var component := get_skill(id)
	if not is_instance_valid(component): return
	_cancel(id, component)
	_detach(id)

func _detach(id: StringName) -> void:
	_components.erase(id)
	_configured_enabled.erase(id)
	_enabled.erase(id)
	skill_unregistered.emit(id)
	skills_changed.emit()

func get_skill(id: StringName) -> Node:
	return _components.get(id)

func get_registered_ids() -> Array[StringName]:
	return _components.keys()

func is_skill_enabled(id: StringName) -> bool:
	return is_instance_valid(get_skill(id)) and _enabled.get(id, false)

func set_skill_enabled(id: StringName, enabled: bool) -> bool:
	var component := get_skill(id)
	if not is_instance_valid(component): return false
	_enabled[id] = enabled
	if not enabled: _cancel(id, component)
	skills_changed.emit()
	return true

func set_combat_frozen(value: bool) -> void:
	combat_frozen = value

func begin_charge(direction: Vector3) -> bool:
	return not combat_frozen and is_skill_enabled(BODY_RICOCHET) and get_skill(BODY_RICOCHET).begin_charge(direction)

func aim_charge(direction: Vector3) -> void:
	if not combat_frozen and is_skill_enabled(BODY_RICOCHET): get_skill(BODY_RICOCHET).aim(direction)

func release_charge() -> bool:
	return not combat_frozen and is_skill_enabled(BODY_RICOCHET) and get_skill(BODY_RICOCHET).release_charge()

func request_dash(direction: Vector3) -> void:
	if not combat_frozen and is_skill_enabled(DASH): get_skill(DASH).request(direction)

func cancel_actions() -> void:
	for id in _components: _cancel(id, _components[id])

func _cancel(id: StringName, component: Node) -> void:
	if id == BODY_RICOCHET: component.cancel(true)
	else: component.cancel()

func reset() -> void:
	cancel_actions()
	_enabled = _configured_enabled.duplicate()
	skills_changed.emit()

func _exit_tree() -> void:
	_components.clear()
	_enabled.clear()
	_configured_enabled.clear()
