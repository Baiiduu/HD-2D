# 成长选择 UI

正式 World 使用 Meowa 提取的斜切笔触卡框，提供翻牌、选择、确认和重抽；City 保留原青铜样式。初始技能与升级均展示调用方提供的候选，UI 不决定抽取和成长数值。

## 卡框与插画

`huitan/assets/meowa/ui/growth_cards/` 保留普通、史诗、传说、神话各自独立的普通态和选中态母版，共八张 448×576 透明 PNG。实际完整卡框使用其 `full/` 目录下的 448×736 版本：保留上下角原生像素，仅平铺安静的中段延长框体，留出插画与文字空间，没有重新生成美术。原母版、透明度与 UID 保留。

整卡固定划分插画、标题、等级、说明与数值；文本长短不推动插画或标题位置。文字直接显示在原卡纸上，不叠加说明底板、分隔线或黑色键帽，保留原生笔触与纹理。World 单卡不显示底部 1／2／3 或“已选”文字，选中状态由外框高亮表达；数字键选卡仍生效，操作说明保留在整套界面的提示中，City 保留旧卡片提示。效果说明左对齐，数值独立使用暖金色，标签、变化和单位在同一行。正文与数值共用下半部的预留高度；同屏根据最长文案选出共同字号，统一应用到每张卡的正文与数值，最低 14，不再逐卡缩字。标题、等级与品级保留独立层级，重抽或调整卡宽后从配置字号重新计算，不沿用上一轮的缩小结果。不省略收益或上限，完整文案也可通过卡片提示查看。左上与右下保留斜向笔触及少量侵染，选中光边沿整张卡框显示。

正式文案先说明触发条件与效果，再列本次变化；技能续级不重复学习时的机制说明，也不列没有变化的数值。`growth_choice_text.gd` 用一个空行分隔两区，UI 兼容旧候选格式；旧样式按普通换行显示。数值从本轮实际配置与成长预览读取，不改变伤害、抽取或成长规则。动能超载展示低／高速的实际增伤，千手展示总刀数及追加刀伤害，一拳超人首次显示攻速代价、续级不重复减速，全能吸血说明按实际伤害回血且无每秒恢复上限，杀怪加速保留每层独立计时、持续秒数与层数上限。实现用语与重复的突破说明不占卡面，突破仍显示在等级栏，变化值已经包含突破收益。

选中态暖白金边独立于品级；悬停只使用较弱的混合强度。材质仅在外沿混合选中图，插画与文字内页不随选择换图。不预选，重抽后清空选择，未翻开的卡片不点亮。

`GrowthChoiceOption.rarity` 同时提供卡框品级和抽取规则的品阶；默认 AUTO 兼容已有 `epic` 标记，显式品阶优先。World 已登记传说 L01「杀怪加速」，开局可选、十级里程碑保底，已学高品阶的续级按地图权重进入普通池；神话仅预留外观与权重位置。UI 只展示候选，不执行保底或解锁，规则见[本局共有成长](../gameplay/combat-buffs.md)。

`illustration` 是单卡独立插画槽。增益资源经 RunBuffs 复制到候选；技能资源的 `CombatSkillDefinition.illustration` 经 RunSkillManager 和 RunSkillDraft 分别传入升级与开局候选。World 的《奔雷涌潮》已接入用户确认的插画，原图位于 `assets/illustrations/skills/ricochet_storm.png`，保持原始像素与颜色；技能栏仍使用 `icon`。其它卡片留空时沿用原图标并限制显示尺寸，后续逐张设计。中文、品级、等级和快捷提示全部由实际控件使用项目「猫啃什锦黑」字体显示，没有烘焙到卡图。

L01「杀怪加速」使用已确认的 Meowa 金色疾风插画 `assets/illustrations/growth/kill_haste.png`，为 512×448 RGBA PNG，保留真实透明与半透明边缘，无损导入、不生成 mipmaps。开局、学习后的续级与重抽共用资源中的 `illustration`，卡框和边缘过渡沿用现有组件；`icon` 继续保留原靴子图标。该牌只表现疾风与加速，不加入人物或战斗场景；后续卡牌按主题独立设计构图。

