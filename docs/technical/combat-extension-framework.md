# 战斗功能的共享优化接口

新增怪物、技能和障碍物以这里的公共入口接入。当前实现使用纯 GDScript，保留原有碰撞、视觉、攻击时序与冻结规则；不增加常驻的全世界刷新器。示例位于 `demoWithMeowa/1/examples/combat/`，未注册到正式地图、波次或技能池。

## 场景配置与启动

World 与 City 分别以 `data/combat/scenes/world/configuration.tres`、`data/combat/scenes/city/configuration.tres` 为实际配置来源。场景中的 `BattleConfiguration` 在人物和战斗组件进入树前绑定独立资源；修改旧的 `data/player/`、`data/enemies/` 等共享模板不会自动更新这两张地图。兼容表现与启动开关时保留两张地图当前的战斗数值和怪群避让，不将共享模板的新平衡覆盖进独立配置；不能只检查共享模板或 Inspector 中尚未绑定的旧引用。

F5 启动 World，采用普通战斗：Game Manager 的升级、抽卡和局内技能管理器三个项目开关均开启，仍须与各组件本地 `enabled` 同时生效。修改项目开关后重新运行；怪潮模拟由地图自身 `population_rules.simulation_mode` 单独开启，模拟直接配装、免伤和锁血，不经过正常初选与成长流程。World 保留自动环绕、基础剑术、奔雷与渐进怪潮，极光由 `MapEffects/Aurora` 明确开启，火带／反弹素材和剑光由 World 的人物资源选择；City 继续使用自己的配置和表现开关。

`Player/CharacterSkillManager` 只管理本体弹射与 `Dash`；Dash 沿用 `PlayerBlink` 和 `blink` 输入，即 Shift 闪身，无需抽卡。基础剑术是独立基础动作，`WavePrototype/RunSkillManager` 管理五种局内可选技能，`SkillDraft` 管理选卡交互，`RunGrowth` 管理经验和升级。旧 `RunSkills` 脚本保留兼容入口。

`tests/test_world_startup.gd` 检查落盘项目开关、World 的实际资源绑定、极光材质与时钟、初选和首次升级，并确认 City 独立配置保留；统一测试入口为 `tools/run_tests.ps1 -Test test_world_startup -UseProjectSystemSwitches`。该回归只检查无界面逻辑与数据，画面、动画和战斗手感仍须人工试玩。

## 接入入口

下列源码路径相对于 Godot 项目 `demoWithMeowa/1`。

| 需求 | 公共入口 | 约定 |
| --- | --- | --- |
| 少量找怪 | `WavePrototype.get_nearby_enemies(point, radius)` | 返回新的局部候选数组，招式自行检查激活、距离、高差与命中资格 |
| 高频找怪 | `WavePrototype.get_nearby_enemies_into(point, radius, excluded_ids, result)` | 清空并填充调用方缓冲，顺序与前者一致；排除 ID 在读取实时位置前过滤 |
| 挡墙／视线 | `Terrain.ray_clear(from, to, mask, excluded_rids)` | 普通攻击使用掩码 1，含真实镜片的环绕查询使用 `ProjectileCollision.REFLECTION_MASK`；身体射线默认规则，不查询 Area |
| 地面资格 | `TerrainPath.flat_ground_height()`、`flat_center_ground_height()` | `NAN` 表示不能证明；前者保留身体宽度，后者仅代替原中心采样；它们不证明没有墙 |
| 连续碰撞与反射 | `ProjectileCollision.wall_contact()`、`BodyPathPrediction` | 需要接触点、法线和碰撞顺序时沿用真实扫掠；布尔视线不能替代接触结果 |
| 外部位置／聚群参数修改 | `WaveEnemy.commit_spatial_state()` | 修改后、下一次空间查询前调用；普通物理步和出生已自动提交 |
| 在途攻击的生命周期 | `WavePrototype.get_combat_generation()` | 回调／恢复后核对本局攻击代际，并重新检查 `combat_active()`；代际不代表几何或位置没变 |
| 修改一个障碍身体的原生绑定 | `Terrain.prepare_obstacle_change(body)` | 必须在直接修改 shape owner／PhysicsServer 数据之前调用 |
| 修改共享 Shape 资源 | `Terrain.prepare_obstacle_shape_change(shape)` | 修改前撤销所有已烘焙拥有者，覆盖不发 changed 信号的 margin 和底层数据编辑 |
| 替换 Collider 的 Shape 引用 | `Terrain.replace_obstacle_shape(collider, shape)` | 自动先撤销其身体再赋值；Collider 须为 PhysicsBody3D 的直接子节点，返回是否接受 |

