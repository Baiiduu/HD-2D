extends SceneTree

## Instrument the real update bodies in memory; the legacy prefix is the oracle
## for the changed assignments. Animation and pose logic execute unchanged.
const LIGHTING := preload("res://scripts/rendering/character_lighting.gd")
const LEGACY_SLIME := """func _process(delta: float) -> void:
	if wave_mode:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		sprite.scale = _sprite_scale * (warning_scale if spawn_delay > 0.0 else 1.0)
		sprite.modulate = _sprite_color * (1.8 if _hit_flash > 0.0 else 1.0)
		sprite.modulate.a = _sprite_color.a
"""
const LEGACY_CREATURE := """func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	sprite.modulate = _sprite_color * (1.8 if _hit_flash > 0.0 else 1.0)
	sprite.modulate.a = _sprite_color.a * (0.4 if spawn_delay > 0.0 else 1.0)
"""
const PROBE_METHODS := """
var probe_color_writes := 0
var probe_color_changes := 0
var probe_scale_writes := 0
var probe_alphas: Array[float] = []
func _enter_tree() -> void:
	pass
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
func _probe_color(value: Color) -> void:
	probe_color_writes += 1
	if sprite.modulate != value: probe_color_changes += 1
	probe_alphas.append(value.a)
	sprite.modulate = value
func _probe_alpha(value: float) -> void:
	var color := sprite.modulate
	color.a = value
	_probe_color(color)
func _probe_scale(value: Vector3) -> void:
	probe_scale_writes += 1
	sprite.scale = value
func reset_probe() -> void:
	probe_color_writes = 0
	probe_color_changes = 0
	probe_scale_writes = 0
	probe_alphas.clear()
	sprite.set("local_changes", 0)
"""
const SPRITE_PROBE := """extends "res://scripts/rendering/character_lighting.gd"
var local_changes := 0
func _ready() -> void:
	set_notify_local_transform(true)
	super._ready()
	set_process(false)
func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED: local_changes += 1
"""
var checks := 0
var failures := 0
var world: Node3D
var camera: Camera3D
var sprite_probe: GDScript
var scripts: Array[GDScript] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func update_body(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("func _process(delta: float) -> void:")
	var end := text.find("\nfunc ", start + 1)
	return text.substr(start, -1 if end < 0 else end - start)

func instrument(body: String) -> String:
	var result := PackedStringArray()
	for line in body.split("\n"):
		var replaced := false
		for pair in [["sprite.modulate.a = ", "_probe_alpha"], ["sprite.modulate = ", "_probe_color"], ["sprite.scale = ", "_probe_scale"]]:
			var at := line.find(pair[0])
			if at >= 0:
				result.append(line.substr(0, at) + pair[1] + "(" + line.substr(at + pair[0].length()) + ")")
				replaced = true
				break
		if not replaced: result.append(line)
	return "\n".join(result)

func make_script(base: String, body: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends \"" + base + "\"\n" + PROBE_METHODS + "\n" + instrument(body)
	check(script.reload() == OK, "instrumented visual update compiles: " + base.get_file())
	scripts.append(script)
	return script

func make_actor(script: GDScript, frames: SpriteFrames, texture: Texture2D) -> SlimeEnemy:
	var actor := script.new() as SlimeEnemy
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.set_script(sprite_probe)
	sprite.set("shared_materials", true)
	sprite.set("occlusion_outline_enabled", false)
	sprite.texture = texture
	actor.add_child(sprite)
	actor.animations = frames
	actor.camera = camera
	actor.wave_mode = true
	actor._sprite_scale = Vector3(0.8, 0.9, 1.0)
	actor._sprite_color = Color(0.9, 0.7, 0.5, 0.65)
	world.add_child(actor)
	return actor

func sync_and_compare(before: SlimeEnemy, after: SlimeEnemy, delta: float, label: String) -> void:
	before._process(delta)
	after._process(delta)
	before.sprite.call("_process", 0.0)
	after.sprite.call("_process", 0.0)
	var same := before.sprite.modulate == after.sprite.modulate and before.sprite.scale == after.sprite.scale and before.sprite.texture == after.sprite.texture and before.sprite.flip_h == after.sprite.flip_h
	same = same and before._frame == after._frame and before._elapsed == after._elapsed and before._clip == after._clip and before._hit_flash == after._hit_flash
	var old_material := before.sprite.material_override as ShaderMaterial
	var new_material := after.sprite.material_override as ShaderMaterial
	for parameter in ["sprite_texture", "tint", "flip_h", "flip_v", "sprite_region"]:
		same = same and old_material.get_shader_parameter(parameter) == new_material.get_shader_parameter(parameter)
	var old_mask := before.sprite.material_overlay as ShaderMaterial
	var new_mask := after.sprite.material_overlay as ShaderMaterial
	same = same and old_mask.get_shader_parameter("sprite_texture") == new_mask.get_shader_parameter("sprite_texture") and old_mask.get_shader_parameter("opacity") == new_mask.get_shader_parameter("opacity")
	check(same, label + ": exact color, scale, texture, shader, mask, facing and animation clock")

func stable_phase(before: SlimeEnemy, after: SlimeEnemy, warning: bool, flashing: bool, is_creature: bool, label: String) -> void:
	for actor in [before, after]:
		actor.spawn_delay = 1.0 if warning else 0.0
		actor._hit_flash = 2.0 if flashing else 0.0
		actor.reset_probe()
	for frame in 36: sync_and_compare(before, after, 0.01, label + " frame %d" % frame)
	check(after.get("probe_color_writes") <= 1 and after.get("probe_color_changes") <= 1, label + ": a stable final tint is written at most once")
	var exact_alpha := after._sprite_color.a * (0.4 if warning and is_creature else 1.0)
	var alphas: Array = after.get("probe_alphas")
	check(alphas.all(func(value: float): return value == exact_alpha), label + ": no temporary amplified or un-warned alpha is written")
	if not is_creature:
		check(after.get("probe_scale_writes") <= 1 and after.sprite.get("local_changes") <= 1, label + ": stable scale emits at most one native transform change")
		check(before.get("probe_scale_writes") == 36 and before.sprite.get("local_changes") >= 36, label + ": the legacy repeated scale setter really dirties the native transform")
	if flashing or (warning and is_creature):
		check(before.get("probe_color_changes") >= 36, label + ": the legacy intermediate alpha really changes the native color repeatedly")

func actor_checks(id: String) -> void:
	var source := load("res://scenes/enemies/" + id + ".tscn").instantiate() as SlimeEnemy
	var frames := source.animations
	var texture: Texture2D = source.get_node("Sprite").texture
	source.free()
	var is_creature := id != "slime"
	var base := "res://scripts/enemies/creature_enemy.gd" if is_creature else "res://scripts/enemies/slime.gd"
	var current := update_body(base)
	var tail := current.substr(current.find("\tif not animations or not camera: return"))
	var legacy := (LEGACY_CREATURE if is_creature else LEGACY_SLIME) + tail
	var before := make_actor(make_script(base, legacy), frames, texture)
	var after := make_actor(make_script(base, current), frames, texture)
	for warning in [false, true]:
		for flashing in [false, true]:
			stable_phase(before, after, warning, flashing, is_creature, "%s warning=%s flash=%s" % [id, warning, flashing])
	var actions: Array[StringName] = []
	for animation in frames.get_animation_names():
		var action := StringName(String(animation).get_slice("_", 0))
		if action not in actions: actions.append(action)
	for frame in 128:
		camera.rotation.y = float(frame) * 0.071
		for actor in [before, after]:
			actor.spawn_delay = 1.0 if frame % 31 < 11 else 0.0
			if frame % 17 == 0: actor._hit_flash = 0.08
			actor.velocity = Vector3.ZERO if frame % 8 < 4 else Vector3.RIGHT
			actor._look = Vector3.BACK.rotated(Vector3.UP, float(frame) * 0.13)
			actor.warning_scale = 0.6 if frame < 64 else 0.77
			actor._sprite_scale = Vector3.ONE * (0.8 if frame < 70 else 1.05)
			actor._sprite_color = Color(0.9, 0.7, 0.5, 0.65 if frame < 80 else 0.83)
			if is_creature:
				actor.set("_visual_action", actions[frame / 16 % actions.size()] if frame % 32 < 16 else &"")
				actor.set("_visual_progress", float(frame % 16) / 15.0 if frame % 32 < 16 else -1.0)
		sync_and_compare(before, after, 0.004 + float(frame % 7) * 0.003, "%s varied pose %d" % [id, frame])
	before.free()
	after.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	sprite_probe = GDScript.new()
	sprite_probe.source_code = SPRITE_PROBE
	check(sprite_probe.reload() == OK, "native local-transform notification probe compiles")
	for id in ["slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		actor_checks(id)
	world.queue_free()
	for frame in 4: await process_frame
	check(LIGHTING._shared_users == 0 and LIGHTING._shared_effect_masks.is_empty(), "visual probes release all shared body and effect-mask users")
	print("Enemy visual dirty writes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
