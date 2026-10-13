class_name SpawnVisualPreset
extends Resource

## 视觉快照；当前 Style 仅应用其中的光影、表面受光和天气，不应用历史镜头或布局。
@export_group("风格名称")
@export var title := ""
@export_group("预设视觉值")
## 节点路径 → 参数字典。相机、位置、尺寸、密度、声音及闪身历史项不参与切换。
@export var node_values: Dictionary = {}
## 地表／侧壁／后处理参数；运行时坐标与生成纹理绑定由原系统维护。
@export var shader_values: Dictionary = {}
## 草地和道路的 tint、roughness、metallic、wet_response；不修改画笔编号或图集规则。
@export var palette_values: Dictionary = {}
