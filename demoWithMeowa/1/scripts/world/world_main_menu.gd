extends Node
## World is already alive behind the opaque menu. Start only releases that same map.
const MENU = preload("res://scenes/ui/main_menu.tscn")
const REQUEST = preload("res://scripts/world/world_entry_request.gd")
@export var show_on_world_start := true
@export var prewarm_entry := true

var menu: Control
var game_ready := false
var started := false
var _entry: WorldEntry
var _bgm: BackgroundMusic
var _music_was_enabled := false
var _hud_visibility: Dictionary = {}
var _cover: CanvasLayer
var _warming_entry := false
var _warmup_started := false
var _frames_left := 2
var _entry_warmed := false
var _returning := false

func _ready() -> void:
	set_process(false)
	var requested := REQUEST.consume_menu()
	# Custom SceneTree scripts (tests/tools) own their startup; normal F5/F6 does not use --script.
	var custom_tree := "--script" in OS.get_cmdline_args() or "-s" in OS.get_cmdline_args()
	var is_root_scene := get_parent().get_parent() == get_tree().root
	if requested or (show_on_world_start and is_root_scene and not custom_tree and not REQUEST.has_pending()): open_menu()

func open_menu() -> bool:
	if menu or _cover or started or not is_inside_tree(): return false
	game_ready = false
	_warmup_started = false
	_warming_entry = false
	_frames_left = 2
	var world := get_parent()
	_entry = world.get_node("WorldEntry") as WorldEntry
	# This node precedes WorldEntry in the scene, so no direct-run intro races the menu.
	_entry.preview_on_direct_run = false
	_bgm = world.get_node("MapEffects/BGM") as BackgroundMusic
	_music_was_enabled = _bgm.music_enabled
	_bgm.music_enabled = false
	add_to_group(&"gameplay_input_blockers")
	_cover = CanvasLayer.new()
	_cover.layer = 900
	add_child(_cover)
	var black := ColorRect.new()
	black.color = Color("07101c")
	_cover.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if world.is_node_ready(): _present_menu.call_deferred()
	else: world.ready.connect(func(): _present_menu.call_deferred(), CONNECT_ONE_SHOT)
	return true

func return_to_menu() -> bool:
	if menu or _cover or _returning or not is_inside_tree(): return false
	_entry = get_parent().get_node("WorldEntry") as WorldEntry
	if _entry.active: _entry.skip()
	started = false
	_entry_warmed = true # This World has already been rendered; do not replay hidden entry.
	_returning = true
	return open_menu()

func _present_menu() -> void:
	if not is_inside_tree(): return
	for hud in _entry.hud_layers:
		if is_instance_valid(hud):
			_hud_visibility[hud] = hud.visible
			hud.hide()
	menu = MENU.instantiate()
	menu.startup_controller = self
	menu.auto_prepare_world = false
	add_child(menu)
	menu.set_game_prepared(false)
	if DisplayServer.get_name() != "headless": RenderingServer.frame_post_draw.connect(_rendered)
	if _returning: _reset_run_after_menu_draw.call_deferred()
	set_process(true)

func _reset_run_after_menu_draw() -> void:
	var tree := get_tree()
	if DisplayServer.get_name() == "headless": await tree.process_frame
	else: await RenderingServer.frame_post_draw
	await tree.process_frame
	if not is_inside_tree(): return
	(get_parent().get_node("WavePrototype") as WavePrototype).reset_for_menu()
	_returning = false

func _process(_delta: float) -> void:
	if _returning: return
	var wave := get_parent().get_node("WavePrototype") as WavePrototype
	if not get_parent().is_node_ready() or not wave._path_ready: return
	if not _warmup_started:
		_warmup_started = true
		if prewarm_entry and not _entry_warmed:
			_warming_entry = _entry.prewarm()
	if _warming_entry:
		if _entry.active: return
		_warming_entry = false
		_entry_warmed = true
		_frames_left = 2
	# Let the normal camera render again after the hidden intro has restored it.
	if DisplayServer.get_name() == "headless": _frames_left -= 1
	if _frames_left > 0: return
	if not wave.feedback_prewarm_ready(): return
	game_ready = true
	set_process(false)
	_disconnect_render()
	if is_instance_valid(menu): menu.set_game_prepared(true)

func _rendered() -> void:
	if _warmup_started and not _warming_entry: _frames_left -= 1

func begin_game() -> bool:
	if not game_ready or started or not is_instance_valid(menu): return false
	started = true
	# Restore the original HUD state before entry captures it for its own reveal.
	for hud: CanvasLayer in _hud_visibility:
		if is_instance_valid(hud): hud.visible = _hud_visibility[hud]
	_hud_visibility.clear()
	REQUEST.request()
	REQUEST.consume()
	_entry.play()
	_entry_warmed = true
	remove_from_group(&"gameplay_input_blockers")
	_bgm.music_enabled = _music_was_enabled
	_cover.queue_free()
	_cover = null
	var old_menu := menu
	menu = null
	old_menu.queue_free()
	return true

func _disconnect_render() -> void:
	if RenderingServer.frame_post_draw.is_connected(_rendered): RenderingServer.frame_post_draw.disconnect(_rendered)

func _exit_tree() -> void:
	_disconnect_render()
