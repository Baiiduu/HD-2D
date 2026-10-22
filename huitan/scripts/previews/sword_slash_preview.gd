@tool
extends GroundSlashEffect

## 独立特效场景：AnimationPlayer 驱动 preview_age，正式战斗仍由攻击时钟驱动。
@export var visual: SwordRibbonVisual
@export_range(0.3, 5.0, 0.01, "suffix:m") var preview_radius := 1.52
@export_range(30.0, 180.0, 1.0, "suffix:°") var preview_angle := 120.0
@export var preview_reverse := false
@export_range(0.03, 0.5, 0.01, "suffix:s") var preview_sweep_seconds := 0.10
@export_range(0.0, 1.0, 0.001, "suffix:s") var preview_age := 0.065:
	set(value):
		preview_age = value
		_refresh()

class FlatSurface extends RefCounted:
	func unclipped_flat(_origin: Vector3, _radius: float) -> bool: return true

var _preview_rules: PlayerSwordRules
var _flat := FlatSurface.new()

func _ready() -> void:
	super._ready()
	set_process(Engine.is_editor_hint())
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	if not is_inside_tree() or not _material or not visual: return
	if not _preview_rules: _preview_rules = PlayerSwordRules.new()
	_preview_rules.effect_mode = PlayerSwordRules.SlashVisual.NATIVE_RIBBON
	_preview_rules.ribbon_visual = visual
	_preview_rules.normal_range = preview_radius
	_preview_rules.sweep_seconds = preview_sweep_seconds
	if preview_age >= preview_sweep_seconds + visual.ribbon_tail_seconds:
		hide()
		return
	display(global_position, Vector3.FORWARD, preview_radius, preview_angle, preview_reverse,
		null, preview_age, _preview_rules, null, _flat, [])
