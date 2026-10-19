# 战斗功能的共享优化接口

新增怪物、技能和障碍物以这里的公共入口接入。正式地图使用 GDScript，保留原有碰撞、视觉、攻击时序与冻结规则；不增加常驻的全世界刷新器。另有默认关闭的 CPU 原生模拟原型，尚未通过正式接入门槛。示例位于 `demoWithMeowa/1/examples/combat/`，未注册到正式地图、波次或技能池。

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
| 普通追击通路 | `TerrainPath.can_walk_direct()`、`first_walkable_ground(from, targets)` | 共用本步数值输入；后者按顺序返回首个可走候选索引或 -1，并可原地填写候选高度。`targets` 使用调用方独占、复用的 PackedVector3Array |
| 连续碰撞与反射 | `ProjectileCollision.wall_contact()`、`BodyPathPrediction` | 需要接触点、法线和碰撞顺序时沿用真实扫掠；布尔视线不能替代接触结果 |
| 外部位置／聚群参数修改 | `WaveEnemy.commit_spatial_state()` | 修改后、下一次空间查询前调用；普通物理步和出生已自动提交 |
| 在途攻击的生命周期 | `WavePrototype.get_combat_generation()` | 回调／恢复后核对本局攻击代际，并重新检查 `combat_active()`；代际不代表几何或位置没变 |
| 修改一个障碍身体的原生绑定 | `Terrain.prepare_obstacle_change(body)` | 必须在直接修改 shape owner／PhysicsServer 数据之前调用 |
| 修改共享 Shape 资源 | `Terrain.prepare_obstacle_shape_change(shape)` | 修改前撤销所有已烘焙拥有者，覆盖不发 changed 信号的 margin 和底层数据编辑 |
| 替换 Collider 的 Shape 引用 | `Terrain.replace_obstacle_shape(collider, shape)` | 自动先撤销其身体再赋值；Collider 须为 PhysicsBody3D 的直接子节点，返回是否接受 |

障碍通知只操作已存在的缓存，冷地图不为通知而建表。资源变更、变换与节点增删仍沿用观察与实时守卫。撤销的身体暂时保持实时检查，不自动重新烘焙。使用当前地图的 Terrain；跨世界对象和裸 PhysicsServer RID 的登记不在这些 Node 接口的范围内。

普通追击的 `PursuitQueryBatch` 只计算数值数组，不访问场景或物理服务器。TerrainPath 在主线程每物理步准备一次各通行尺寸的查询配置及障碍资格，地面支撑表仅在地形／变换变更后重建。空地直接返回；地面已确认、障碍未确认时只保留实时扫掠／初始接触，避免再查地面。身体的 `flat_ground_height()` 同样复用支撑表，仍按自身半径加留白检查，实际移动和碰撞继续在主线程实时处理。水域、坡地、边界、自定义路径、超大或稀疏地图及未排除的实时身体沿用原流程。固定障碍撤销、增删与地形信号即时使本步输入失效；原生修改仍必须先走上表通知接口。

这只批量处理普通追击的路径前视／让行通路查询，没有把招式状态机、接触伤害或身体求解搬到新内核；不新增线程，也不返回上一物理步的候选结果。内部前缀表是同步只读复用数据，不能直接交给后台长期持有；未来并行还需冻结输入、独立输出和版本核验。`chase_batch_enabled=false` 可在 TerrainPath 上恢复原查询与让行流程，用于同条件对照。

如果修改的是生成地面的身体或共享形状，还会同步撤销平地支撑资格；地面数据与原生碰撞重新由 Terrain 生成器建立一致关系后才能恢复。这样后续功能直接改地面原生碰撞时，不会继续依赖旧的平地证明。

生成地形的 `Generated/Body` 只包含原有地表、河床与崖壁三角面，未架桥水格的阻挡盒独立在 `Generated/WaterBlockers`。所有旱地同高、无桥／坡道且河床不高于旱地时，可取得陆地支撑资格；水池的存在本身不再撤销整张图的资格。局部身体留宽仍由 `TerrainPath` 证明，导航只排除地形面，不排除挡水体；水域反弹通过 `Terrain.is_reflective_water_shape()` 识别，不依赖某个身体固定的 shape 序号。

Terrain 完整重建后，仅向已有障碍缓存登记本次新生成的两个身体，不重新扫描世界，也不重新烘焙外部修改过的旧身体。旧身体退出时释放其 Shape 订阅与拥有者记录；共享 Shape 仍保留其他身体的订阅。水域原生修改只撤销水域的固定证明，修改地形面仍撤销陆地资格；上述修改前通知约定保持。

## 怪物接入

`SlimeEnemy`／`CreatureEnemy` 的存活受击姿态消费既有 `damaged(CombatDamageEvent)`，不增加伤害入口。攻击继续通过 `take_damage(amount, {"direction": horizontal_direction, ...})` 提供世界来向；零方向的旧调用回退人物至怪物的方向。World 在 `PlayerActionVisuals` 独立开启 `enemy_hit_reaction_enabled`，倾斜幅度和回正时间可在参数总览「人物」调整。刚体贴图旋转复用受光、遮挡轮廓、技能补画与倒影的实例参数；不移动根节点、不暂停动画或招式，连续命中接续当前姿态并限幅，致死／取消清理。子类覆写 `_process()` 时也须调用 `_advance_hit_reaction(delta)`；无反应时立即返回，不创建额外逐帧节点。专项无界面回归为 `test_enemy_hit_reaction`，观感在正式地图人工验收。

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

### 怪物集中更新

