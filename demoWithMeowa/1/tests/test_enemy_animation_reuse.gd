extends SceneTree

const SLIME := preload("res://scripts/enemies/slime.gd")
const OLD_SLIME := """func _process(delta: float) -> void:
	if wave_mode:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		var target_scale := _sprite_scale
		if sprite.scale != target_scale: sprite.scale = target_scale
		var tint := _sprite_color * (1.8 if _hit_flash > 0.0 else 1.0)
		tint.a = _sprite_color.a
		if sprite.modulate != tint: sprite.modulate = tint
	if not animations or not camera: return
	var right := camera.global_basis.x
	var backward := camera.global_basis.z
	right.y = 0.0; backward.y = 0.0
	var facing := _facing_index(right.normalized(), backward.normalized())
	var moving := Vector2(velocity.x,velocity.z).length() > 0.05
	var clip := StringName(("hop_" if moving else "idle_")+DIRECTIONS[facing])
	if not animations.has_animation(clip): return
	if clip != _clip:
		if String(_clip).get_slice("_",0) != String(clip).get_slice("_",0):
			_frame = 0; _elapsed = 0.0
		_clip = clip
	var count := animations.get_frame_count(_clip)
	var fps := animations.get_animation_speed(_clip)
	if count == 0 or fps <= 0.0: return
	_frame %= count
	_elapsed += delta*animation_speed
	var duration := animations.get_frame_duration(_clip,_frame)/fps
	while _elapsed >= duration:
		_elapsed -= duration
		_frame = (_frame+1)%count
		duration = animations.get_frame_duration(_clip,_frame)/fps
	sprite.texture = animations.get_frame_texture(_clip,_frame)
"""
const OLD_CREATURE := """func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	var tint := _sprite_color * (1.8 if _hit_flash > 0.0 else 1.0)
	tint.a = _sprite_color.a
	if sprite.modulate != tint: sprite.modulate = tint
	if not animations or not camera: return
	var right := camera.global_basis.x
	var backward := camera.global_basis.z
	right.y = 0.0
	backward.y = 0.0
	var facing := _facing_index(right.normalized(), backward.normalized())
	var direction: String = DIRECTIONS[facing]
	sprite.flip_h = "left" in direction
	direction = direction.replace("left", "right")
	var action: StringName = _visual_action if not _visual_action.is_empty() else (&"walk" if Vector2(velocity.x, velocity.z).length() > 0.05 else &"idle")
	var clip := StringName("%s_%s" % [action, direction])
	if not animations.has_animation(clip): clip = StringName("%s_front" % action)
	if not animations.has_animation(clip): return
	var count := animations.get_frame_count(clip)
	if count == 0: return
	if _visual_progress >= 0.0:
		sprite.texture = animations.get_frame_texture(clip, clampi(roundi(_visual_progress * (count - 1)), 0, count - 1))
		return
	if String(_clip).get_slice("_", 0) != String(action):
		_frame = 0
		_elapsed = 0.0
	_clip = clip
	_frame %= count
	var fps := animations.get_animation_speed(clip)
	if fps <= 0.0: return
	_elapsed += delta * animation_speed
	var duration := animations.get_frame_duration(clip, _frame) / fps
	while _elapsed >= duration:
		_elapsed -= duration
		_frame = (_frame + 1) % count
		duration = animations.get_frame_duration(clip, _frame) / fps
	sprite.texture = animations.get_frame_texture(clip, _frame)
"""
const PROBE := """
var texture_writes := 0
var repeat_texture_writes := 0
var flip_writes := 0
var repeat_flip_writes := 0
func _enter_tree() -> void:
	pass
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
func _write_texture(value: Texture2D) -> void:
	texture_writes += 1
	if sprite.texture == value: repeat_texture_writes += 1
	sprite.texture = value
func _write_flip(value: bool) -> void:
	flip_writes += 1
	if sprite.flip_h == value: repeat_flip_writes += 1
	sprite.flip_h = value
"""
var checks := 0
var failures := 0
var world: Node3D
var camera_parent: Node3D
var camera: Camera3D
var textures: Array[Texture2D] = []
var scripts: Array[GDScript] = []
var old_actor: SlimeEnemy
var new_actor: SlimeEnemy
var creature := false

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func body(source: String) -> String:
	var first := source.find("func _process(delta: float) -> void:")
	var last := source.find("\nfunc ", first + 1)
	return source.substr(first, -1 if last < 0 else last-first)

func instrument(source: String) -> String:
	var lines := PackedStringArray()
	for line in source.split("\n"):
		for item in [["sprite.texture = ","_write_texture"],["sprite.flip_h = ","_write_flip"]]:
			var at := line.find(item[0])
			if at >= 0: line = line.substr(0,at)+item[1]+"("+line.substr(at+item[0].length())+")"
		lines.append(line)
	return "\n".join(lines)

