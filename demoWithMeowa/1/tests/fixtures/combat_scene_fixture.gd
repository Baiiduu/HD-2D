extends RefCounted
## 只修改实例化的测试场景；不写回地图文件或场景独立配置资源。

static func isolate_profile(scene: Node) -> SceneCombatConfiguration:
	var binding := scene.get_node("BattleConfiguration")
	var profile := binding.configuration.duplicate() as SceneCombatConfiguration
	binding.configuration = profile
	return profile

static func clear_placed_obstacles(scene: Node) -> void:
	var details := scene.get_node_or_null("WorldDetails")
	if details:
		scene.remove_child(details)
		details.free()
	for child in scene.get_children():
		if child is TreePlanter or child is PlazaProp:
			scene.remove_child(child)
			child.free()

static func enable_legacy_skills(scene: Node) -> void:
	# 正式池关闭的旧武器仅在验证组合接口的夹具中显式启用。
	for path in ["WavePrototype/FanAutoAttack", "WavePrototype/LightPierceAutoAttack"]:
		scene.get_node(path).enabled = true
