extends "res://tests/test_run_skill_manager_contract.gd"
## 技能插画沿真实开局／升级数据链传递；不渲染或评价视觉观感。

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var empty := CombatSkillDefinition.new()
	check("illustration" in empty, "Skill definitions expose an independent card illustration")
	if not "illustration" in empty:
		finish()
		return
	for skill_id in [&"ricochet_storm", &"prism_ricochet"]:
		await check_skill(skill_id)
	finish()

func check_skill(skill_id: StringName) -> void:
	var definition: CombatSkillDefinition = load("res://data/combat/scenes/world/skills/%s.tres" % skill_id)
	var art := definition.get("illustration") as Texture2D
	check(art != null, "World %s uses the approved illustration" % skill_id)
	check(load("res://data/combat/scenes/city/skills/%s.tres" % skill_id).get("illustration") == null, "City retains its original icon presentation: %s" % skill_id)
	var session := SessionFixture.new()
	session.add_child(session.player)
	var growth: RunGrowth = load("res://scenes/growth/run_growth.tscn").instantiate()
	growth.name = "RunGrowth"
	growth.session = session
	session.add_child(growth)
	var manager := RunSkillManager.new()
	var skill := SkillFixture.new()
	skill.name = "Skill"
	skill.definition = definition
	session.add_child(skill)
	manager.skill_paths.append(NodePath("../Skill"))
	session.add_child(manager)
	var draft := RunSkillDraft.new()
	draft.session = session
	draft.manager = manager
	draft.growth = growth
	var choice: GrowthChoiceUI = load("res://scenes/ui/growth_choice_ui.tscn").instantiate()
	choice.name = "InitialSkillChoice"
	choice.ink_style = true
	choice.open_duration = 0.0
	choice.hover_duration = 0.0
	choice.get_node("UIAudio").enabled = false
	draft.add_child(choice)
	draft.initial_choice = choice
	session.add_child(draft)
	root.add_child(session)
	growth.choice_ui.get_node("UIAudio").enabled = false
	growth.set_physics_process(false)
	var learn := manager.candidates()[0]
	check(art != null and learn.illustration == art and learn.icon == definition.icon, "Learning cards carry art without replacing skill-bar icons")
	check(draft.present_initial_choice(), "Initial selection still opens")
	check(draft._initial_pool[0].illustration == art, "Initial draw retains the skill illustration")
	var card: GrowthChoiceCard = choice._cards[0]
	var icon := card.get_node("IconSlot/Icon") as TextureRect
	var blend := icon.material as ShaderMaterial
	check(icon.texture == art and blend != null, "The real initial card displays the illustration with its own material")
	check(card.get_node_or_null("ArtBacking") == null and card.get_node("IconSlot").texture == null, "Ink artwork has no separate dark backing or socket frame")
	if blend:
		check(blend.get_shader_parameter("blend_edges") == true, "Only revealed illustration cards enable edge blending")
	card.set_revealed(false)
	check(icon.texture == card.BACK_ICON and (not blend or blend.get_shader_parameter("blend_edges") == false), "Concealed cards do not reveal the illustration")
	card.set_revealed(true)
	card.configure(learn, 0.96, 1.0, 0.0, 20, Color.WHITE, false)
	check(icon.texture == definition.icon and (not blend or blend.get_shader_parameter("blend_edges") == false), "Legacy cards retain their icon without illustration blending")
	choice.cancel()
	check(manager.set_skill_level(definition.id, 1), "Skill can still be learned")
	var upgrade := manager.candidates()[0]
	check(upgrade.illustration == art and upgrade.icon == definition.icon, "Upgrades retain the same approved illustration and HUD icon")
	session.free()
	await process_frame

func finish() -> void:
	print(JSON.stringify({"suite":"skill_card_illustration", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
