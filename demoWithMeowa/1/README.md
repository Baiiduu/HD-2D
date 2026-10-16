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

开发采用「核心逻辑 TDD → 重构前回归 → 修复后回归 → UI／玩法人工验收」。核心规则先补能复现缺陷的失败测试，再实现修复；布局、动画观感与战斗手感由实际窗口试玩确认。自动断言和截图检查不能代替人工手感验收。

统一测试入口为 `tools/run_tests.ps1`，使用 PowerShell 7。指定 `-GodotPath` 或设置 `GODOT_BIN`，不依赖仓库原作者的安装目录。`-Suite core` 运行核心契约，`regression` 运行战斗与参数集成回归，`all` 枚举可自动执行的无界面测试；`-Test test_xxx` 可单独指定用例，`-List` 只列清单。自动运行一律使用 `--headless`，`all` 排除带截图或渲染验收的人工脚本；显式传入人工脚本会拒绝执行。`-Suite render` 仅显示人工验收入口，不启动引擎、不记录自动通过。全部日志与 `summary.json` 默认写入 `D:/.codexfile/work/godot-tests/`。非零退出、引擎脚本错误、资源泄漏或超时均判失败，不能只依据输出中的 PASS 文本。

```powershell
./tools/run_tests.ps1 -Suite regression -GodotPath $env:GODOT_BIN
./tools/run_tests.ps1 -Suite render # 仅查看人工验收入口
```

测试进程默认临时启用升级、抽卡和局内技能系统，避免编辑器中关闭的开关影响战斗夹具；不保存设置或修改 `project.godot`。需要验证当前项目开关时传入 `-UseProjectSystemSwitches`。开关自身的契约测试仍在独立进程内显式切换并验证各组合。

截图、渲染观感、UI 与玩法手感均由人工验收，使用 World 的 F5 和 City 的 F6：确认出生与镜头跟随，开局卡片与重抽，移动／普攻／蓄力瞄准与释放／反弹／闪身，升级冻结与恢复，隐藏底栏及打开管理页时世界继续，撤退与重试。自动测试只验证规则、状态、数据和坐标计算；未做的人工项目保留待验收，不以无界面断言代替。

编辑器右侧的 **Game Manager** 页签集中控制项目级「升级系统」「抽卡系统」「局内技能管理器」，不在地图中创建 GameManager 节点。勾选立即保存到 `project.godot` 的 `game_manager/systems/*`，重新运行后对所有场景生效。若当前编辑器尚未加载新插件，在「项目 → 项目设置 → 插件」启用 Game Manager。各组件的本地 `Enabled` 也须开启；可在 `WavePrototype/RunGrowth`、`SkillDraft`、`RunSkillManager` 的检查器或参数总览中独立调整。

| 系统关闭时 | 行为 |
| --- | --- |
| 升级系统 | 停止经验掉落、吸取和升级，隐藏经验 HUD；独立的开局选卡仍可使用 |
| 抽卡系统 | 跳过开局选卡，不弹出升级卡片；经验仍可升级，待选奖励保留至本局重新开启或结束 |
| 局内技能管理器 | 停止可选技能学习与执行；本地关闭保留已学等级，重新开启后恢复；属性成长仍可选 |

本地开关支持运行中关闭和恢复：关闭升级或抽卡会关闭属于它的选卡界面并释放战斗冻结，不自动领取奖励；本局结束和重试仍按原规则清理。以上开关不影响角色固有弹射、Dash 或基础普攻。项目开关在系统进入树时读取，运行中修改编辑器 Game Manager 后须重新运行。

人物固有技能与局内可选技能分开管理：`Player/CharacterSkillManager`（`scripts/player/character_skill_manager.gd`）持有弹射 `body_ricochet` 和 Dash `dash`，对应组件位于其 `BodyRicochet`、`Dash` 子节点；无需选卡、没有学习等级。外部输入调用 `begin_charge`、`aim_charge`、`release_charge`、`request_dash`。普攻是 `Player/BasicSword` 的基础战斗动作，直接使用 `request_manual`，不放进任一技能池。

`WavePrototype/RunSkillManager`（`scripts/combat/run_skill_manager.gd`）只管理局内可选技能的注册、学习等级、执行开关、候选和模拟装配，不接收人物固有技能输入。`WavePrototype/SkillDraft` 连接 RunSkillManager、RunGrowth、RunBuffs、选卡界面和战斗生命周期，负责候选合并、共用重抽、重试清理与可选技能冻结登记。开局界面路径为 `WavePrototype/SkillDraft/InitialSkillChoice`，初始抽取张数在 SkillDraft。重试重置学习等级，角色固有技能仍由角色自己的管理器保留和恢复；升级冻结同时停止固有技能计时。共享成长数值继续通过 RunCombatModifiers 作用于普攻、弹射和适用的可选技能。

`BattleConfiguration` 的 `scene_combat_binding.gd` 只在组件就绪前装配所选场景的独立数值资源，不把角色接到局内技能管理器。World 和 City 均已保存角色技能子场景；其它保留预览由 Player 自动补齐同一角色组件。旧 `RunSkills` 类只兼容可学习技能入口。

World 和 City 的实际平衡、动作槽和表现开关以各自独立配置为准；更新通用 `data/enemies`、`data/player`、`data/waves` 不会自动覆盖它们。新增反弹、火带和剑光实现保留，启用时在相应地图资源中配置。World 保留既有布局、地表、镜头与光影；新增极光和静态合批默认关闭，可在对应组件独立开启。计分与统一设置界面接入共享战斗和 World，不改变编辑器 Game Manager 的现有开关。

波次数量、组间空档、批量分配和间隔增长的纯计算位于 `scripts/combat/wave_schedule_planner.gd`，不依赖地图、怪物实例或 UI。`wave_spawn_queue.gd` 持有实际待生成队列，统一处理分帧预算、整批预留、满员等待、位置重试和取消；`wave_enemy_roster.gd` 统一登记存活对象、分类数量、容量成本和空间索引，死亡与退出回调只释放一次。WavePrototype 连接地图查询、实际实例化和战斗阶段，既有调用入口与调参路径保留。规划只生成新的资源条目，不修改开场模板。

`SceneCombatConfiguration.validation_errors()` 可单独检查场景战斗配置，返回包含属性路径的全部错误；`validation_error()` 返回合并文字。装配前检查共享数值、技能与成长条目的唯一 ID、技能等级和嵌套规则，发现错误时不部分装配，也不先打开开局选卡。地形、刷新入口与实际批次容量继续在建立本局快照时校验。空的可选资源与空池保留原有回退／禁用语义。修改配置资源后重新运行场景进行装配；实际回归入口为 `test_combat_configuration_validation`。

正式地图与各预览均可在 Godot 打开后按 F6 运行。玩法试玩统一使用正式地图；怪物数量、模拟技能与等级由 `WavePrototype.population_rules` 配置。独立的旧攻击、人物弹射、怪物展示和空卡牌演示入口已移除，实际技能与 UI 组件及自动回归保留。

例如在项目目录运行波次检查：

```powershell
& 'D:\Project\godot\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/test_wave_core.gd
```

功能说明和当前实机效果见 [项目文档索引](../../docs/README.md)。一次性验证脚本和日志放到 `D:\.codexfile\work\<任务名>`，不要继续堆放在项目根目录。
