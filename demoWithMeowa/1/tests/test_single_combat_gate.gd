extends SceneTree

const Probe = preload("res://tests/fixtures/combat_gate_probe.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var gate_calls := 0
var player: Player
var wave: WavePrototype
var actor: Variant
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		push_error(text)

func live_gate() -> bool:
	gate_calls += 1
	return wave.combat_active()

func sample(label: String, enabled: bool, expected: bool) -> void:
	actor.legacy_outer_gate = not enabled
	var previous: int=actor.combat_ticks
	gate_calls=0
	actor._physics_process(1.0/60.0)
	var advanced: bool=actor.combat_ticks==previous+1
	var wanted_calls:=1 if enabled or not expected else 2
	check(advanced==expected and gate_calls==wanted_calls, "%s mode=%s: live eligibility advances once; no stale callback result" % [label,enabled])
	rows.append({"case":label,"single_gate":enabled,"expected":expected,"advanced":advanced,"predicate_calls":gate_calls})

func run() -> void:
	var world:=Node3D.new()
	root.add_child(world)
	current_scene=world
	player=Player.new()
	var sprite:=Sprite3D.new()
	sprite.name="Sprite"
	player.add_child(sprite)
	var collision:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.24
	capsule.height=1.06592
	collision.shape=capsule
	collision.position.y=capsule.height*.5
	player.add_child(collision)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position=Vector3.ZERO
	wave=WavePrototype.new()
	wave.player=player
	wave.battle_area=Rect2(-2,-2,4,4)
	wave.phase=WavePrototype.Phase.BATTLE
	var definition: WaveMeleeEnemyDefinition=load("res://data/enemies/leaf_charger.tres")
	actor=definition.scene.instantiate() as CreatureEnemy
	actor.set_script(Probe)
	actor.configure_wave({"player":player,"navigation":null,"attack_root":world,"terrain":null,"camera":null,"damage_player":Callable(),"request_spawn":Callable(),"combat_active":live_gate},definition,0.0)
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	var actual:=actor.get_node("Collision") as CollisionShape3D
	var initial=[actual.shape.get_instance_id(),actual.shape.radius,actual.shape.height,actual.transform,actor.collision_layer,actor.collision_mask]
	var start_health:=player.current_health
	for enabled in [false,true]:
		wave.player=player
		wave.phase=WavePrototype.Phase.BATTLE
		wave.combat_frozen=false
		player.current_health=start_health
		player.global_position=Vector3.ZERO
		sample("active",enabled,true)
		wave.combat_frozen=true
		sample("freeze_same_engine_frame",enabled,false)
		wave.combat_frozen=false
		sample("unfreeze_same_engine_frame",enabled,true)
		wave.phase=WavePrototype.Phase.REST
		sample("phase_rest_same_engine_frame",enabled,false)
		wave.phase=WavePrototype.Phase.BATTLE
		sample("phase_battle_same_engine_frame",enabled,true)
		player.current_health=0
		sample("dead_player_same_engine_frame",enabled,false)
		player.current_health=start_health
		player.global_position=Vector3(3,0,0)
		sample("player_leaves_same_engine_frame",enabled,false)
		player.global_position=Vector3.ZERO
		sample("player_returns_same_engine_frame",enabled,true)
		wave.battle_area=Rect2(10,10,2,2)
		sample("area_changed_same_engine_frame",enabled,false)
		wave.battle_area=Rect2(-2,-2,4,4)
		wave._generation+=1
		sample("new_generation_live",enabled,true)
		wave.player=null
		sample("player_reference_removed_live",enabled,false)
	check(initial==[actual.shape.get_instance_id(),actual.shape.radius,actual.shape.height,actual.transform,actor.collision_layer,actor.collision_mask],"Actual shapes/transforms/masks remain untouched")
	var report={"checks":checks,"failures":failures,"rows":rows,"engine":Engine.get_version_info(),"backend":ProjectSettings.get_setting("physics/3d/physics_engine"),"purpose":"Callback gate functional proof only; no cached eligibility and no timing claim"}
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	wave.free()
	world.queue_free()
	print("Single combat gate: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