CPU 原生候选由 `SceneCombatConfiguration.native_swarm_enabled` 单独选择，默认关闭。
加载器仅在显式开启时尝试仓库外层 `native/swarm/hd2d_swarm.gdextension`，DLL 缺失时
继续使用脚本。现有怪物、后续出生和空间索引同时绑定／撤销，七种已知脚本以外的
怪物仍走原实现。它批量计算成对避让，但普通移动仍为逐怪同步调用，导航和地形
资格仍经过原脚本；尚非完整的单批数据模拟。未改变特殊招式、伤害、动画或冻结频率。
构建、平台边界和验证入口见 [`native/swarm/README.md`](../../native/swarm/README.md)。
128 只底座碰撞负例已通过普通移动的人物碰撞隔离修复；当前 World／City 仍未启用
原生候选。固定 CPU 对照与实际渲染帧率分别记录在性能报告中，不能互相换算。

普通追击的平地扫掠排除当前人物；通用物理回退通过 `_slide_ordinary()` 临时加入
人物碰撞例外，并在同步移动结束后撤回。人物近身留白与伤害仍由原有逻辑决定。
不要将该例外永久登记：卷叶虫锁线冲锋通过真实人物碰撞停止并结算伤害。
已有外部登记的碰撞例外由原拥有者管理，不在普通移动结束时擅自删除。

地图战斗配置新增 `centralized_enemy_updates`，默认关闭，World／City 尚未启用。关闭时沿用原有逐节点物理回调。开启后，已确认兼容的七种内置怪物脚本由 `EnemyUpdates` 按登记顺序统一推进；它位于 `EnemyAttacks` 之后，招式、眩晕、外力、鼓舞顺序及每次移动后的空间提交保持。动画仍按原显示频率更新。驱动每波创建和清理，迭代期间出生留到下一次更新，移除立即撤销资格；伤害回调、冻结和切换波次后重新核对战斗状态。这只是回调集中，尚非完整的数据型模拟器，性能结论见 `docs/gameplay/attack-performance.md`。

暂停／恢复怪物模拟统一使用 `enemy.set_wave_tick_enabled(false/true)`，用 `is_wave_tick_enabled()` 查询是否启用；直接操作原生 `set_physics_process()` 只控制独立回调，不能暂停已交给集中驱动的怪物。升级冻结和场景暂停继续使用原有 `process_mode`。手动推进夹具先调用暂停接口，再显式调用其逻辑；不要让独立回调与集中驱动同时拥有同一个对象。

自定义 `WaveEnemy` 默认保留自己的回调；内置脚本白名单之外的 `SlimeEnemy` 子类也不自动接管。新脚本只有在符合共用 `_advance_wave_step()`、无额外 `_physics_process()` 规则，并保持已绑定目标与纯战斗资格接口时，才可覆写 `supports_central_update()` 返回 true。改写了 `WavePrototype` 战斗谓词的自定义控制器不启用此共享资格快路。集中更新期间的外部伤害／冻结／结束继续经过控制器公共入口，不直接改私有战斗状态。

### 蓄力预测内的查询复用

`PlayerActionVisuals.deduplicate_charge_preview` 默认关闭，独立于已有显示请求合并开关；后者合并多次物理显示请求，前者只优化一次同步预测内部的数据读取和障碍查询。真实运动、剑术伤害和实际环绕不消费预测结果。

已知原版控制器／空间索引下，短预测可复用本次提交后的整数槽位、位置和 float64 体型数据，并保持原候选与 BFS 顺序。预测先用一次实时原生体积查询收集相应空间中的障碍形状，再从 PhysicsServer 的实际形状与变换建立保守包围盒；与所有盒子均不相交的射线可共用此次采集结果。有潜在相交、候选缓冲饱和、未知形状或不支持的变换时，继续使用原有精确射线。普通墙与有限镜面使用相同反射掩码。

这份上下文不跨预测、不跨帧、不跨 await 或玩法回调；每次预测重新读取动态墙、镜片和形状原生绑定。它不允许从一次空地结果推断下一帧仍然安全，也不改变可见轮廓、接群规则或展示路线长度。自定义控制器／索引保留原查询路径。

同一预测内，相同位置／半径的邻域候选可被首次轮廓与短弧回退复用；每次遍历重新应用各自的 visited／排除集合，候选顺序和精确距离判定保持。缓存不保存视线、命中或下一帧结果。独立物理线程、非标准地形或改变了墙射线 bodies／areas 语义时保留原预测路径。

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

近身短闪调用 `WaveEnemy.get_contact_feedback_position(origin)` 获取身体接触锚点，头顶伤害数字继续用 `get_damage_feedback_position()`；异形怪可分别覆写，避免把接触特效放到数字位置。持续攻击镜头消费剑术真实命中和 `RicochetStorm.presentation_landed(point, hits, kills, flight_id)`，后者按实际同片落雷合并且冻结中途保留计数，不负责伤害或目标查询。启用持续视觉层次的地图在正常清波后只保留纯视觉反馈短收尾，危险和种子弹丸即时停用；退役视觉仍登记战斗冻结，完成后释放，退出／重试强制清理。

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

默认日志在 `D:\.codexfile\work\combat-framework-checks`，可用 `-LogDirectory` 改动；子进程临时文件使用 `D:\.codexfile\tmp`。入口串行运行接口／两个范例、陆地与挡水分离、普通追击数值批处理、出怪同步、剑术与共享射线、持续绕群／预览、只读预测视图检查，不启动压力或 FPS 采样。非零退出、脚本错误、引擎错误或缺少成功标记均判失败；警告单独显示并保留日志。

新增功能再补充与自身行为有关的用例：同一步出生／移动／死亡、动态薄墙和镜片、冻结／恢复、结束／重试、回调重入，以及资源或查询配置修改。示例验证和公共检查不能代替新功能自己的伤害、轨迹、素材与玩法验收。