func actor_script(base: String, source: String) -> GDScript:
	var result := GDScript.new()
	result.source_code = "extends \""+base+"\"\n"+PROBE+"\n"+instrument(body(source))
	check(result.reload() == OK,"Compile actual animation update: "+base)
	scripts.append(result)
	return result

func make_actor(script: GDScript, frames: SpriteFrames) -> SlimeEnemy:
	var actor := script.new() as SlimeEnemy
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = textures[0]
	actor.add_child(sprite)
	actor.animations = frames
	actor.camera = camera
	actor.wave_mode = true
	world.add_child(actor)
	return actor

func frames_resource() -> SpriteFrames:
	var result := SpriteFrames.new()
	for action in ["idle","hop","walk","skill","two_words"]:
		for index in SLIME.DIRECTIONS.size():
			var clip := StringName(action+"_"+SLIME.DIRECTIONS[index])
			result.add_animation(clip)
			result.set_animation_speed(clip,7.0+index)
			for frame in 3: result.add_frame(clip,textures[(index+frame)%textures.size()],float(frame+1)*.4)
	return result

func compare(delta: float, label: String, reverse := false) -> void:
	if reverse:
		new_actor._process(delta)
		old_actor._process(delta)
	else:
		old_actor._process(delta)
		new_actor._process(delta)
	for key in [&"_frame",&"_clip",&"_elapsed",&"_facing_sector",&"_hit_flash"]:
		check(new_actor.get(key) == old_actor.get(key),label+" state "+key)
	check(new_actor.sprite.texture == old_actor.sprite.texture,label+" frame texture")
	check(new_actor.sprite.flip_h == old_actor.sprite.flip_h,label+" horizontal mirror")
	check(new_actor.sprite.modulate == old_actor.sprite.modulate and new_actor.sprite.scale == old_actor.sprite.scale,label+" warning/flash")

func animation_sequence() -> void:
	# All calls deliberately stay in the same engine frame: a frame-number camera
	# cache would miss camera and parent rotations between these two-actor updates.
	for index in 144:
		camera_parent.transform = Transform3D(Basis.from_euler(Vector3(.1,index*.037,-.07)).scaled(Vector3(1.1,.8,1.3)),Vector3.ZERO)
		camera.rotation = Vector3(-.42,index*.017,.03)
		for actor in [old_actor,new_actor]:
			actor._look = Vector3(sin(index*.09),0,cos(index*.09))
			actor.velocity = Vector3(.0 if index%11<3 else .07,0,.02 if index%7 else .03)
			actor.animation_speed = [0.25,1.0,1.7][index%3]
			actor.spawn_delay = .3 if index%8<2 else 0.0
			actor._sprite_color = Color(.8,.9,1,.65 if index%5 else .4)
			if index%13 == 0: actor._hit_flash = .15
			if creature:
				actor.set("_visual_action",[&"",&"skill",&"two_words",&"missing"][index%4])
				actor.set("_visual_progress",[-1.0,0.0,.4,1.3][(index/4)%4])
		compare([0.0,.016,.12,.35][index%4],"sequence %d"%index,index%2 == 0)
	# The same camera basis can serve either actor order, and switching cameras
	# with a different basis must be noticed even without an engine-frame advance.
	var other := Camera3D.new()
	other.rotation = Vector3(-.7,2.0,0)
	world.add_child(other)
	for actor in [old_actor,new_actor]: actor.camera = other
	compare(.03,"different camera, same render frame")
	for actor in [old_actor,new_actor]: actor.camera = camera
	other.free()

