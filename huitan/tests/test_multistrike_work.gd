extends "res://tests/test_player_sword.gd"
## Exact contact/order oracle and bounded work for a dense eight-slash attack.
const REFERENCE = preload("res://tests/fixtures/unfiltered_sword_sweep.gd")
class CountedSword extends PlayerSword:
	var checks := 0
	func _eligible(actor: WaveEnemy) -> bool:
		checks += 1
		return super._eligible(actor)
class CountedReference extends "res://tests/fixtures/unfiltered_sword_sweep.gd":
	var checks := 0
	func _eligible(actor: WaveEnemy) -> bool:
		checks += 1
		return super._eligible(actor)

func collector(script: GDScript, heading: Vector3, reverse: bool) -> PlayerSword:
	var value: PlayerSword = script.new()
	value.player = player
	value.session = session
	value.rules = sword.rules
	value._settings = sword._settings
	value._stats = sword._stats.duplicate()
	value._path = session._path
	value._heading = heading
	value._reverse = reverse
	value._flight_swing = true
	value._age = 0.0
	return value

func contacts(value: PlayerSword) -> PackedByteArray:
	var result := []
	for contact in value._pending_hits:
		var hit: Dictionary = contact.duplicate()
		hit.enemy = hit.enemy.get_instance_id()
		hit.erase("attack_snapshot")
		hit.erase("score_batch")
		result.append(hit)
	return var_to_bytes([value._hits.keys(), result])

func manual_checks() -> void:
	await reset()
	sword.rules = sword.rules.duplicate()
	sword.rules.flight_angle = 360.0
	session.growth_rules = RunGrowthRules.new()
	session.combat_modifiers.growth_rules = session.growth_rules
	for rank in 7: session.combat_modifiers.apply_buff(load("res://data/combat/scenes/world/growth/epic/multistrike.tres"))
	player.body_ricochet.state = PlayerRicochet.State.FLYING
	player.body_ricochet.flight_speed = 16.0
	for index in 128:
		var angle := TAU * float(index % 16) / 16.0
		var radius := 0.28 + float(index / 16) * 0.16
		enemy(Vector3(cos(angle), 0.0, sin(angle)) * radius, 100000.0)
	sword._begin(Vector3.RIGHT, true, 16.0)
	check(sword._strike_total == 8, "The dense fixture exercises the actual eight-slash cap")
	var total_old := 0
	var total_new := 0
	for reverse in [false, true]:
		for angle in [120.0, 360.0]:
			for travel in [Vector3.ZERO, Vector3(0.23, 0.0, -0.19)]:
				for heading in [Vector3.RIGHT, Vector3(0.4, 0.0, -1.0).normalized()]:
					var current := collector(CountedSword, heading, reverse) as CountedSword
					var old := collector(CountedReference, heading, reverse) as CountedReference
					for value in [current, old]:
						value._stats.angle = angle
						value._collect_hits(player.global_position, player.global_position + travel, 0.0, 1.0, true, 0.0, 0.1, 12.0, 0.5)
					check(contacts(current) == contacts(old), "Conservative filtering preserves exact targets, order, contact time, velocity and blade direction")
					total_old += old.checks
					total_new += current.checks
					current.free()
					old.free()
	check(total_new < total_old * 0.65, "Narrow blade slices reject distant candidates before repeated eligibility and geometry work")
	print(JSON.stringify({"dense_sweep_eligibility": {"before":total_old, "after":total_new}}))
	await reset()
	for index in 16: enemy(Vector3(0.6, 0.0, 0.0).rotated(Vector3.UP, TAU * index / 16.0), 10000.0)
	session.combat_modifiers._bonuses[GrowthBuffDefinition.Attribute.MULTISTRIKE] = 7.0
	player.body_ricochet.state = PlayerRicochet.State.FLYING
	player.body_ricochet.flight_speed = 16.0
	sword._begin(Vector3.RIGHT, true, 16.0)
	var duration := sword._settings.duration() * sword._strike_total
	sword._simulate(player.global_position, player.global_position, duration, true, Vector3.RIGHT)
	var expected := sword._pending_hits.duplicate()
	var observed := []
	var listener := func(actor, _amount, _flying):
		observed.append(actor)
		if observed.size() == 3: session.set_combat_frozen(true)
	sword.hit_landed.connect(listener)
	sword._drain_hits()
	check(observed.size() == 3 and sword._pending_hits.size() == expected.size() - 3, "Freeze retains exactly the unconsumed prefix in the original order")
	sword._drain_hits()
	check(observed.size() == 3, "Frozen queues cannot replay a consumed hit")
	session.set_combat_frozen(false)
	sword._drain_hits()
	check(observed.size() == expected.size() and sword._pending_hits.is_empty(), "Resume drains every remaining real slash once")
	for index in observed.size(): check(observed[index] == expected[index].enemy, "Batched draining preserves hit order")
	sword.hit_landed.disconnect(listener)
	var after_cancel := []
	var cancellation := func(actor, _amount, _flying):
		after_cancel.append(actor)
		if after_cancel.size() == 1:
			sword.cancel(false)
			sword._pending_hits.append(expected[-1])
	sword._pending_hits.assign(expected.slice(0, 4))
	sword.hit_landed.connect(cancellation)
	sword._drain_hits()
	sword._drain_hits()
	check(after_cancel.size() == 2 and after_cancel[-1] == expected[-1].enemy and sword._pending_hits.is_empty(), "Cancel discards old contacts without erasing a newly enqueued attack or replaying it")
	sword.hit_landed.disconnect(cancellation)
	await reset()

func attack_speed_checks() -> void: pass
func flight_checks() -> void: pass
func freeze_checks() -> void: pass
func input_and_art_checks() -> void: pass
func score_checks() -> void: pass
