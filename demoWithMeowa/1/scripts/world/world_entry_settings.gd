class_name WorldEntrySettings
extends Resource

@export_group("入场播放")
@export var enabled := true
@export_range(0.0, 12.0, 0.1, "suffix:s") var duration_seconds := 6.4
@export var allow_skip := true
## 前段用于穿雾运镜，余下时间在原有取景中散雾显露人物。
@export_range(0.35, 0.85, 0.01) var arrival_ratio := 0.56
@export_group("穿雾环绕镜头")
## 未绑定建筑路线时，从正常镜头后方远空推进；最后恢复地图原有取景，不改基础镜头参数。
@export_range(50.0, 180.0, 1.0, "suffix:m") var sky_extra_distance := 95.0
@export_range(8.0, 45.0, 1.0, "suffix:m") var sky_extra_height := 18.0
@export_range(-25.0, 25.0, 0.5, "suffix:m") var sky_lateral_offset := 8.0
@export_range(-5.0, 8.0, 0.5) var sky_view_pitch := 3.0
@export_range(0.0, 160.0, 1.0, "suffix:°") var camera_sweep_degrees := 110.0
## 左右侧倾；限制在 55° 内，不倒置画面。
@export_range(0.0, 55.0, 1.0, "suffix:°") var camera_bank_degrees := 36.0
@export_group("穿雾声音")
@export var traversal_audio_enabled := true
@export var traversal_sound: AudioStream
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var traversal_volume_db := -8.0
@export_group("空间云雾")
## 雾团整体强度；没有全屏颜色遮罩，浓淡由空间密度、噪声与相机穿行决定。
@export_range(0.0, 0.95, 0.01) var fog_opacity := 0.94
@export var fog_color := Color(0.60, 0.64, 0.69)
@export_range(0.0, 2.0, 0.05) var fog_flow_speed := 0.65
@export_range(0.0, 0.4, 0.005) var volume_density := 0.22
@export_range(10.0, 70.0, 1.0, "suffix:m") var fog_retreat_distance := 42.0
@export_range(0.0, 2.0, 0.05) var fog_curl_strength := 1.0
@export_group("人物聚光")
@export var spotlight_color := Color(1.0, 0.86, 0.65)
@export_range(0.0, 12.0, 0.1) var spotlight_energy := 4.0
@export_range(0.0, 12.0, 0.1) var spotlight_fog_energy := 3.0
@export_range(4.0, 14.0, 0.5, "suffix:m") var spotlight_height := 9.0
@export_range(5.0, 18.0, 0.5) var spotlight_angle := 10.0