func edit_checks() -> void:
	var frames := frames_resource()
	for actor in [old_actor,new_actor]:
		actor.animations = frames
		actor.velocity = Vector3.ZERO
		actor._look = Vector3.BACK
		if creature:
			actor.set("_visual_action",&"")
			actor.set("_visual_progress",-1.0)
	camera_parent.transform = Transform3D.IDENTITY
	camera.rotation = Vector3.ZERO
	compare(.07,"resource replacement retains animation phase")
	var selected := old_actor._clip
	frames.set_animation_speed(selected,0.0)
	compare(.3,"zero fps edit without changed signal")
	frames.set_animation_speed(selected,17.0)
	frames.set_frame(selected,0,textures[3],.17)
	compare(.15,"live texture and duration edit")
	frames.remove_frame(selected,2)
	compare(.02,"frame removal clamps current index")
	frames.add_frame(selected,textures[1],1.3)
	compare(.09,"frame addition")
	for actor in [old_actor,new_actor]: actor.sprite.texture = textures[2]
	compare(0.0,"external texture replacement restored even at unchanged frame")
	var alternate := &"skill_front"
	# These operations do not emit SpriteFrames.changed, including a rename swap
	# with unchanged names/counts/fps. The production getters must remain live.
	frames.rename_animation(selected,&"temporary")
	frames.rename_animation(alternate,selected)
	frames.rename_animation(&"temporary",alternate)
	compare(.11,"silent rename swap uses replacement metadata")
	frames.remove_animation(selected)
	compare(.13,"silent clip removal")
	frames.duplicate_animation(alternate,selected)
	compare(.17,"silent same-name animation replacement")
	frames.clear(selected)
	compare(.12,"empty clip retains previous texture")
	frames.add_frame(selected,textures[3],.8)
	compare(.05,"repopulate cleared clip")
	frames.clear_all()
	compare(.09,"clear_all without changed signal")
	frames.add_animation(selected)
	frames.add_frame(selected,textures[1],.5)
	compare(.11,"new clip after clear_all")
	if creature:
		for actor in [old_actor,new_actor]:
			actor.set("_visual_action",&"skill")
			actor.set("_visual_progress",.8)
		frames.add_animation(&"skill_front")
		frames.add_frame(&"skill_front",textures[3],.7)
		compare(.8,"action direction missing uses front fallback with progress")
	for actor in [old_actor,new_actor]: actor.animations = null
	compare(.05,"null animation resource")
	for actor in [old_actor,new_actor]: actor.animations = frames
	compare(.05,"restore animation resource")

func steady_write_checks() -> void:
	var frames := frames_resource()
	for actor in [old_actor,new_actor]:
		actor.animations = frames
		actor._look = Vector3.BACK
		actor.velocity = Vector3.ZERO
		if creature:
			actor.set("_visual_action",&"skill")
			actor.set("_visual_progress",.3)
	compare(0.0,"steady pose setup")
	for actor in [old_actor,new_actor]:
		actor.set("repeat_texture_writes",0)
		actor.set("repeat_flip_writes",0)
	for index in 12: compare(0.0,"unchanged pose %d"%index)
	check(new_actor.get("repeat_texture_writes") == 0 and old_actor.get("repeat_texture_writes") == 12,"Stable native frame avoids all redundant texture setter calls")
	if creature: check(new_actor.get("repeat_flip_writes") == 0 and old_actor.get("repeat_flip_writes") == 12,"Stable mirror avoids all redundant flip setter calls")
	if creature:
		new_actor.sprite.flip_h = not new_actor.sprite.flip_h
		old_actor.sprite.flip_h = not old_actor.sprite.flip_h
		compare(0.0,"external mirror replacement restored")
	for index in 24: SLIME._clips_for(StringName("evicted_%d"%index))
	compare(.03,"cache eviction still resolves previous clip action")
	camera_parent.transform = Transform3D.IDENTITY
	camera.rotation = Vector3.ZERO
	for actor in [old_actor,new_actor]: actor._facing_sector = 0
	for degrees in [22.0,28.4,28.6]:
		for actor in [old_actor,new_actor]: actor._look = Vector3(sin(deg_to_rad(degrees)),0,cos(deg_to_rad(degrees)))
		compare(0.0,"six-degree facing margin at %.1f"%degrees)
		check(new_actor._facing_sector == (0 if degrees < 28.5 else 1),"Existing six-degree hysteresis remains intact")

func run_kind(is_creature: bool) -> void:
	creature = is_creature
	var name := "creature_enemy" if creature else "slime"
	var base := "res://scripts/enemies/"+name+".gd"
	var frames := frames_resource()
	old_actor = make_actor(actor_script(base,OLD_CREATURE if creature else OLD_SLIME),frames)
	new_actor = make_actor(actor_script(base,FileAccess.get_file_as_string(base)),frames)
	animation_sequence()
	edit_checks()
	steady_write_checks()
	old_actor.free()
	new_actor.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera_parent = Node3D.new()
	world.add_child(camera_parent)
	camera = Camera3D.new()
	camera_parent.add_child(camera)
	for color in [Color.RED,Color.GREEN,Color.BLUE,Color.YELLOW]:
		var pixels := Image.create(4,4,false,Image.FORMAT_RGBA8)
		pixels.fill(color)
		textures.append(ImageTexture.create_from_image(pixels))
	run_kind(false)
	run_kind(true)
	for index in 32: SLIME._clips_for(StringName("custom_%d"%index))
	check(SLIME._directional_clips.size() <= 16 and SLIME._clip_actions.size() <= 144,"String-only caches remain bounded after custom actions")
	world.queue_free()
	for frame in 3: await process_frame
	print("Enemy animation reuse: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
