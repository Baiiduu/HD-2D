extends SceneTree
const SETTINGS := preload("res://scripts/core/game_system_settings.gd")
var checks := 0
var failures: Array[String] = []
var scene: Node3D
var wave: WavePrototype
var growth: RunGrowth
var manager: RunSkillManager
var draft: RunSkillDraft

func _initialize() -> void:
	create_timer(75.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func frames(count := 3) -> void:
	for index in count: await physics_frame

func load_scene(path: String, disabled: StringName = &"") -> void:
	for system in SETTINGS.SYSTEMS: ProjectSettings.set_setting(SETTINGS.key(system.id), system.id != disabled)
	scene = load(path).instantiate()
	scene.get_node("LoadoutUI").save_enabled = false
	scene.get_node("MapEffects/BGM").music_enabled = false
	scene.get_node("MapEffects/Weather").rain_audio_enabled = false
	scene.get_node("MapEffects/Weather").wind_audio_enabled = false
	scene.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	# 这里只验证系统状态与选卡规则；不启动异步 UI 播放，音频由专用回归覆盖。
	for audio in scene.find_children("UIAudio", "", true, false): audio.enabled = false
	root.add_child(scene)
	await frames(12)
	wave = scene.get_node("WavePrototype")
	growth = wave.get_node("RunGrowth")
	manager = wave.run_skill_manager
	draft = wave.skill_draft
	wave.set_physics_process(false)
	growth.set_physics_process(false)
	wave.player.set_physics_process(false)
	wave.player.global_position = wave.global_position + Vector3.UP * 0.03
	check(scene.get_node_or_null("GameManager") == null, "The Game Manager remains an editor tool, never a map node")

func release_scene() -> void:
	scene.free()
	await frames(3)

func grant_level() -> void:
	growth._grant_experience(growth.rules.required_for(growth.state.level))

func run() -> void:
	await load_scene("res://scenes/world/world.tscn", SETTINGS.DRAFT)
	check(wave.start_run() and wave.phase == WavePrototype.Phase.BATTLE and not draft.initial_choice.is_open, "Project draw disable starts World combat directly")
	check(growth.active and manager.is_enabled(), "Draw disable leaves upgrading and skill execution independent")
	grant_level()
	check(growth.state.level == 2 and growth.state.pending_choices == 1 and not growth.choice_ui.is_open and not wave.combat_frozen, "Levels accumulate without cards or combat freeze while drawing is disabled")
	check(not draft.present_initial_choice() and not growth.can_reroll([], []), "Direct draw requests cannot bypass the project switch")
	await release_scene()
	await load_scene("res://scenes/city/city.tscn", SETTINGS.UPGRADES)
	check(wave.start_run() and draft.initial_choice.is_open, "Project upgrade disable still permits the independent initial draft")
	draft.initial_choice.reveal_now()
	draft.initial_choice.select_option(draft._initial_cards[0].id)
	draft.initial_choice.confirm_selection()
	check(wave.phase == WavePrototype.Phase.BATTLE and not growth.active and not growth.experience_hud.visible, "City combat runs with experience upgrading disabled")
	grant_level()
	check(growth.state.level == 1 and growth.state.pending_choices == 0, "Disabled upgrading rejects direct experience grants")
	check(wave.player.skill_manager.get_registered_ids().size() == 2 and wave.player.sword.enabled, "Project systems never disable innate abilities or basic sword")
	await release_scene()
	await load_scene("res://scenes/world/world.tscn", SETTINGS.RUN_SKILLS)
	check(wave.start_run() and wave.phase == WavePrototype.Phase.BATTLE and not draft.initial_choice.is_open, "Disabled skill management cannot trap battle start behind an empty initial draft")
	check(not manager.is_enabled() and manager.candidates().is_empty() and growth.active, "Project skill disable preserves independent experience upgrading")
	grant_level()
	check(growth.choice_ui.is_open and wave.combat_frozen and growth.choice_options.all(func(option): return not String(option.id).begins_with("skill:")), "Attribute growth still draws valid cards without learnable skills")
	draft.enabled = false
	check(not growth.choice_ui.is_open and not wave.combat_frozen and growth.state.pending_choices == 1, "Local draw disable closes its UI and releases freeze while retaining the earned choice")
	draft.enabled = true
	check(growth.choice_ui.is_open and wave.combat_frozen, "Re-enabling drawing resumes the pending choice")
	growth.enabled = false
	check(not growth.active and not growth.choice_ui.is_open and not wave.combat_frozen, "Local upgrade disable releases an open upgrade choice safely")
	growth.enabled = true
	check(growth.active and growth.choice_ui.is_open and growth.state.pending_choices == 1, "Re-enabling upgrading retains earned progress without auto-awarding a card")
	await release_scene()
	await load_scene("res://scenes/city/city.tscn")
	draft.enabled = false
	check(wave.start_run() and wave.phase == WavePrototype.Phase.BATTLE, "The local draw switch independently bypasses initial selection")
	grant_level()
	check(growth.state.pending_choices == 1 and not wave.combat_frozen, "The local draw switch also gates subsequent level choices")
	draft.enabled = true
	check(growth.choice_ui.is_open, "The local draw switch can resume its pending level choice")
	manager.enabled = false
	await frames(2)
	check(growth.choice_ui.is_open and growth.choice_options.all(func(option): return not String(option.id).begins_with("skill:")), "Disabling the skill manager refreshes an already-open card pool without stale skill rewards")
	await release_scene()
	for system in SETTINGS.SYSTEMS: ProjectSettings.set_setting(SETTINGS.key(system.id), true)
	print(JSON.stringify({"suite":"game_system_scene", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
