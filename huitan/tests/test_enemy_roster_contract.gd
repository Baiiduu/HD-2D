extends SceneTree
const PATH := "res://scripts/combat/wave_enemy_roster.gd"
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func run() -> void:
	check(ResourceLoader.exists(PATH), "Enemy lifecycle bookkeeping is independent from the wave controller")
	if not ResourceLoader.exists(PATH): quit(1); return
	var roster = load(PATH).new()
	var data := WaveEnemyDefinition.new()
	data.population_cost = 3
	data.role = WaveEnemyDefinition.Role.SPECIAL
	var enemy := WaveEnemy.new()
	enemy.definition = data
	check(roster.register(enemy) and not roster.register(enemy), "Duplicate registration cannot double population cost")
	check(roster.enemies.size() == 1 and roster.cost == 3 and roster.by_role[1] == 1 and roster.by_definition[data] == 1, "Registration updates all capacity counters together")
	check(roster.remove(enemy) and not roster.remove(enemy), "Repeated death and exit callbacks release an actor once")
	check(roster.cost == 0 and roster.by_role[1] == 0 and roster.by_definition.get(data, 0) == 0, "Removal releases all capacity counters together")
	roster.register(enemy)
	data.population_cost = 8
	check(roster.remove(enemy) and roster.cost == 0, "Removal pays back the cost captured at registration")
	data.population_cost = 3
	roster.register(enemy)
	var remaining = roster.take_all()
	check(remaining == [enemy] and roster.enemies.is_empty() and roster.cost == 0 and roster.by_role == PackedInt32Array([0, 0, 0, 0]), "Run cleanup detaches all actors before cancellation callbacks")
	check(not roster.remove(enemy), "Late exit callbacks cannot change a cleared roster")
	var population := WavePopulationRules.new()
	population.max_population_cost = 6
	population.role_limits = PackedInt32Array([8, 2, 8, 8])
	roster.register(enemy)
	check(roster.can_fit(data, 1, 8, population, {}), "Available cost and role capacity admit another actor")
	check(not roster.can_fit(data, 2, 8, population, {}), "Population cost and role limits cannot be oversubscribed")
	data.max_alive = 1
	check(not roster.can_fit(data, 1, 8, population, {}), "Per-definition capacity remains independent from the total active limit")
	data.max_alive = 0
	var members: Array[WaveEnemyDefinition] = [data]
	var batch: Dictionary = preload("res://scripts/combat/wave_spawn_queue.gd").make_batch(members, 1)
	check(not roster.can_fit(data, 1, 8, population, batch), "An unrelated spawn cannot steal a reserved batch slot or cost")
	check(roster.can_fit(data, 1, 8, population, batch, batch), "A batch member consumes its own reservation instead of counting it twice")
	check(roster.can_fit_batch(batch, 8, population) and not roster.can_fit_batch(batch, 1, population), "Whole-batch admission honors the active capacity")
	roster.take_all()
	enemy.free()
	print(JSON.stringify({"suite":"enemy_roster_contract", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
