class_name AudioMixSettings
extends RefCounted

signal changed

const BUSES := [&"Combat", &"Music", &"Ambience", &"UI", &"Movement"]
const MIN_DB := -40.0
const MAX_DB := 6.0
## 50 keeps the map's default mix; 100 adds headroom without changing stored dB gains.
const DEFAULT_BUS_VOLUME_PERCENT := 50.0
const BUS_MIN_DB := -80.0
const BUS_MAX_DB := linear_to_db(100.0 / DEFAULT_BUS_VOLUME_PERCENT)

var clip_gains: Dictionary = {}
var clip_mutes: Dictionary = {}
var bus_gains: Dictionary = {}

func clip_path(clip: AudioStream) -> String:
	return String(clip.get_meta(&"mix_source_path", clip.resource_path)) if clip else ""

func clip_gain_db(clip: AudioStream) -> float:
	var path := clip_path(clip)
	return -80.0 if clip_mutes.get(path, false) else float(clip_gains.get(path, 0.0))

func is_clip_muted(clip: AudioStream) -> bool:
	return bool(clip_mutes.get(clip_path(clip), false))

func set_clip_gain(path: String, value: float) -> void:
	if path.is_empty() or not is_finite(value): return
	_store_gain(clip_gains, path, value)
	changed.emit()

func set_clip_muted(path: String, value: bool) -> void:
	if path.is_empty(): return
	if value: clip_mutes[path] = true
	else: clip_mutes.erase(path)
	changed.emit()

func set_bus_gain(bus: StringName, value: float) -> void:
	if bus not in BUSES or not is_finite(value): return
	_store_gain(bus_gains, String(bus), value, BUS_MIN_DB, BUS_MAX_DB)
	changed.emit()

func bus_volume_percent(bus: StringName) -> float:
	if is_bus_muted(bus): return 0.0
	return clampf(db_to_linear(float(bus_gains.get(String(bus), 0.0))) * DEFAULT_BUS_VOLUME_PERCENT, 0.0, 100.0)

func set_bus_volume_percent(bus: StringName, value: float) -> void:
	if bus not in BUSES or not is_finite(value): return
	value = clampf(value, 0.0, 100.0)
	set_bus_gain(bus, linear_to_db(value / DEFAULT_BUS_VOLUME_PERCENT) if value > 0 else BUS_MIN_DB)

func is_bus_muted(bus: StringName) -> bool:
	return float(bus_gains.get(String(bus), 0.0)) <= BUS_MIN_DB

func _store_gain(values: Dictionary, key: String, value: float, minimum := MIN_DB, maximum := MAX_DB) -> void:
	value = clampf(value, minimum, maximum)
	if is_zero_approx(value): values.erase(key)
	else: values[key] = value

func reset_clip(path: String) -> void:
	clip_gains.erase(path)
	clip_mutes.erase(path)
	changed.emit()

func reset_all() -> void:
	clip_gains.clear()
	clip_mutes.clear()
	bus_gains.clear()
	changed.emit()

func save_to_path(path: String) -> Error:
	var file := ConfigFile.new()
	file.set_value("mix", "version", 1)
	for key in clip_gains: file.set_value("clips", key, clip_gains[key])
	for key in clip_mutes: file.set_value("muted", key, true)
	for key in bus_gains: file.set_value("buses", key, bus_gains[key])
	return file.save(path)

func load_from_path(path: String) -> Error:
	var file := ConfigFile.new()
	var result := file.load(path)
	if result != OK: return result
	if file.get_value("mix", "version", 0) != 1: return ERR_INVALID_DATA
	clip_gains.clear()
	clip_mutes.clear()
	bus_gains.clear()
	for section in ["clips", "buses"]:
		if not file.has_section(section): continue
		for key in file.get_section_keys(section):
			var value: Variant = file.get_value(section, key)
			if not (value is float or value is int) or not is_finite(float(value)): continue
			if section == "buses" and StringName(key) not in BUSES: continue
			if section == "buses": _store_gain(bus_gains, key, float(value), BUS_MIN_DB, BUS_MAX_DB)
			else: _store_gain(clip_gains, key, float(value))
	if file.has_section("muted"):
		for key in file.get_section_keys("muted"):
			if file.get_value("muted", key) == true: clip_mutes[key] = true
	changed.emit()
	return OK
