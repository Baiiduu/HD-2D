# 地图切换

打开项目后，在 Godot 编辑器右侧选择 **地图切换** 标签。插件已在项目配置中启用；已打开的编辑器需要重开项目以加载新插件。

| 地图 | 场景 |
| --- | --- |
| 视觉预览 | `res://scenes/previews/four_realms.tscn` |
| 正式连续地图 | `res://scenes/world/world.tscn` |
| 树池建筑预览 | `res://scenes/previews/tree_planter_preview.tscn` |
| 广场路灯与环球雕塑预览 | `res://scenes/previews/plaza_landmarks_preview.tscn` |
| 六种弹射障碍物预览 | `res://scenes/previews/ricochet_props_preview.tscn` |
| 弹射建筑变种预览 | `res://scenes/previews/ricochet_variants_preview.tscn` |
| 城镇细节物件预览 | `res://scenes/previews/town_details_preview.tscn` |

选择地图后，可以使用：

- **打开地图**：在编辑器中打开所选场景。
- **运行此地图**：运行所选场景；已有运行会先停止。
- **设为默认启动地图**：保存 F5 启动的地图。面板会显示当前默认选择。

当前默认启动仍为视觉预览。正式连续地图已加入第一版小院出生区，可直接打开与运行；它独立维护地表与植被，复用通用人物、相机和效果资源。

若插件被关闭，可在 **项目 → 项目设置 → 插件** 中启用 **地图切换**。
