extends SceneTree

var audio: GameAudio
var map: Node3D
var player: Node3D
var camera: Camera3D
var owners: Array[Node] = []
var clips: Array[AudioStream] = [preload("res://assets/meowa/audio/combat/sweep_01.wav")]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func event(owner: Node, cue: StringName, kind := GameAudio.Kind.ATTACK, point := Vector3.ZERO, extra := {}) -> Dictionary:
	var result := {"source": owner, "cue": cue, "kind": kind, "position": point, "clips": clips, "volume_db": -10.0}
	result.merge(extra, true)
	return result

func reset() -> void:
	audio.stop_all()
	audio.enabled = true
	audio.set_frozen(false)
	audio.max_voices = 12
	audio.important_reserve = 2
	audio.per_cue_limit = 3
	audio.minimum_interval = 0.035
	audio.merge_window = 0.08
	audio._process(0.0)

func frames(count := 4) -> void:
	for frame in count: await process_frame

func run() -> void:
	map = Node3D.new()
	root.add_child(map)
	player = Node3D.new()
	map.add_child(player)
	camera = Camera3D.new()
	map.add_child(camera)
	camera.position = Vector3(0, 1, 5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	for index in 100:
		var owner := Node.new()
		map.add_child(owner)
		owners.append(owner)
	audio = GameAudio.new()
	audio.load_local_mix = false
	audio.player = player
	audio.camera = camera
	map.add_child(audio)
	await frames()
	check(audio._voices.size() == 12 and get_first_node_in_group(&"game_audio") == audio, "One shared twelve-voice pool is available to all producers")
	for index in 100: audio.request(event(owners[index], StringName("weapon_%d" % index)))
	check(audio.get_debug_state().active == 10 and audio.get_debug_state().budget_dropped == 90, "One hundred different attackers share ten normal slots plus two reserves")
	check(audio.request(event(owners[0], &"danger", GameAudio.Kind.DANGER)) != null, "Danger can use a protected slot")
	check(audio.request(event(owners[0], &"hurt", GameAudio.Kind.HURT)) != null and audio.get_debug_state().active == 12, "Hurt uses the other reserve without exceeding the hard limit")
	check(audio.request(event(owners[0], &"hurt_second", GameAudio.Kind.HURT)) != null and audio.get_debug_state().active == 12 and audio.get_debug_state().preempted == 1, "Important feedback replaces a weaker sound when the pool is full")
	check(audio.request(event(owners[0], &"ordinary_hit", GameAudio.Kind.HIT)) == null, "Ordinary feedback cannot evict stronger attack or danger voices")
	reset()
	for index in 10: audio.request(event(owners[index], &"same_attack"))
	check(audio.get_debug_state().active == 3, "Identical attack cues share a global per-cue limit across sources")
	reset()
	for index in 100: audio.request(event(owners[index], StringName("hit_%d" % index), GameAudio.Kind.HIT, Vector3(0.01 * index, 0, 0)))
	check(audio.get_debug_state().active == 1 and audio.get_debug_state().merged == 99, "One hundred cross-weapon hits in one area become one representative sound")
	check(audio.request(event(owners[0], &"distant_hit", GameAudio.Kind.HIT, Vector3(5, 0, 0))) != null, "A separate impact region remains audible")
	audio._process(0.09)
	check(audio.request(event(owners[1], &"later_hit", GameAudio.Kind.HIT)) != null, "The same area can sound again after the merge window")
	reset()
	check(audio.request(event(owners[0], &"repeat")) != null and audio.request(event(owners[0], &"repeat")) == null, "One emitter cannot retrigger one cue in the same short interval")
	reset()
	check(audio.request(event(owners[0], &"too_far", GameAudio.Kind.ATTACK, Vector3(25, 0, 0))) == null, "Far sounds are filtered relative to the player")
	var near := audio.request(event(owners[0], &"near"))
	check(near != null and is_equal_approx(near.volume_db, -10.0), "A sound at the player keeps its source gain")
	var distant := audio.request(event(owners[1], &"distance", GameAudio.Kind.ATTACK, Vector3(0, 0, -10)))
	check(distant != null and distant.volume_db < near.volume_db, "Farther in-view sounds attenuate")
	camera.position *= 5.0
	camera.look_at(Vector3.ZERO)
	audio._process(0.01)
	check(is_equal_approx(near.volume_db, -10.0) and audio._listener.global_position.distance_to(player.global_position + Vector3.UP * audio.listener_height) < 0.001, "Pulling the camera back does not attenuate a nearby player sound")
	camera.position = Vector3(0, 1, 5)
	camera.look_at(Vector3.ZERO)
	var behind_point := Vector3(0, 0, 8)
	var ordinary := audio.request(event(owners[2], &"offscreen", GameAudio.Kind.ATTACK, behind_point))
	var danger := audio.request(event(owners[3], &"offscreen_danger", GameAudio.Kind.DANGER, behind_point))
	check(ordinary != null and danger != null and danger.volume_db > ordinary.volume_db + 6.0, "Offscreen ordinary sounds soften while important warnings remain clear")
	camera.rotation.y += PI / 2.0
	audio._process(0.01)
	var forward := -camera.global_basis.z
	forward.y = 0
	check((-audio._listener.global_basis.z).dot(forward.normalized()) > 0.999, "Listener orientation follows camera yaw without moving the camera")
	reset()
	var first := audio.request(event(owners[0], &"owned_a"))
	var second := audio.request(event(owners[1], &"owned_b"))
	audio.stop_source(owners[0])
	check(not first.playing and second.playing and audio.get_debug_state().active == 1, "Cancelling one weapon leaves another weapon audible")
	var following := audio.request(event(player, &"following", GameAudio.Kind.ATTACK, player.position, {"follow_source": true}))
	player.position.x += 1.0
	audio._process(0.01)
	check(following.global_position == player.global_position, "Following attacks keep their existing voice at the moving emitter")
	check(audio.set_cue_volume(player, &"following", -18.0), "A continuous cue can update its gain without requesting another voice")
	check(is_equal_approx(following.volume_db, -18.0), "Cue gain changes are applied immediately")
	check(not audio.set_cue_volume(owners[1], &"following", -30.0) and is_equal_approx(following.volume_db, -18.0), "Gain updates cannot affect a different source")
	check(not audio.set_cue_volume(player, &"following", NAN), "Invalid gains do not enter an existing voice")
	audio.stop_cue(player, &"following")
	check(not audio.set_cue_volume(player, &"following", -30.0) and second.playing, "Updating a finished cue does not touch unrelated pooled voices")
	player.position.x -= 1.0
	audio.set_frozen(true)
	await frames()
	# 3D 播放的暂停命令在音频线程的下一混音块生效。
	await create_timer(0.12).timeout
	var position := second.get_playback_position()
	await create_timer(0.15).timeout
	check(second.stream_paused and absf(second.get_playback_position() - position) < 0.01, "Combat freeze holds actual mixer playback in place")
	check(audio.request(event(owners[2], &"frozen_request")) == null, "Frozen combat rejects new events instead of queueing a later burst")
	audio.set_frozen(false)
	await frames()
	check(not second.stream_paused, "Unfreezing resumes existing voices")
	audio.enabled = false
	check(audio.get_debug_state().active == 0 and not second.playing, "The global switch stops all combat voices")
	reset()
	audio.max_voices = 2
	audio.important_reserve = 0
	for index in 4: audio.request(event(owners[index], StringName("resize_%d" % index)))
	check(audio._voices.size() == 2 and audio.get_debug_state().active == 2, "Changing the inspector limit immediately resizes the shared pool")
	reset()
	var disposable := Node.new()
	map.add_child(disposable)
	var orphan := audio.request(event(disposable, &"orphan"))
	disposable.free()
	audio._process(0.01)
	check(not orphan.playing and audio.get_debug_state().active == 0, "Destroyed emitters release their voices")
	check(audio.request(event(owners[0], &"nan", GameAudio.Kind.ATTACK, Vector3(NAN, 0, 0))) == null, "Invalid positions do not enter the audio server")
	for bus in audio.BUSES: check(AudioServer.get_bus_index(bus) >= 0, "Each audio category has its own bus")
	var combat_bus := AudioServer.get_bus_index(&"Combat")
	check(AudioServer.get_bus_effect(combat_bus, 0) is AudioEffectCompressor and AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "Combat compressor and output limiter are attached")
	audio.combat_volume_db = -7.0
	audio.music_volume_db = -4.0
	audio.compression_threshold_db = -20.0
	audio.limiter_ceiling_db = -2.0
	audio._process(0.01)
	check(AudioServer.get_bus_volume_db(combat_bus) == -7.0 and AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")) == -4.0, "Inspector mix gains affect their independent groups")
	check(AudioServer.get_bus_effect(combat_bus, 0).threshold == -20.0 and is_equal_approx(AudioServer.get_bus_effect(0, 0).ceiling_db, -2.0), "Inspector peak controls update the actual effects")
	audio.stop_all()
	map.queue_free()
	await frames()
	check(get_first_node_in_group(&"game_audio") == null, "Scene exit releases the singleton map manager")
	clips.clear()
	owners.clear()
	await create_timer(0.1).timeout
	print("Global audio: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
