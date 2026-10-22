extends "res://tests/test_preview_query_view.gd"

const TickProbe = preload("res://tests/fixtures/batch_tick_probe.gd")

func add_probe() -> TickProbe:
	var actor := TickProbe.new()
	var definition := WaveEnemyDefinition.new()
	actor.configure_wave({"player":player, "spatial_index":session._spatial_index,
		"navigation":navigation, "attack_root":session._attack_root,
		"damage_player":Callable(), "request_spawn":Callable(),
		"combat_active":session.combat_active}, definition, 0.0)
	session._enemy_roster.register(actor)
	session.add_child(actor)
	if session.centralized_enemy_updates: session._sync_enemy_updates()
	return actor

func run() -> void:
	await fixture()
	check(session.get("centralized_enemy_updates") != null, "Central enemy update switch exists")
	if failures:
		world.queue_free(); await settle(); quit(1); return
	var first := add_probe()
	var second := add_probe()
	session.set("centralized_enemy_updates", true)
	var batch: Node = session.get("_enemy_update_batch")
	check(is_instance_valid(batch) and not first.is_physics_processing() and not second.is_physics_processing(), "One driver replaces per-enemy physics callbacks")
	batch.set_physics_process(false)
	batch.call("advance", 0.1)
	check(first.ticks == 1 and second.ticks == 1, "Every registered actor advances once in original order")
	first.call("set_wave_tick_enabled", false)
	batch.call("advance", 0.1)
	check(first.ticks == 1 and second.ticks == 2, "Explicit suspension works under the central driver")
	first.call("set_wave_tick_enabled", true)
	first.stun_remaining = 0.2
	batch.call("advance", 0.1)
	check(first.stunned_ticks == 1 and is_equal_approx(first.stun_remaining, 0.1), "Central update keeps stun timing and the original stunned action")
	first.stun_remaining = 0.0
	first.during_tick = func(): session.set_combat_frozen(true)
	var old_second := second.ticks
	batch.call("advance", 0.1)
	check(session.combat_frozen and second.ticks == old_second, "Mid-batch upgrade freeze stops remaining actors immediately")
	first.during_tick = Callable()
	session.set_combat_frozen(false)
	second.process_mode = Node.PROCESS_MODE_DISABLED
	batch.call("advance", 0.1)
	check(second.ticks == old_second, "Central update respects disabled process modes")
	second.process_mode = Node.PROCESS_MODE_INHERIT
	first.during_tick = func(): second.take_damage(9999.0)
	batch.call("advance", 0.1)
	check(second.dead and second.ticks == old_second and not session._spatial_index._entries.has(second), "Lethal removal during a batch cannot tick a dead actor or retain its slot")
	first.during_tick = Callable()
	var newborns: Array[WaveEnemy] = []
	first.during_tick = func(): newborns.append(add_probe())
	batch.call("advance", 0.1)
	check(newborns.size() == 1 and newborns[0].get("ticks") == 0, "A birth during iteration cannot extend this pass or invalidate its array")
	first.during_tick = Callable()
	batch.call("advance", 0.1)
	check(newborns[0].get("ticks") == 1, "A newly registered actor advances exactly once in the next pass")
	session.set("centralized_enemy_updates", false)
	check(first.is_physics_processing(), "Disabling central update restores original callbacks")
	first.call("set_wave_tick_enabled", false)
	check(not first.is_physics_processing(), "The same suspension API works with the legacy backend")
	session.set("centralized_enemy_updates", true)
	check(not first.is_physics_processing(), "Switching backends does not resume suspended actors")
	var fallback := WaveEnemy.new()
	fallback.definition = WaveEnemyDefinition.new()
	session._enemy_roster.register(fallback)
	session.add_child(fallback)
	session.call("_sync_enemy_updates")
	check(fallback.is_physics_processing(), "Unregistered custom update contracts retain native callbacks")
	first.call("set_wave_tick_enabled", true)
	var newborn_ticks: int = newborns[0].get("ticks")
	first.during_tick = func(): session._cleanup_attacks()
	batch.call("advance", 0.1)
	check(session.get("_enemy_update_batch") == null and newborns[0].get("ticks") == newborn_ticks, "Mid-step wave cleanup releases references and stops the old generation immediately")
	for actor in session._enemy_roster.take_all(): actor.cancel()
	body.cancel(true)
	world.queue_free()
	await settle()
	print("Enemy update batch: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
