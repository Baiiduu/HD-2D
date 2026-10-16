# 参数总览

编辑器独立 **Game Manager** 页签保存项目级升级、抽卡、局内技能三个总开关，重新运行后对全部场景生效；不向场景加入节点。参数总览搜索“升级系统本地开关”“抽卡系统本地开关”“局内技能管理器本地开关”可定位各组件 `enabled`。项目与本地开关同时开启才生效，角色固有技能和基础普攻独立。

角色固有技能位于 `Player/CharacterSkillManager`（`scripts/player/character_skill_manager.gd`），仅管理本体弹射 `body_ricochet` 与 Dash `dash`。实际组件是它的 `BodyRicochet`、`Dash` 子节点；基础普攻 `Player/BasicSword` 是独立战斗动作。角色管理器不接入选卡、学习等级或技能栏；`begin_charge`、`aim_charge`、`release_charge`、`request_dash` 是外部输入入口，`set_skill_enabled` 调整运行开关而不写回规则资源。

`WavePrototype/RunSkillManager`（`scripts/combat/run_skill_manager.gd`）只负责升级可选技能。`get_skill` / `get_registered_ids` 查询可选组件，`set_skill_level` / `get_level` 管理本局学习等级，`is_skill_available` / `set_skill_available` 管理进入选卡池的资格，`set_skill_enabled` 管理临时执行开关。新增可选技能实现定义、等级应用及升级说明接口并加入 `skill_paths`，或调用 `register_skill`；固有技能 ID 不可注册到此管理器。开局选择与升级候选沿用同一有效池，模拟退出恢复原来的可选技能配置。

`WavePrototype/SkillDraft` 连接局内管理器、成长、增益、界面和战斗生命周期。初始抽取张数位于 SkillDraft，开局界面为其 `InitialSkillChoice` 子节点。移除 SkillDraft 会释放自己的候选来源、输入占用与可选技能冻结登记，不修改角色技能注册。重试清空可学习等级；角色固有能力单独恢复，升级冻结时也停止弹射和 Dash 计时。共享成长仍对普攻、弹射和可选技能的适用属性生效。

场景独立 Resource 由 `BattleConfiguration` 装配，World 和 City 的数值分别在各自 `configuration` 中修改。City 镜头直接使用 `MapEffects/Camera3D` 保存的 FOV、距离、俯角与焦点；HDR 散景组件继续负责自身渲染接入。旧 `RunSkills` 类只兼容可学习技能。

顶部「战斗配置」选择 World 或 City 会打开对应地图；「打开此场景的战斗配置」直接编辑该地图 `BattleConfiguration.configuration`。F5 继续启动正式 world，城市战斗使用打开 city 后的 F6，或「地图切换 → City 城市战斗场景 → 运行此地图」。旧面板点击「刷新」可补上选择入口。

独立配置位于 `data/combat/scenes/world/configuration.tres` 和 `data/combat/scenes/city/configuration.tres`。各自拥有怪物、波次、人物弹射、基础剑术、成长、技能等级和伤害数字资源；动作槽、残影和弹射运镜也独立。美术与战斗脚本继续共用。参数总览优先显示此配置中的有效值，不再重复列出被配置覆盖的旧入口或通用怪潮预设。停止运行、修改并保存资源后，重新运行生效。

Godot 右侧「参数总览」搜索当前场景的参数，选择结果在原检查器中修改。默认只显示常用；关闭筛选按组件及原分组浏览全部，搜索始终覆盖全部。

选中参数后点击「定位来源」，或直接双击参数，可在场景树中选中来源节点，并展开、高亮检查器中的目标项；资源参数还会在文件系统中选中对应文件，内置子资源定位到其所属文件。下方显示节点路径、当前场景与资源路径。已打开的旧面板点击「刷新」即可补上新入口。

索引脚本导出项、相机 FOV、嵌套资源和高级着色器参数，跳过无场景所有者的生成节点。原注释作为说明和搜索词；不复制数值或另存配置。

分类、控制对象与 R 切换规则见 [参数与 Style](../../../../docs/technical/parameters-and-styles.md)。

「人物」搜索“普攻”“弹射挥剑”或“基础剑术”，定位所选场景配置中的 `sword_rules`，统一调整伤害、出手间隔、真实扇区及腰部斜切素材；参数直接编辑该场景的独立资源。

「战斗与成长」搜索“自动目录混合怪潮”调整波次组的混编开关；搜索“怪潮出场权重”调整目录怪物比例，0 排除自动怪潮。新怪登记目录后默认参与，下一局／重试生效。

雾与后处理的独立样板开关、四种配置资源、距离雾曲线、精细密度、泛光阈值、暗部提亮和暗角范围已列为常用视觉参数，见[调节与恢复](../../../../docs/visuals/fog-post-sample.md)。