P01「伤害提升」使用已确认并经 Meowa 完美像素处理的剑锋碎裂插画 `assets/illustrations/growth/damage.png`，485×422 RGBA PNG，原文件直接无损导入、保留透明背景且不生成 mipmaps。升级与重抽候选共用该资源的 `illustration`，卡片继续使用统一字体、原卡框与边缘过渡，小图标沿用原剑图标。

R01「弹射速度」使用已确认的第二版人物出射插画 `assets/illustrations/growth/launch_speed.png`，经 Meowa 完美像素处理及去背景，为 384×336 RGBA PNG。保留银白发、白金轻甲、酒红披风、双剑与青蓝速度气流，原文件无损导入、不生成 mipmaps。World 的学习、续级与重抽候选共用该资源的 `illustration`，沿用原卡框及边缘过渡；靴子小图标与弹射速度数值保留，City 和共享默认资源保持独立。

R02「动能维持」使用已确认并经 Meowa 完美像素处理的飞轮与循环气流插画 `assets/illustrations/growth/momentum_retention.png`，331×294 RGBA PNG，保留原生像素与透明背景，无损导入、不生成 mipmaps。学习、续级与重抽候选沿 RunBuffs 共用该资源的 `illustration`，保留原星形小图标、卡框与边缘过渡，以及原有动能效率数值。

E01「空间扩张」使用已确认并经 Meowa 完美像素处理的三层斩击弧与空间碎片插画 `assets/illustrations/growth/global_range.png`，459×398 RGBA PNG，原文件无损导入、保留透明背景且不生成 mipmaps。首次获得、续级与重抽沿 RunBuffs 共用该资源的 `illustration`，沿用原剑形小图标、统一字体、史诗卡框与边缘过渡。

E03「千手」与 E04「一拳超人」分别使用 `assets/illustrations/growth/multistrike.png` 和 `heavy_strike.png`，为已确认 Meowa 样张去背景后的 384×336 RGBA PNG。保留手臂刀影、拳头与光效及半透明边缘，不烘焙深蓝底；透明区域直接透出卡纸。首次获得、续级和重抽沿 RunBuffs 共用正式资源的插画槽，原小图标、数值与抽取规则保持。

World「棱光弹射」使用已确认的 Meowa 透明像素插画 `assets/illustrations/skills/prism_ricochet.png`，384×336 RGBA PNG，以金边青蓝棱晶、两次折返光路与碰撞亮点表达机制。先落盘并完成无损导入，再绑定技能 `illustration`；开局、学习和续级共用该图，沿用原卡框与透明边缘过渡，技能栏仍使用原棱晶小图标。City 保留原配置，技能数值与弹丸素材保持。

插画区取消独立黑色底板和内框，扩展到卡面上半部，以保持比例的填充方式显示。`shaders/ui/card_illustration.gdshader` 只羽化图像边缘透明度，露出下方原有卡纸纹理，下缘过渡稍宽；不添加黑色晕影、不改主体颜色。羽化按控件边界计算，适配填充裁切与窗口缩放。原图标、旧样式和未翻开卡背不启用羽化；各卡材质独立，选中光边仍只改变外框。

`scenes/previews/growth_card_workshop.tscn` 为卡片人工预览工作台，F6 对比奔雷涌潮、千手、一拳超人的正式插画与默认、悬停、选中效果，可移动鼠标或点击切换。三张共用正式卡片组件，便于检查场景插画与透明机制插画的卡纸融合，不授予成长或改变抽取规则。整屏背景与其它界面仍由正式 World 显示实际地图。

## 查看与组件结构

