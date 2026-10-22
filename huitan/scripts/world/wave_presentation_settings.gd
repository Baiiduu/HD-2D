class_name WavePresentationSettings
extends Resource

@export_group("演出时长")
@export_range(0.3, 4.0, 0.05, "suffix:s") var opening_seconds := 1.4
@export_range(0.3, 3.0, 0.05, "suffix:s") var next_wave_seconds := 0.9
@export_range(0.3, 4.0, 0.05, "suffix:s") var clear_seconds := 1.6
@export_group("开战动态大字")
## 仅替换首波／续波标题；清波提示与最后一击特写沿用各自演出。
@export var animated_opening_enabled := false
@export_range(48, 120, 8) var opening_title_size := 88
@export_range(0.1, 0.35, 0.01) var opening_title_top_ratio := 0.16
@export_range(0.1, 0.4, 0.01, "suffix:s") var opening_title_enter_seconds := 0.22
@export_range(0.1, 0.3, 0.01, "suffix:s") var opening_title_exit_seconds := 0.18
@export_range(16.0, 100.0, 2.0, "suffix:px") var opening_title_travel_pixels := 56.0
@export_group("清波收尾与休整")
@export var compact_clear_enabled := false
@export_range(40, 80, 8) var clear_title_size := 56
@export_range(0.1, 0.5, 0.01, "suffix:s") var clear_title_enter_seconds := 0.24
@export_range(0.1, 0.5, 0.01, "suffix:s") var clear_title_exit_seconds := 0.22
@export_range(12, 24, 1) var rest_hint_font_size := 18
## World 的开战与休整续波提示共用此屏幕底部距离。
@export_range(80.0, 180.0, 2.0, "suffix:px") var rest_hint_bottom_margin := 112.0
@export_group("最后一击特写")
@export var finish_shot_enabled := true
## 真实时间；包含推近、剪影重音与完整归位。
@export_range(0.6, 4.0, 0.05, "suffix:s") var finish_shot_seconds := 3.0
@export_range(0.08, 1.0, 0.01) var finish_slow_scale := 0.16
@export_range(0.4, 1.0, 0.01) var finish_zoom_scale := 0.56
@export_range(0.0, 1.0, 0.05) var finish_contrast := 0.9
@export_group("标题美术")
@export var battle_frame: Texture2D
@export var clear_frame: Texture2D
@export var pulse_texture: Texture2D
@export_range(440.0, 1000.0, 10.0) var banner_width := 520.0
@export_range(0.1, 0.4, 0.01) var top_ratio := 0.10
@export var title_color := Color("fff1cf")
@export var battle_color := Color("ffc26c")
@export var clear_color := Color("bceacf")
@export_group("场景反馈")
@export var ground_pulse_enabled := true
@export_range(0.5, 6.0, 0.1, "suffix:m") var battle_pulse_radius := 1.8
@export_range(0.5, 8.0, 0.1, "suffix:m") var clear_pulse_radius := 3.6
@export_range(0.0, 1.0, 0.05) var pulse_opacity := 0.48
@export_range(0.0, 0.3, 0.01) var edge_strength := 0.10
