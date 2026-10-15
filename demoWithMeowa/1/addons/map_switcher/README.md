# 地图切换

打开项目后，在 Godot 编辑器右侧选择 **地图切换** 标签。插件已在项目配置中启用；已打开的编辑器需要重开项目以加载新插件。

| 地图 | 场景 |
| --- | --- |
| 正式连续地图 | `res://scenes/world/world.tscn` |
| 视觉预览 | `res://scenes/previews/four_realms.tscn` |
| 树池建筑预览 | `res://scenes/previews/tree_planter_preview.tscn` |
| 广场路灯与环球雕塑预览 | `res://scenes/previews/plaza_landmarks_preview.tscn` |
| 六种弹射障碍物预览 | `res://scenes/previews/ricochet_props_preview.tscn` |
| 弹射建筑变种预览 | `res://scenes/previews/ricochet_variants_preview.tscn` |
| 伤害数字预览 | `res://scenes/previews/damage_numbers_preview.tscn` |
| 城镇细节物件预览 | `res://scenes/previews/town_details_preview.tscn` |

选择地图后，可以使用：

- **打开地图**：在编辑器中打开所选场景。
- **运行此地图**：运行所选场景；已有运行会先停止。
- **设为默认启动地图**：保存 F5 启动的地图。面板会显示当前默认选择。

当前 F5 默认启动正式连续地图，范围为战斗区与必要绕行带。玩法测试统一在这里进行，巨量怪潮的数量、技能和等级由 `WavePrototype.population_rules` 配置。独立的旧技能与人物试玩入口已清理；视觉沙盒、建筑预览和伤害数字样式入口继续保留。

若插件被关闭，可在 **项目 → 项目设置 → 插件** 中启用 **地图切换**。