运行 `huitan/scenes/world/world.tscn`，普通模式按 F 开始后查看真实初始技能抽牌，升级时查看成长抽牌。巨量怪潮模拟直接采用配置的技能并跳过选卡，查看成长 UI 时应使用普通模式。鼠标选择卡片后确认，也可用方向键切换、Enter 或空格确认；Esc 是否可取消由当前流程决定。旧双空卡演示已清理。

| 组件 | 路径 | 用途 |
| --- | --- | --- |
| 单张可复用卡片 | `scenes/ui/growth_choice_card.tscn` | 独立边框、插画／图标、标题、等级与描述；旧样式保留圆槽 |
| 整套选择界面 | `scenes/ui/growth_choice_ui.tscn` | 标题装饰、候选卡片、确认按钮与已有 UI 音效 |
| 选项数据 | `scripts/ui/growth_choice_option.gd` | Resource：稳定 ID、标题、描述、图标、是否可选 |
| 正式游戏入口 | `scenes/world/world.tscn` | 实际开局技能与升级抽牌 |

卡片按候选动态实例化，新增选项不需要复制面板。内页透明度与选中边框独立调节；World 的标题和确认／重抽按钮复用已存在的 Meowa 红黑笔触素材，背景直接显示实际地图。

## 后续接入接口

将 `growth_choice_ui.tscn` 实例化到需要显示选择界面的场景中；组件默认隐藏。用 `Array[GrowthChoiceOption]` 传入本次候选，通过 `choice_confirmed` 接收选中的稳定标识。

```gdscript
var choice := GrowthChoiceOption.new()
choice.id = &"candidate_a"
# title、description、icon 可以暂时留空。
var choices: Array[GrowthChoiceOption] = [choice]

growth_ui.choice_confirmed.connect(_on_choice_confirmed)
growth_ui.present_choices(choices)
```

`_on_choice_confirmed(option_id: StringName)` 由后续成长系统实现，用于验证候选并实际应用效果。UI 只负责展示与回传，不决定获得时机、抽取规则、技能效果、等级或波次推进。连接信号应在初始化时完成一次，不在每次弹出时重复连接。

| 接口 | 行为 |
| --- | --- |
| `present_choices(options) -> bool` | 翻开本轮卡片，不预选奖励；全部禁用、空列表、空 ID、重复 ID 或其它面板占用输入时返回 false |
| `select_option(option_id) -> bool` | 选中已展示且可用的候选 |
| `get_selected_option()` | 返回当前选项资源，关闭后返回 null |
| `confirm_selection()` | 关闭界面、释放输入占用，再发出 `choice_confirmed(option_id)`；重复调用不重复确认 |
| `cancel()` | 允许取消时关闭并发出 `cancelled`，不发出选择结果 |
| `close()` | 调用方直接关闭，不发出确认或取消结果 |
| `selection_changed(option_id)` | 用户切换候选时发出，便于后续预览或联动 |
| `set_draw_status(remaining, available)` | 显示共用剩余重抽次数与可替换状态；不足池或次数耗尽时禁用 |
| `reroll_requested` | 请求调用方替换本轮卡片，UI 自身不消费次数或授予奖励 |
| `reveal_now()` | 提前结束翻牌，仍保持无选中状态 |

候选生成与效果应用留给正式成长系统。同一轮展示期间不要直接修改候选资源；需要刷新候选时再次调用 `present_choices`。不合法的替换请求保留当前待选内容。若调用方要求必须完成选择，将 `allow_cancel` 设为 false；不据此确定正式玩法中的取消规则。

打开时使用项目已有 `gameplay_input_blockers` 占用人物移动、跳跃与镜头按键，不修改全局暂停状态。天气、环境动画、物理、BGM 和雨风声继续运行；其它系统已设置的暂停也保持原状。背包入口补充了输入占用检查，避免 Tab 或程序调用在选择面板后面打开背包。正式地图的 `WavePrototype/RunGrowth` 在经验升级时调用，协调器只冻结战斗；已接入武器等级及伤害、冷却、范围增益，见 [本局成长](../gameplay/run-growth.md) 和 [本局战斗增益](../gameplay/combat-buffs.md)。