障碍通知只操作已存在的缓存，冷地图不为通知而建表。资源变更、变换与节点增删仍沿用观察与实时守卫。撤销的身体暂时保持实时检查，不自动重新烘焙。使用当前地图的 Terrain；跨世界对象和裸 PhysicsServer RID 的登记不在这些 Node 接口的范围内。

如果修改的是生成地面的身体或共享形状，还会同步撤销平地支撑资格；地面数据与原生碰撞重新由 Terrain 生成器建立一致关系后才能恢复。这样后续功能直接改地面原生碰撞时，不会继续依赖旧的平地证明。

生成地形的 `Generated/Body` 只包含原有地表、河床与崖壁三角面，未架桥水格的阻挡盒独立在 `Generated/WaterBlockers`。所有旱地同高、无桥／坡道且河床不高于旱地时，可取得陆地支撑资格；水池的存在本身不再撤销整张图的资格。局部身体留宽仍由 `TerrainPath` 证明，导航只排除地形面，不排除挡水体；水域反弹通过 `Terrain.is_reflective_water_shape()` 识别，不依赖某个身体固定的 shape 序号。

Terrain 完整重建后，仅向已有障碍缓存登记本次新生成的两个身体，不重新扫描世界，也不重新烘焙外部修改过的旧身体。旧身体退出时释放其 Shape 订阅与拥有者记录；共享 Shape 仍保留其他身体的订阅。水域原生修改只撤销水域的固定证明，修改地形面仍撤销陆地资格；上述修改前通知约定保持。

## 怪物接入

[`shared_chase_enemy.gd`](../../demoWithMeowa/1/examples/combat/shared_chase_enemy.gd) 是可执行的最小追击范例：继承 `CreatureEnemy`，只覆写 `_combat_tick()`，复用普通追击、真实接触伤害及反馈池。以已有 Creature 场景的副本作为素材与身体结构，保留其 Sprite 和 Collision，再替换副本的脚本。

继承层负责出生登记、普通 tick 后提交、死亡／取消／退出撤索引、眩晕、冻结检查及资源复用。覆写 `configure_wave()`、`_ready()`、`_physics_process()` 或 `_exit_tree()` 时必须保留对应 `super` 调用；通常只改行为 tick 即可。新定义与场景通过既有 EnemyCatalog／波次框架登记，具体规则见[怪物框架](../gameplay/enemy-framework.md)。

外部瞬移或自定义运动完成时：

```gdscript
# 先按该动作自己的规则处理轨迹、碰撞、速度及已有寻路状态。
enemy.global_position = destination
enemy.reset_physics_interpolation()
enemy.commit_spatial_state()
```

`commit_spatial_state()` 只发布当前位置、激活状态、体型和间距，不实现瞬移玩法，不重置招式或绕过地面碰撞。体型、聚群间距或激活状态直接修改后也使用此入口。继承的正常提交已有一次，外部中途变更才需要额外提交；不在每次查询前同步全场。

## 技能接入

[`shared_query_skill.gd`](../../demoWithMeowa/1/examples/combat/shared_query_skill.gd) 演示由拥有者推进冷却、手动请求一次单目标攻击。它没有自动施放或空闲逐帧回调，也不加入成长池。范例顺序是：

1. 先检查战斗资格、冷却与输入数值。
2. 用自己的数组收集局部候选，再检查激活、高差和共享挡墙查询。
3. 结束候选迭代、清空缓冲，再进入可能触发死亡／升级／重试的伤害回调。
4. 回调前预留冷却，防止同一步重入；使用 `take_damage()`，沿用真实伤害事件。

