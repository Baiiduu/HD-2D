# 项目文档

当前 Godot 项目：`demoWithMeowa/1`。正式地图集中在战斗区与外围绕行带，视觉测试地图独立维护。本体蓄力弹射、墙面反弹与同旋向切线拨怪已接入；人物自带普攻和弹射挥剑独立于 A01，并与已有自动技能共享局内属性增益。设计提案与实际接入状态分别标明。

总体玩法与战斗核心设计保留在本目录，便于持续讨论。其余文件按用途分组：

| 目录 | 内容 |
| --- | --- |
| `gameplay/` | 波次、攻击、成长、人物动作与保留的玩法原型 |
| `visuals/` | 地图、材质、光影、植被与环境表现 |
| `ui/` | 界面、HUD 与交互说明 |
| `audio/` | 动作和 UI 声音说明，战斗声音接口见自动扇击文档 |
| `technical/` | 参数入口、性能、制作教程与问题反馈 |
| `media/` | 实机截图、动画、试听，保留各功能原有预览目录名 |
| `references/` | 已确认参考、界面部件展示与原始反馈证据 |
| `archive/` | 已结束的历史设计 |

当前项目入口和代码目录见 [仓库说明](../README.md) 与 [Godot 目录说明](../demoWithMeowa/1/README.md)。

## 玩法与地图

| 文档 | 内容 |
| --- | --- |
| [当前玩法与实现状态](rpg-game-design.md) | 手动普攻与本体弹射的确认范围、已接入原型及待定规则 |
| [人物本体弹射框架](gameplay/player-ricochet.md) | 右键蓄力、胶囊反弹、同向切线拨怪、五类动作资源槽与试玩参数 |
| [人物自带基础剑术](gameplay/player-sword.md) | 左键普攻、弹射自动挥剑、真实连续命中与共享属性；当前独立剑光停用 |
| [伤害数字框架](gameplay/damage-numbers.md) | 真实伤害事件、可替换样式、弹跳错位、旋转投影、冻结与节点复用 |
| [战斗内容候选](combat-core-design.md) | 原自动攻击方案的怪物、攻击、增益与构筑讨论池；具体数量与规则继续讨论 |
| [趣味海克斯提案](hex-system-proposal.md) | 阵法边界、地陷、庇护与上一局援场等候选，尚未接入 |
| [南侧战斗区域搭建参考](gameplay/battle-area-plan.md) | 保留早期扩展布局和试走基线；当前范围与入口见正式地图说明 |
| [波次循环灰盒](gameplay/wave-graybox.md) | 操作、敌人与基础攻击参数；挑战 UI 当前默认隐藏 |
| [怪物刷新与波次基础](gameplay/wave-spawning.md) | 小股与怪潮交替、首波十只集中进场、整批容量预留、安全刷新与扩展接口 |
| [怪物接入与大规模框架](gameplay/enemy-framework.md) | 统一怪物目录与数值、正式渐进 128 档、1～10 倍生命成长、512／768 扩展档位及待验收性能目标 |
| [A01 自动扇击](gameplay/fan-auto-attack.md) | 本局技能框架、八级扇击／连斩／持续旋转、真实升级卡与实机动画 |
| [棱光弹射](gameplay/prism-ricochet.md) | 连续球形碰撞、真实墙面反射、八级晶体齐射、折线拖尾与实机预览 |
| [A02 雷光贯穿](gameplay/light-pierce.md) | 四级实际贯穿成长、墙体阻挡、原生像素雷刺、断续电光尾迹与命中电弧 |
| [反射镜印](gameplay/mirror-mark.md) | 四级镜梭成长、怪物贴印与固定法线反射、致死碎裂和人物像素匹配 |
| [奔雷涌潮](gameplay/ricochet-storm.md) | 独立弹射雷电技能、同片多目标、分层扩散、真实挡墙、四级成长与实机预览 |
| [本局经验与抽卡成长](gameplay/run-growth.md) | 经验吸取、初始技能与升级三选一、共用三次重抽、连续升级和战斗冻结 |
| [本局战斗增益](gameplay/combat-buffs.md) | 伤害、冷却、范围的升级卡、叠加、封顶与参数调节 |
| [无尽波次](gameplay/endless-waves.md) | 无限续波、清波休整、数量和节奏增长、上限与参数 |
| [地图效果接入](visuals/map-effects.md) | 通用效果场景、正式地图连接与调节入口 |
| [参数总览与 Style](technical/parameters-and-styles.md) | Godot 七类参数入口、控制对象、R 切光影天气与 T 重试 |
| [计分、得分 HUD 与排行榜接口](technical/leaderboard-api.md) | 真实击杀与清波计分、数字动效、独立后端及 PostgreSQL 部署；登录与上传待定 |
| [游戏启动性能](technical/startup-performance.md) | 正式地图草花区域检索瓶颈、优化前后计时与后续方案 |
| [攻击性能与资源复用](gameplay/attack-performance.md) | A01 网格与查询优化、A02 拖尾及星芒复用、敌方受击资格和后续攻击要求 |
| [正式地图说明](../demoWithMeowa/1/scenes/world/README.md) | 当前战斗区、外围绕行带、弹射障碍与手绘地表 |
| [地表画笔](../demoWithMeowa/1/addons/terrain_painter/README.md) | 地表绘制、画笔配置、保存与撤销 |
| [编辑器地图切换](../demoWithMeowa/1/addons/map_switcher/README.md) | 打开、运行与设置默认开发地图 |
| [训练小屋](gameplay/training-hut.md) | 保留原型的交互、属性、建筑参数与存档；已退出正式地图 |
| [第一只史莱姆](gameplay/first-slime.md) | 外观、巡逻与追踪；正式战斗使用波次组件的生命与接触伤害 |
| [种植操作](gameplay/farming.md) | 保留的锄地、播种、浇水原型；本次 Demo 暂不纳入 |
| [种植交互提示](ui/farming-ui.md) | 保留的像素提示原型；本次 Demo 暂不纳入 |
| [3D 豌豆射手视觉原型](gameplay/peashooter.md) | 保留的体积与材质预览；本次 Demo 暂不纳入 |

