extends "res://tests/test_player_sword.gd"

const MIRROR := preload("res://scripts/combat/mirror_reflection_surface.gd")

class CountField extends StaticObstacleField:
	var proofs := 0
	var attempts := 0
	func clear_ray(from: Vector3, to: Vector3, mask: int, excluded: Array[RID]) -> bool:
		attempts += 1
		var clear := super.clear_ray(from, to, mask, excluded)
		if clear: proofs += 1
		return clear

func native_clear(from: Vector3, to: Vector3, mask: int, excluded: Array[RID]) -> bool:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask, excluded)).is_empty()

func manual_checks() -> void:
	var thin := box(Vector3(4,0.8,-4), Vector3(0.023,1.6,3))
	var angled := box(Vector3(-4,0.8,-4), Vector3(3,1.6,0.025))
	angled.rotation.y = PI * 0.25
	await settle()
	var field := CountField.new()
	field.source = terrain
	terrain._obstacle_field = field
	terrain.add_child(field)
	check(field._static.has(thin) and is_instance_valid(field._support), "ray proof shares the fixed raster and retains an observed physical floor")
	var excluded: Array[RID] = [player.get_rid()]
	var positive := 0
	for mask in [1, ProjectileCollision.REFLECTION_MASK]:
		for x in range(-6,7,2):
			for z in range(-6,7,2):
				var from := Vector3(x + 0.071,0.45,z - 0.133)
				var to := from + Vector3(1.33,0.07,-0.77)
				var reference := native_clear(from, to, mask, excluded)
				if field.clear_ray(from, to, mask, excluded):
					positive += 1
					check(reference, "every shared positive agrees with the original native ray")
				check(terrain.ray_clear(from, to, mask, excluded) == reference, "proof plus exact fallback preserves native visibility")
	check(positive > 30, "native ray oracle covers a useful set of empty-space samples")
	var from := Vector3(2,0.45,-4)
	var to := Vector3(6,0.45,-4)
	check(not terrain.ray_clear(from, to, 1, excluded), "shared rays cannot cross a sub-cell thin fixed wall")
	check(not field.clear_ray(Vector3(0,0.45,4), Vector3(0,-1,4), 1, excluded), "rays crossing the omitted raster floor cannot be certified")
	check(not terrain.ray_clear(Vector3(0,0.45,4), Vector3(0,-1,4), 1, excluded), "floor-crossing fallback retains actual native ground hits")
	(thin.get_child(0) as CollisionShape3D).shape.margin += 0.01
	await settle(1)
	terrain.ray_clear(Vector3(0,0.45,4), Vector3(1,0.45,4), 1, excluded)
	check(not field._static.has(thin), "unknown static margin edits are detected before an empty proof next step")
	thin.position.x = 7
	thin.force_update_transform()
	check(terrain.ray_clear(from, to, 1, excluded), "moved fixed wall is read live in the same step")
	var late := box(Vector3(3,0.8,4), Vector3(0.02,1.6,2))
	late.force_update_transform()
	from = Vector3(2,0.45,4)
	to = Vector3(4,0.45,4)
	check(not terrain.ray_clear(from, to, 1, excluded), "late wall blocks a previously empty segment in the same step")
	check(terrain.ray_clear(from, to, 1, [player.get_rid(),late.get_rid()]), "dynamic exclusion semantics are retained")
	late.collision_layer = 4
	check(terrain.ray_clear(from, to, 1, excluded) and not terrain.ray_clear(from, to, 5, excluded), "live mask switches preserve mirror-only blocking")
	late.free()
	thin.free()
	angled.free()
	await reset()
	var victim := enemy(Vector3(1,0,0))
	var before := field.proofs
	check(sword._can_reach(player.global_position, victim) and field.proofs > before, "actual basic sword reachability consumes the shared positive")
	var storm := RicochetStorm.new()
	storm.session = session
	storm.enabled = false
	world.add_child(storm)
	before = field.proofs
	check(storm._clear_path(player.global_position, victim.global_position) and field.proofs > before, "actual storm propagation consumes the same shared positive")
	enemy(Vector3(1.55,0,0.45))
	enemy(Vector3(1.55,0,-0.45))
	var settings := PlayerRicochetRules.new()
	settings.eccentric_enabled = true
	var steering := PlayerCrowdDeflection.new(settings, session)
	before = field.proofs
	var outline := steering._eccentric_outline(victim, player.global_position)
	check(not outline.is_empty() and field.proofs > before, "actual orbit membership and connected edges consume shared positives")
	terrain.obstacle_certificates_enabled = false
	check(steering._eccentric_outline(victim, player.global_position) == outline, "orbit member order, bounds and geometry match native-only queries")
	check(sword._can_reach(player.global_position, victim) and storm._clear_path(player.global_position, victim.global_position), "native-only switch preserves sword and storm reachability")
	terrain.obstacle_certificates_enabled = true
	var mirror := MIRROR.new()
	world.add_child(mirror)
	mirror.attach(victim, Vector3.LEFT, Vector2(1,1), 0.45)
	from = player.global_position + Vector3.UP * 0.45
	to = victim.global_position + Vector3.UP * 0.45
	check(not steering._ray_clear(from, to) and not terrain.ray_clear(from, to, 5, excluded), "actual attached mirror blocks orbit capture/continuation rays")
	check(sword._can_reach(player.global_position, victim) and storm._clear_path(player.global_position, victim.global_position), "mirror remains transparent to ordinary sword and storm queries")
	mirror.stop()
	check(steering._ray_clear(from, to), "same-step mirror removal restores visibility")
	mirror.free()
	storm.free()
	# Base Shape.margin lacks a changed signal; the very next ray must revoke it.
	var floor_shape := terrain.ground_collision_body().get_child(0) as CollisionShape3D
	floor_shape.shape.margin += 0.01
	check(terrain.ray_clear(from, to, 1, excluded) == native_clear(from, to, 1, excluded), "uncertain floor retains exact native ray fallback")
	check(not is_instance_valid(field._support), "floor margin edits revoke its cached 3D bound before the next same-step proof")
	print("ATTACK_RAY_CLEARANCE positives=", positive, "; shared proofs consumed=", field.proofs)
	await super.manual_checks()
