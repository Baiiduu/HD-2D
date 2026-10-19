@tool
extends Node
## 必须位于 Player 和 WavePrototype 之前；进入树时绑定，早于战斗组件的 _ready。
@export var configuration: SceneCombatConfiguration

func _enter_tree() -> void:
	if Engine.is_editor_hint() or not configuration: return
	var scene := get_parent()
	var player := scene.get_node("Player") as Player
	var wave := scene.get_node("WavePrototype") as WavePrototype
	wave.configuration_error = configuration.validation_error()
	if not wave.configuration_error.is_empty(): return
	_bind_player(configuration, player)
	_bind_skills(configuration, wave.run_skill_manager)
	player.crowd_clearance_distance = configuration.crowd_clearance_distance
	for property in ["enemy_catalog", "default_enemy", "population_rules", "health_growth_rules", "spawn_shadow_settings", "waves", "endless_mode", "max_active_enemies", "centralized_enemy_updates", "native_swarm_enabled", "batch_crowd_enabled", "native_chase_enabled", "slime_ground_movement_enabled"]:
		wave.set(property, configuration.get(property))
	var growth := wave.get_node("RunGrowth") as RunGrowth
	growth.rules = configuration.experience_rules
	growth.cards_per_draw = configuration.cards_per_draw
	growth.rerolls_per_run = configuration.rerolls_per_run
	wave.get_node("RunBuffs").definitions = configuration.growth_definitions
	wave.get_node("DamageNumbers").number_styles = configuration.number_styles

func _bind_player(config: SceneCombatConfiguration, player: Player) -> void:
	player.ricochet_rules = config.ricochet_rules
	player.sword_rules = config.sword_rules
	player.action_visuals = config.action_visuals
	player.flight_trail_settings = config.flight_trail_settings
	if player.movement_camera is FollowCamera:
		player.movement_camera.ricochet_camera_settings = config.ricochet_camera_settings

func _bind_skills(config: SceneCombatConfiguration, manager: RunSkillManager) -> void:
	for path in manager.skill_paths:
		var component := manager.get_node_or_null(path)
		if not component or not component.has_method("get_skill_definition"): continue
		var definition: CombatSkillDefinition = component.get_skill_definition()
		if not definition: continue
		for configured in config.skill_definitions:
			if configured and configured.id == definition.id:
				component.set("skill_definition", configured)
				break
		if definition.id == &"ricochet_storm":
			for property in ["damage", "attack_interval", "trigger_radius", "spread_radius", "max_propagation_radius", "spread_layers", "targets_per_layer", "layer_interval"]:
				component.set(property, config.get("storm_" + property))