## 人物与界面

| 文档 | 内容 |
| --- | --- |
| [人物跳跃与下落](gameplay/player-jump.md) | 动画、跳跃物理与台阶通行 |
| [人物瞬移闪身](gameplay/player-dodge.md) | 位移、碰撞、残影、音效与环境反馈 |
| [人物受光](visuals/character-lighting.md) | 侧光、背光与亮边参数 |
| [玩家与怪物遮挡轮廓](visuals/player-occlusion.md) | 建筑遮挡、动画帧采样与轮廓参数 |
| [人物、装备与技能界面](ui/equipment-skills-ui.md) | 管理页配置、手帐动效与历史技能测试说明 |
| [背包与物品快捷栏](ui/inventory-ui.md) | 库存、分类、物品栏与使用入口 |
| [人物属性条](references/player-bars-reference/README.md) | 真实生命与魔力绑定、接口及布局参数 |
| [技能栏](ui/skill-hud.md) | 已确认的槽位外框、本局技能图标与等级、视觉参数 |
| [UI 操作音效](audio/ui-audio.md) | 共用声音、操作对应与音量配置 |
| [人物动作音效](audio/movement-audio.md) | 地表脚步过渡、起跳与落地 |
| [背景音乐与曲池](audio/background-music.md) | 探索／战斗状态选曲、双路衔接、曲池扩展与参数入口 |

## 视觉与声音