拥有者在战斗物理步调用 `advance(delta)`，在真正的施放请求到来时调用 `strike_one()`；结束／重试调用 `cancel_current()`。范例会在冻结时停冷却且拒绝攻击。正式自动技能继续使用既有技能定义、`get_skill_definition()`／`apply_skill_level()`、战斗节点登记与结束清理接口；示例不替这些玩法规定学习方式、攻击间隔或目标排序。

多目标、弹丸和分层技能在死亡／升级回调后必须重新检查当前资格和 `get_combat_generation()` 返回的攻击代际。结束、重试和清理攻击根会更新代际，冻结本身不更新；这个值不能作为墙体、地形或怪物位置的缓存键。需要冻结后继续的批次保存处理游标与剩余预算，恢复时继续，不能简单重打整轮。缓冲只属于一次同步候选收集；不要在持有它的迭代中递归填充同一个数组，也不要把它作为跨帧快照。

## 缓存与障碍修改

```gdscript
# 替换一个碰撞节点的绑定：自动先撤销。
terrain.replace_obstacle_shape(collision, replacement)

# 同一资源可能被多个身体共用：先撤销所有拥有者，再改原生参数。
terrain.prepare_obstacle_shape_change(shared_shape)
shared_shape.margin = new_margin

# 直接编辑一个身体的原生 shape owner：先撤销其固定证明。
terrain.prepare_obstacle_change(body)
body.shape_owner_add_shape(owner_id, extra_shape)
```

只有固定几何、地面资格和有明确期限的配置允许复用。视线、动态墙体和镜片结果每次实时检查；证明不足走原生回退。直接修改导航私有查询配置时沿用 `TerrainPath.invalidate_query_certificate()` 的同一步失效约定。不能把某个身体的尺寸证明用于其它半径，也不能从空地证明推导攻击命中。

## 表现和诊断

怪物反馈复用 `EnemyFeedbackPool`；战斗声音走 `MapEffects/GameAudio.request()` 的预算、优先级与混音；伤害数字来自真实扣血事件并使用 `DamageNumbers` 的节点池。新增技能特效可沿用已有 LightPierce／Prism／Storm 的共享材质和节点池方式，保持原生像素、遮挡和完整动画，结束后停处理。按需要复用现有池，不额外创建一个通用池管理器。

```gdscript
terrain.reset_query_metrics()
terrain.query_diagnostics_enabled = true
# 正常执行要检查的功能；计数本身不发起查询。
var counts := terrain.get_query_metrics()
terrain.query_diagnostics_enabled = false
```

`ray_requests = ray_certified + ray_native`，分别表示请求数、空地证明通过数、原生回退数。默认不计数，没有采集节点或逐帧回调；仅在读取时构造统计 Dictionary。怪群继续使用 `CrowdBatchEnemySpatialIndex` 的现有 opt-in 计数，数字池用 `get_pool_stats()`，声音用 `GameAudio.get_debug_state()`。这些都是调用与存储计数，不是 CPU 耗时或 FPS。

## 功能验证入口

在 Godot 项目目录运行，Godot 路径按本机安装位置传入：

```powershell
pwsh -File .\tools\validate_combat_framework.ps1 -GodotPath 'D:\Project\godot\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe'
```

默认日志在 `D:\.codexfile\work\combat-framework-checks`，可用 `-LogDirectory` 改动；子进程临时文件使用 `D:\.codexfile\tmp`。入口串行运行接口／两个范例、陆地与挡水分离、出怪同步、剑术与共享射线、持续绕群／预览、只读预测视图检查，不启动压力或 FPS 采样。非零退出、脚本错误、引擎错误或缺少成功标记均判失败；警告单独显示并保留日志。

新增功能再补充与自身行为有关的用例：同一步出生／移动／死亡、动态薄墙和镜片、冻结／恢复、结束／重试、回调重入，以及资源或查询配置修改。示例验证和公共检查不能代替新功能自己的伤害、轨迹、素材与玩法验收。