## 可调参数

选中 `growth_choice_ui.tscn` 的根节点 `GrowthChoiceUI`。布局与视觉参数可在编辑器或运行时远程检查器调整；打开场景即可预览空白卡片。`Preview Options` 仅供编辑器，运行时通过接口传入真实候选。

| 参数 | 默认值 | 含义 |
| --- | ---: | --- |
| Ink Style | World 开启，City 关闭 | 启用四品级笔触卡框、独立插画区及红黑标题／按钮 |
| Card Width | World 340，旧样式 280 | 高度按各自素材比例计算；整套界面等比适配窗口 |
| Card Gap | World 28，旧样式 64 | 相邻卡片间距 |
| Screen Margin | `(24, 24)` | 窄窗口适配时预留的最小边距 |
| Center Offset | `(0, 0)` | 整套界面相对屏幕中心的偏移，仍限制在安全区域内 |
| Button Width | 244 | 确认按钮宽度，高度按素材比例计算 |
| Background Opacity | World 0.96，旧样式 0.86 | 内页叠在暗底上保证文字可读，边框与光边保持 |
| Selection Strength | 1.0 | 普通与选中纹理的混合强度；悬浮时使用较轻的高亮 |
| World Dim Opacity | 0.0 | 整屏暗化程度，默认直接显示游戏世界 |
| Title / Confirm Text | 选择成长方向 / 确认 | 动态标题和按钮文字 |
| Title Font Size | 40 | 界面上方标题字号 |
| Content Font Size | 20 | 正文与数值的首选字号；笔触卡标题增加 7，旧样式增加 4，长文本在各自区域内适配 |
| Card Text Color | 暖白 | 实际候选标题与描述颜色，配轻阴影提高透明卡面上的可读性 |
| Confirm Font Size | 32 | 确认按钮独立字号 |
| Allow Cancel | true | 是否接受 Esc 取消，由正式调用方决定 |
| Open Duration | 0.18 秒 | 渐显与每张翻开时长，卡片依次错开 0.05 秒；0 立即显示 |
| Hover Duration | 0.12 秒 | 悬浮和选中高亮的过渡时长，0 立即切换 |

`UIAudio` 子节点接入共用语义操作映射：鼠标进入可用卡片或按钮提示 `navigate`，鼠标及数字键／方向键明确选卡使用 `choice`，确认和 Esc 取消使用 `confirm`／`close`。在卡内持续移动、程序换牌、未揭晓及禁用控件不追加悬停音；重抽只沿原成功事件播放核心换牌和揭晓，确认保留原成长生效音。复用既有 Meowa 音源、声音池、限频和 UI 混音，可独立调整开关、总增益与声音资源，见 `docs/audio/ui-audio.md`。

## 验证

无界面检查：`test_growth_card_copy` 检查伤害区间、刀数、首次重击代价、全能吸血无每秒上限与击杀加速限制，并确认文案随实际规则变化；`test_skill_card_illustration` 覆盖真实技能插画在开局、学习、升级中的传递与原图标保留，以及翻牌／旧样式的材质切换；`test_growth_card_presentation` 覆盖文字分区与旧格式兼容、显式品阶与旧史诗标记兼容、材质隔离、统一字体、选择与重抽、未翻牌高亮以及 World／City 独立启用；`test_growth_choice_ui` 继续覆盖原输入、确认和取消流程。抽取、史诗与传说成长另有对应逻辑测试；对应品阶耗尽时由成长流程回退到低阶有效候选，标题随实际候选调整；只有整轮合法候选全部耗尽才跳过，不打开空选择面板。

新卡框的实际比例、插画留白、长说明可读性、悬停与选中辉光、翻牌和小窗口观感仍待人工验收。使用 World 正常模式按 F 开始并查看升级；没有运行自动渲染窗口或截图测试。鼠标或数字键／方向键选择，Enter 确认，R 重抽；翻牌阶段点击或确认键只提前揭晓。