| 文档 | 内容 |
| --- | --- |
| [项目视觉设计](visuals/visual-design.md) | Lumina 原则在当前家园、连续地图与战斗内容中的应用、实际基准和后续视觉优先级 |
| [草地与光照明暗层次](visuals/value-lighting-sample.md) | 保留草底中间色、拓宽草花色阶、暖主光与冷色半球补光，以及原版切换与同机位实机 |
| [雾与后处理细调](visuals/fog-post-sample.md) | 四种 Style 的近处去灰、远雾、泛光、暗部提亮与暗角；独立恢复、参数及小院／战区同机位对照 |
| [Style 主光与后处理修复](visuals/style-light-repair.md) | 修复三种风格共用暖主光的回归，保留原始实际光影；实机前后对照 |
| [原始光影增强](visuals/original-light-refinement.md) | 改善昏暗、强化明暗交界、统一主光与局部暖光方向；独立开关与实机对照 |
| [HD-2D 视觉复刻教程](technical/hd2d-visual-tutorial.md) | 分阶段实现方法、提示词、参数与拍摄检查 |
| [地图局部光斑](visuals/map-accent-light.md) | 保留的氛围参数与预览；正式地图关闭自动地面光斑 |
| [远景空气光](visuals/atmospheric-light.md) | 保留的光束、辉光与体积散射参数；正式地图关闭远景装饰灯 |
| [草地光影](visuals/grass-lighting.md) | 草丛受光、程序化法线与旋转时的阴影 |
| [像素美术统一样板](visuals/pixel-art-sample.md) | 草地、卵石路、墙面、屋瓦的像素尺度、实机对比与检查器材质切换 |
| [材质色阶统一](visuals/pixel-color-ramps.md) | 四类材质各五档底色、同机位实机对比与色板调节 |
| [草地与花草样板](visuals/foliage-visual-sample.md) | 草底对比、花草五色色阶、同色花簇与密度；实机对比及恢复入口 |
| [小院浓绿林缘样板](visuals/courtyard-foliage.md) | 八种 Meowa 蕨草、阔叶和长草、局部茂密铺设与边缘过渡；开关和同机位实机 |
| [环境动态的时段与区域差异](visuals/environment-dynamics.md) | 自然风、光点的时段渐变和家园／战区差异，保留统一雨量；参数与动态实机 |
| [边缘、植被与受光](visuals/surface-integration.md) | 路边草缘、台地衔接、簇内层次及地表／建筑／人物独立法线；实机图与恢复参数 |
| [萤火虫](visuals/fireflies.md) | 光点颜色、亮度、大小与明暗变化 |
| [水面与湿地面光照](visuals/water-lighting.md) | 水体波光，以及当前战区的薄湿膜、路灯／点光源倒影与波纹参数 |
| [泡沫与水花](visuals/water-foam.md) | 颜色、尺度、岸边与瀑布落点 |
| [瀑布表现](visuals/waterfall-visuals.md) | 水帘与首版实现说明 |
| [日照演示](visuals/daylight-preview.md) | 保留作对照的可选功能，默认关闭 |
| [BGM 与风声](../demoWithMeowa/1/assets/meowa/audio/README.md) | 音源、循环淡化与试听 |
| [全局战斗音效](gameplay/fan-auto-attack.md#全局战斗音效管理) | 共享预算、优先级、密集合并、人物听觉中心、分组混音及新攻击接入 |
| [细雨与天气](../demoWithMeowa/1/assets/meowa/weather/README.md) | 雨声、镜头水滴及天气配置 |

## 历史参考与反馈

- [仙门灯会历史方案](archive/lantern-festival-design.md)：保留早期设计供参考，不作为当前世界题材或实现要求。
- [本体弹射概念图](references/body-ricochet/)：蓄力、动作与场景玩法参考；当前运动框架见人物本体弹射文档，参考图不作为动画帧。
- [Meowa 动画反馈](technical/meowa-animation-feedback.md)：原始观察、调用证据与已接入结果。[证据包](references/meowa-animation-feedback.zip) 和 [原始证据目录](references/meowa-animation-feedback/) 保留。
- 已确认的界面参考与提取组件：[装备与技能](references/equipment-skills-reference/)、[背包](references/inventory-reference/)、[人物属性条](references/player-bars-reference/) 与 [技能栏参考图](media/skill-hud-preview/reference.png)。

## 目录维护

功能说明和仍被引用的实机图片、动画、试听保留在这里。一次性截图、检查脚本、分析结果和临时下载放到 `D:\.codexfile\work\<任务名>`；历史设计放到 `archive/`，并标明适用范围。

功能文档记录当前用法、接口和必要对照，避免重复总体设计或堆积任务流水。未接入的玩法标明提案，保留原型与历史参考注明适用范围。
