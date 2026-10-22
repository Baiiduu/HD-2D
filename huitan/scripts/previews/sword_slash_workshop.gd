extends Node3D

@onready var slash: MeshInstance3D = $SwordSlash
@onready var animation: AnimationPlayer = $SwordSlash/AnimationPlayer
@onready var play: Button = $CanvasLayer/Panel/Controls/Play
@onready var timeline: HSlider = $CanvasLayer/Panel/Controls/Timeline
@onready var phase: Label = $CanvasLayer/Panel/Phase

func _ready() -> void:
	var camera := $Camera3D as Camera3D
	var focus := Vector3.UP * 0.75
	camera.fov = 28.0
	camera.position = focus + Vector3(0.0, sin(deg_to_rad(30.627)), cos(deg_to_rad(30.627))).rotated(Vector3.UP, deg_to_rad(135.0)) * 30.0
	camera.look_at(focus, Vector3.UP)
	_configure_animation()
	play.pressed.connect(func():
		if animation.is_playing(): animation.pause()
		else: animation.play(&"slash")
		play.text = "暂停" if animation.is_playing() else "播放")
	$CanvasLayer/Panel/Controls/Replay.pressed.connect(func():
		animation.play(&"slash")
		animation.seek(0.0, true)
		play.text = "暂停")
	$CanvasLayer/Panel/Controls/Reverse.toggled.connect(func(value):
		slash.preview_reverse = value
		slash.preview_age = slash.preview_age)
	$CanvasLayer/Panel/Controls/Compare.toggled.connect(func(value):
		slash.visual = load("res://data/visual/sword_ribbon_world.tres" if value else "res://data/visual/sword_slash_world.tres")
		_configure_animation()
		play.text = "暂停")
	timeline.value_changed.connect(func(value):
		animation.pause()
		play.text = "播放"
		slash.preview_age = value * (slash.preview_sweep_seconds + slash.visual.ribbon_tail_seconds))

func _configure_animation() -> void:
	# 每次对照只改内存中的预览轨道，保留两套外观资源与正式攻击节奏。
	var clip := animation.get_animation(&"slash").duplicate() as Animation
	var reset := animation.get_animation(&"RESET")
	var end: float = slash.preview_sweep_seconds + slash.visual.ribbon_tail_seconds
	clip.length = end + 0.52
	clip.track_set_key_time(0, 1, end)
	clip.track_set_key_value(0, 1, end)
	clip.track_set_key_time(0, 2, clip.length)
	clip.track_set_key_value(0, 2, end)
	var library := AnimationLibrary.new()
	library.add_animation(&"RESET", reset)
	library.add_animation(&"slash", clip)
	animation.remove_animation_library(&"")
	animation.add_animation_library(&"", library)
	animation.play(&"slash")

func _process(_delta: float) -> void:
	var total: float = slash.preview_sweep_seconds + slash.visual.ribbon_tail_seconds
	timeline.set_value_no_signal(slash.preview_age / total)
	var state := "挥出：短弧拉开" if slash.preview_age < slash.preview_sweep_seconds else "收尾：亮刃退去，余迹破碎"
	phase.text = "%s  ·  %.3f 秒" % [state, slash.preview_age]
