class_name KillAudioRules
extends Resource

## 各地图独立启用；只改变击杀听感，不改变死亡、伤害或镜头。
@export_group("击杀声音反馈")
@export var enabled := true
@export_group("附近群杀节奏")
@export_range(0.04, 0.2, 0.01, "suffix:s") var group_window := 0.10
@export_range(0.5, 5.0, 0.1, "suffix:m") var group_radius := 2.5
@export_range(2, 12, 1) var group_threshold := 3
@export_range(4, 30, 1) var large_group_threshold := 8
@export_range(0.1, 1.0, 0.01, "suffix:s") var group_cooldown := 0.24
@export_group("相对击杀主音的增益")
@export_range(-18.0, 3.0, 0.5) var group_gain_db := -2.0
@export_range(-24.0, 0.0, 0.5) var air_gain_db := -10.0
@export_range(-24.0, 0.0, 0.5) var landing_gain_db := -9.0
@export_group("真实空中翻飞")
## 地图明确启用；起落由快照驱动，原一次性抛飞事件保留兼容。
@export var air_motion_enabled := false
@export_range(0.01, 0.2, 0.01, "suffix:s") var air_fade_out_seconds := 0.06
@export_group("群杀临时声音退让")
@export_range(-6.0, 0.0, 0.1) var music_duck_db := -1.2
@export_range(-6.0, 0.0, 0.1) var ambience_duck_db := -1.8
@export_range(0.05, 0.6, 0.01, "suffix:s") var duck_seconds := 0.22

func gain_for(cue: StringName) -> float:
	match cue:
		&"kill_group": return group_gain_db
		&"kill_air": return air_gain_db
		&"kill_land": return landing_gain_db
	return 0.0
