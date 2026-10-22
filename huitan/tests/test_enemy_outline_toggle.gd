extends SceneTree

const LIGHTING := preload("res://scripts/rendering/character_lighting.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func settle() -> void:
	for frame in 3: await process_frame

func wave_checks() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	for frame in 16: await physics_frame
	var wave: WavePrototype = world.get_node("WavePrototype")
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	check(not wave.enemy_occlusion_outline_enabled, "正式地图统一关闭波次怪物轮廓")
	var player_flag: bool = wave.player.sprite.get("occlusion_outline_enabled")
	wave.player.global_position = wave.global_position + Vector3.UP * 0.03
	check(wave.start_run(), "正式地图可正常开局")
	var choice: GrowthChoiceUI = wave.get_node("SkillDraft/InitialSkillChoice")
	if choice.is_open:
		choice.reveal_now()
		choice.select_option(choice._options[0].id)
		choice.confirm_selection()
	for component: Node in (wave.get_node("RunSkillManager") as RunSkillManager)._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED
	wave._spawn_queue.clear()
	check(wave.phase == WavePrototype.Phase.BATTLE, "实际进入战斗验证出怪")
	for definition in wave.enemy_catalog.enemies:
		var spawned := wave._spawn_enemy(definition)
		check(spawned, "正式怪物正常出场：%s" % definition.enemy_id)
		if not spawned: continue
		var enemy := wave.enemies[-1]
		enemy.set_physics_process(false)
		var sprite := enemy.get_node("Sprite")
		check(not sprite.has_node("OcclusionOutline"), "统一关闭时新怪不建立轮廓：%s" % definition.enemy_id)
	wave.enemy_occlusion_outline_enabled = true
	check(wave.enemies.all(func(enemy: WaveEnemy): return enemy.get_node("Sprite/OcclusionOutline").visible), "统一开启立即作用于现有六种怪物")
	var local := wave.enemies[0].get_node("Sprite")
	local.set("occlusion_outline_enabled", false)
	wave.enemy_occlusion_outline_enabled = false
	wave.enemy_occlusion_outline_enabled = true
	check(not local.get_node("OcclusionOutline").visible and not local.get("occlusion_outline_enabled"), "统一开启不覆盖单只 Sprite 的关闭选择")
	wave.enemy_occlusion_outline_enabled = false
	check(wave.enemies.all(func(enemy: WaveEnemy): return not enemy.get_node("Sprite/OcclusionOutline").visible), "统一关闭立即隐藏现有全部怪物")
	check(wave._spawn_enemy(), "关闭后继续生成新怪")
	wave.enemies[-1].set_physics_process(false)
	check(not wave.enemies[-1].has_node("Sprite/OcclusionOutline"), "后续生成的怪物也保持关闭")
	var pot: WaveEnemy
	for enemy in wave.enemies:
		if enemy.definition.enemy_id == &"pot_brood": pot = enemy
	if pot:
		pot.spawn_delay = 0.0
		pot.take_damage(pot.max_health + 1.0)
		wave._physics_process(1.0)
		var children := wave.enemies.filter(func(enemy: WaveEnemy): return enemy.definition.enemy_id == &"mini_slime")
		check(children.size() == 3, "死亡分裂仍真实生成两只幼体")
		check(children.all(func(enemy: WaveEnemy): return not enemy.has_node("Sprite/OcclusionOutline") or not enemy.get_node("Sprite/OcclusionOutline").visible), "分裂幼体同样受统一关闭控制")
	check(wave.player.sprite.get("occlusion_outline_enabled") == player_flag, "怪物总开关不修改玩家轮廓")
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var parameters := catalog.collect(world)
	check(parameters.any(func(item: Dictionary): return item.property == "enemy_occlusion_outline_enabled" and item.category == "战斗与成长" and item.common), "参数总览提供常用的波次怪物统一开关")
	catalog.entries.clear()
	wave._finish("outline toggle test")
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	await create_timer(0.1).timeout
	world.queue_free()
	await settle()
	await create_timer(0.1).timeout

func run() -> void:
	var frames: SpriteFrames = load("res://assets/meowa/slime/animations.tres")
	for shared in [false, true]:
		var sprite: Sprite3D = LIGHTING.new()
		sprite.texture = frames.get_frame_texture(&"idle_front", 0)
		sprite.set("shared_materials", shared)
		root.add_child(sprite)
		await settle()
		var outline: MeshInstance3D = sprite.get_node("OcclusionOutline")
		check(outline.visible, "开启时正常建立轮廓")
		# @tool 脚本重载会保留已有辅助节点，脚本内节点引用却可能重新初始化。
		sprite.set("_outline", null)
		sprite.set("occlusion_outline_enabled", false)
		await settle()
		check(not outline.visible, "关闭必须隐藏引用重建前已存在的轮廓，共享=%s" % shared)
		sprite.texture = frames.get_frame_texture(&"hop_front_right", 2)
		sprite.flip_h = true
		sprite.call("apply_lighting")
		await settle()
		check(not outline.visible, "关闭后换帧、镜像和重新应用受光不能恢复轮廓")
		sprite.set("occlusion_outline_enabled", true)
		await settle()
		check(outline.visible and sprite.get_node("OcclusionOutline") == outline, "重新开启复用原节点且只保留一个轮廓")
		sprite.set("occlusion_outline_width", 0.0)
		sprite.set("_outline", null)
		await settle()
		check(not outline.visible, "零宽度同样隐藏已有轮廓")
		sprite.set("occlusion_outline_width", 1.0)
		sprite.set("occlusion_outline_opacity", 0.0)
		sprite.set("_outline", null)
		await settle()
		check(not outline.visible, "零透明度同样隐藏已有轮廓")
		sprite.queue_free()
		await settle()
	await wave_checks()
	print("Enemy outline toggle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
