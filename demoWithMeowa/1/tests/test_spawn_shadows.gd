extends SceneTree
## 仅验证图集数据、实例池与真实生成接口，不启动渲染窗口或做截图验收。
const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
const ATLAS := preload("res://scripts/combat/wave_spawn_shadow_atlas.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func settle(count := 3) -> void:
	for frame in count: await physics_frame

func run() -> void:
	var config := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var city := load("res://data/combat/scenes/city/configuration.tres") as SceneCombatConfiguration
	check(config.spawn_shadow_settings and config.spawn_shadow_settings.enabled, "World explicitly enables pre-spawn silhouettes")
	check(not city.spawn_shadow_settings, "City keeps its own immediate spawn configuration")
	check(config.validation_error().is_empty(), "Actual World configuration validates with its new settings")
	var settings := config.spawn_shadow_settings.duplicate() as WaveSpawnShadowSettings
	settings.warning_seconds = NAN
	check(not settings.validation_error().is_empty(), "Invalid warning durations fail data validation")
	settings = config.spawn_shadow_settings.duplicate() as WaveSpawnShadowSettings
	var source := Image.create_empty(3, 3, false, Image.FORMAT_RGBA8)
	source.set_pixel(1, 1, Color(1, 1, 1, 1))
	var mask := ATLAS.bake_mask(source)
	check(mask.get_pixel(3, 3).r == 1 and mask.get_pixel(3, 3).g == 0, "Baked silhouette retains the original opaque pixel")
	check(mask.get_pixel(2, 3).g == 1 and mask.get_pixel(1, 3).a == 0, "Rim is exactly one original pixel with a transparent guard")
	var scenes: Array[PackedScene] = []
	for definition in config.enemy_catalog.enemies: scenes.append(definition.scene)
	var atlas := ATLAS.new()
	check(atlas.prepare(scenes) and atlas.records.size() == 6, "All five main monsters and the split child derive masks from actual Sprite frames")
	var texture_id := atlas.texture.get_instance_id()
	check(not atlas.prepare(scenes) and atlas.texture.get_instance_id() == texture_id, "Repeated run preparation reuses the atlas without reading/rebaking images")
	for scene in scenes:
		check(atlas.records.has(scene) and atlas.records[scene].size.x > 0.0 and atlas.records[scene].size.y > 0.0, "Native pixel dimensions retained: " + scene.resource_path.get_file())
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var effects := WaveSpawnShadows.new()
	world.add_child(effects)
	effects.configure(settings, scenes, Rect2(-16, -16, 32, 32))
	for index in 128: effects.begin(index, scenes[index % scenes.size()], Vector3(index % 16, 0, index / 16), 0.55, 2.0)
	check(effects.get_child_count() == 1 and effects._entries.size() == 128, "128 warnings share one mesh node rather than 128 scene objects")
	check(effects._mesh.multimesh.visible_instance_count == 128, "Pool growth retains all active warnings without dropping effects")
	check(not effects.is_processing() and not effects.is_physics_processing(), "Pool has no independent frame callback")
	check(effects._mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "The silhouette batch does not cast realtime shadows")
	effects.end(0, false)
	check(effects._entries.size() == 127 and effects._slots[127] == 0, "Cancelled slots compact without losing a moved live entry")
	effects.advance(2.55)
	effects.end(127, true)
	check(effects._entries.size() == 127 and is_equal_approx(effects._entries[0].data.b, 2.55), "Birth releases a short tail on the combat clock")
	effects.advance(2.68)
	check(effects._entries.size() == 126, "Only expired tails are removed")
	effects.clear()
	check(effects._entries.is_empty() and effects._mesh.multimesh.visible_instance_count == 0 and not effects.visible, "Clear hides all instances and keeps reusable allocations")
	effects.free()
	# Minimal terrain fixture exercises actual position checks, actors and lifecycle.
	var terrain := Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-11, -11), Vector2i(22, 22))
	terrain.data = data
	world.add_child(terrain)
	var wave := SESSION.new()
	wave.name = "WavePrototype"
	wave.terrain = terrain
	wave.battle_area = Rect2(-16, -16, 32, 32)
	wave.spawn_shadow_settings = settings
	wave.default_enemy = config.default_enemy
	wave.enemy_catalog = config.enemy_catalog
	wave.max_active_enemies = 3
	world.add_child(wave)
	wave.phase = WavePrototype.Phase.BATTLE
	wave.wave = 1
	wave._attack_root = Node3D.new()
	wave.add_child(wave._attack_root)
	var player := Player.new()
	player.name = "Player"
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.1
	collider.shape = capsule
	collider.position.y = 0.55
	player.add_child(collider)
	wave.player = player
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await settle()
	wave._path.build(terrain, 0.32, [player.get_rid()])
	wave._path_ready = true
	wave._prepare_spawn_shadows()
	check(wave.queue_spawn(config.default_enemy, 1, 0.0, Vector3(7, 0, 0)), "Real wave API registers the spawn before any actor exists")
	wave._physics_process(0.01)
	check(wave.enemies.is_empty() and wave._pending == 1 and wave._spawn_shadows._entries.size() == 1, "A due job shows a silhouette with no damageable/AI actor")
	var point: Vector3 = wave._spawn_queue[0].spawn_point
	check(not wave._valid_spawn(point, wave._spawn_queue[0].enemy, wave._ground_target(), true), "Reserved silhouettes exclude overlapping new spawn points")
	var clock: float = wave._wave_clock
	wave.set_combat_frozen(true)
	wave._physics_process(1.0)
	check(wave._wave_clock == clock and wave._spawn_shadows._clock == clock, "Upgrade freeze stops both queue and shader clock")
	wave.set_combat_frozen(false)
	wave._physics_process(0.56)
	check(wave.enemies.size() == 1 and wave._pending == 0, "The warning creates exactly one real actor when it completes")
	if not wave.enemies.is_empty():
		var enemy := wave.enemies[0]
		enemy.set_physics_process(false)
		check(enemy.global_position.is_equal_approx(point + Vector3.UP * 0.03), "The actual actor uses the exact warned point")
		check(enemy.spawn_delay == 0.0 and enemy.health == enemy.max_health and enemy.get_node("Sprite").modulate.a == 1.0, "New actors enter immediately at full health/opacity without a second warning wait")
		wave._enemy_roster.remove(enemy)
		enemy.cancel()
	await settle()
	wave._physics_process(0.13)
	# Empty wave just cleared; resume a fixture battle for invalidation/cleanup.
	wave.phase = WavePrototype.Phase.BATTLE
	wave._attack_root = Node3D.new()
	wave.add_child(wave._attack_root)
	check(wave.queue_spawn(config.default_enemy, 1, 0, Vector3(-7, 0, 0)), "A second real warning can be queued")
	wave._physics_process(0.01)
	point = wave._spawn_queue[0].spawn_point
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 3, 1.5)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.position = point + Vector3.UP * 1.5
	await settle()
	wave._physics_process(0.56)
	check(wave.enemies.is_empty() and wave._pending == 1 and wave._spawn_shadows._entries.is_empty(), "A new real wall cancels the stale silhouette instead of relocating an unannounced actor")
	wall.queue_free()
	await settle()
	wave._physics_process(0.31)
	check(wave._spawn_state.prepared_jobs.size() == 1 and wave.enemies.is_empty(), "Unblocked retry shows a new warning before spawning")
	wave._finish("fixture cleanup")
	check(wave._spawn_shadows._entries.is_empty() and wave._spawn_state.prepared_jobs.is_empty() and wave._pending == 0, "Ending/retrying clears visual tails and all reserved positions")
	world.queue_free()
	await settle()
	print(JSON.stringify({"suite":"spawn_shadows", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
