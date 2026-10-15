# Godot 项目目录

使用 Godot 4.7.2 打开本目录的 `project.godot`。F5 默认运行正式主场景 [scenes/world/world.tscn](scenes/world/world.tscn)，只保留当前战斗区及外围绕行带，布局说明见 [正式地图](scenes/world/README.md)。[四境视觉沙盒](scenes/previews/four_realms.tscn)保留作光影与材质对照。地图切换和参数总览均位于编辑器右侧。

## 文件放置

| 目录 | 内容 |
| --- | --- |
| `assets/meowa/` | 按资源类别组织的 Meowa 运行素材及其原始输出 |
| `assets/surface_normals/` | 独立法线数据与生成清单 |
| `assets/previews/` | 仅用于观察和对照的纹理 |
| `scenes/world/` | 正式地图与战区组件 |
| `scenes/previews/` | 视觉、建筑与伤害数字样式预览，以及保留的小院原型 |
| `scenes/combat/`、`scenes/growth/` | 波次、攻击、经验与成长组件 |
| `scenes/audio/` | 公共战斗声音、人物动作与 UI 声音组件 |
| `scenes/ui/`、`scenes/buildings/`、`scenes/enemies/` | 可复用界面、建筑和敌人 |
| `scenes/shared/` | 相机与地图效果、地形和植被默认组件 |
| `scenes/rpg/`、`scenes/plants/` | 保留的种植与植物原型 |
| `scripts/` | 按 player、camera、world、rendering、audio、combat、growth、ui 等职责分组的 GDScript |
| `scripts/previews/` | 开发预览的专用控制脚本 |
| `shaders/` | character、combat、terrain、water、environment、ui、post 分类着色器 |
| `shaders/includes/` | 公共着色器片段 |
| `data/world/` | 地形、地表画笔与历史植被布局数据 |
| `data/enemies/`、`data/waves/`、`data/skills/`、`data/growth/` | 敌人、波次、技能和本局成长配置 |
| `data/audio/`、`data/rpg/`、`data/visual/` | 音源表、保留的角色系统与视觉预设 |
| `data/player/` | 人物弹射、基础剑术的伤害／间隔／范围与五类动作资源槽 |
| `materials/` | 可复用材质资源 |
| `addons/` | 编辑器工具 |
| `tests/` | 当前回归检查与共享夹具，保留被其它测试继承的基类 |
| `tools/` | 可重复使用的资产准备工具 |

`.gd.uid`、`.gdshader.uid` 等跟随所属资源保留，`.import` 跟随对应素材。资源移动后同时更新场景引用、`preload/load`、Shader include、配置和说明链接；不通过复制同一资源创建新的 UID。

## 运行与检查

正式地图与各预览均可在 Godot 打开后按 F6 运行。玩法试玩统一使用正式地图；怪物数量、模拟技能与等级由 `WavePrototype.population_rules` 配置。独立的旧攻击、人物弹射、怪物展示和空卡牌演示入口已移除，实际技能与 UI 组件及自动回归保留。

例如在项目目录运行波次检查：

```powershell
& 'D:\Project\godot\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/test_wave_core.gd
```

功能说明和当前实机效果见 [项目文档索引](../../docs/README.md)。一次性验证脚本和日志放到 `D:\.codexfile\work\<任务名>`，不要继续堆放在项目根目录。
