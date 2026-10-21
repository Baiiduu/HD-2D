# 项目文档

当前 Godot 项目：`demoWithMeowa/1`，F5 运行正式地图，活动范围为 32×32 米战斗核心，视觉测试地图独立维护。本体蓄力弹射、墙面反弹与怪群外沿自动环绕已接入，正式拨怪关闭；人物自带普攻和弹射挥剑独立于 A01，并与已有技能共享局内属性增益。设计提案与实际接入状态分别标明。

总体玩法与战斗核心设计保留在本目录，便于持续讨论。其余文件按用途分组：

| 目录 | 内容 |
| --- | --- |
| `gameplay/` | 波次、攻击、成长与人物动作 |
| `visuals/` | 地图、材质、光影、植被与环境表现 |
| `ui/` | 界面、HUD 与交互说明 |
| `audio/` | 动作和 UI 声音说明，战斗声音接口见自动扇击文档 |
| `technical/` | 参数入口、性能、制作教程与问题反馈 |
| `media/` | 功能截图、动画与试听；不保留旧地图过程截图 |
| `references/` | 已确认参考、原始美术试作、界面部件展示与反馈证据；试作不代表正式采用 |

当前项目入口和代码目录见 [仓库说明](../README.md) 与 [Godot 目录说明](../demoWithMeowa/1/README.md)。

## 玩法与地图

| 文档 | 内容 |
| --- | --- |
| [当前玩法与实现状态](rpg-game-design.md) | 手动普攻与本体弹射的确认范围、已接入原型及待定规则 |
| [人物本体弹射框架](gameplay/player-ricochet.md) | 右键蓄力、胶囊反弹、怪群外沿与自动环绕、动作资源槽与试玩参数 |
| [人物自带基础剑术](gameplay/player-sword.md) | 左键普攻、弹射自动挥剑、真实连续命中与共享属性；表现由各地图资源独立选择 |
| [伤害数字框架](gameplay/damage-numbers.md) | 真实伤害事件、可替换样式、弹跳错位、旋转投影、冻结与节点复用 |
| [战斗内容候选](combat-core-design.md) | 原自动攻击方案的怪物、攻击、增益与构筑讨论池；具体数量与规则继续讨论 |
| [趣味海克斯提案](hex-system-proposal.md) | 阵法边界、地陷、庇护与上一局援场等候选，尚未接入 |
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
| [参数总览、画质与 Style](technical/parameters-and-styles.md) | 编辑器参数入口、游戏内画质选项含义、全屏分辨率、R 切光影天气与 T 重试 |
| [计分、得分 HUD 与排行榜接口](technical/leaderboard-api.md) | 真实击杀与清波计分、数字动效、独立后端及 PostgreSQL 部署；登录与上传待定 |
| [游戏启动性能](technical/startup-performance.md) | 正式地图草花区域检索瓶颈、优化前后计时与后续方案 |
| [CPU 与 GPU 性能优化](gameplay/attack-performance.md) | 独立隔离方法、当前证据、复现入口与完整 128 怪验收；区分降画质和实现收益 |
| [正式地图说明](../demoWithMeowa/1/scenes/world/README.md) | 当前战斗核心、弹射障碍与手绘地表 |
| [地表画笔](../demoWithMeowa/1/addons/terrain_painter/README.md) | 地表绘制、画笔配置、保存与撤销 |
| [编辑器地图切换](../demoWithMeowa/1/addons/map_switcher/README.md) | 打开、运行与设置默认开发地图 |
| [第一只史莱姆](gameplay/first-slime.md) | 外观、巡逻与追踪；正式战斗使用波次组件的生命与接触伤害 |

## 人物与界面

| 文档 | 内容 |
| --- | --- |
| [动态主菜单](ui/main-menu.md) | 回弹标题、分层弹射与近景击飞、按钮反馈、设置及入场交接 |
| [人物跳跃与下落](gameplay/player-jump.md) | World 暂时关闭跳跃与自动迈步，保留原型动作和参数参考 |
| [人物瞬移闪身](gameplay/player-dodge.md) | 位移、碰撞、残影、音效与环境反馈 |
| [人物受光](visuals/character-lighting.md) | 侧光、背光与亮边参数 |
| [玩家与怪物遮挡轮廓](visuals/player-occlusion.md) | 建筑遮挡、动画帧采样与轮廓参数 |
| [人物、装备与技能界面](ui/equipment-skills-ui.md) | 管理页配置、手帐动效与历史技能测试说明 |
| [背包与物品快捷栏](ui/inventory-ui.md) | 库存、分类、物品栏与使用入口 |
| [人物属性条](references/player-bars-reference/README.md) | 真实生命与魔力绑定、接口及布局参数 |
| [技能栏](ui/skill-hud.md) | 已确认的槽位外框、本局技能图标与等级、视觉参数 |
| [UI 操作音效](audio/ui-audio.md) | 共用声音、操作对应与音量配置 |
| [人物动作音效](audio/movement-audio.md) | 地表脚步过渡、起跳与落地 |
| [角色动画试作报告](visuals/character-animation/character_animation_attempts_report.md) | 多分支试作、失败与限制；[离线 HTML](visuals/character-animation/character_animation_attempts_report.html)，配套原图与中间产物集中在 `references/character-animation/` |
| [背景音乐与曲池](audio/background-music.md) | 探索／战斗状态选曲、双路衔接、曲池扩展与参数入口 |

## 视觉与声音

| 文档 | 内容 |
| --- | --- |
| [项目视觉设计](visuals/visual-design.md) | 当前同高战区、城市建筑、光影与战斗可读性的视觉基线 |
| [城市建筑制作规范](visuals/building-production-guide.md) | 三视图、风格与各面布局先确认，整套贴图一次生成，模型、UV、材质、人工验收与积分说明 |
| [Meowa 音效制作与接入指南](audio/meowa-sfx-production-guide.md) | 画面特征与提示词审核、即时起声、成套音色、变体一致性、响度、积分控制与实战验收 |
| [HD-2D 视觉复刻教程](technical/hd2d-visual-tutorial.md) | 分阶段实现方法、提示词、参数与拍摄检查 |
| [地图局部光斑](visuals/map-accent-light.md) | 保留的氛围参数与预览；正式地图关闭自动地面光斑 |
| [远景空气光](visuals/atmospheric-light.md) | 保留的光束、辉光与体积散射参数；正式地图关闭远景装饰灯 |
| [草地光影](visuals/grass-lighting.md) | 草丛受光、程序化法线与旋转时的阴影 |
| [环境动态的时段与区域差异](visuals/environment-dynamics.md) | 共享自然风与光点倍率、地图独立区域配置，保留统一雨量 |
| [萤火虫](visuals/fireflies.md) | 光点颜色、亮度、大小与明暗变化 |
| [水面与湿地面光照](visuals/water-lighting.md) | 水体波光，以及当前战区的薄湿膜、路灯／点光源倒影与波纹参数 |
| [泡沫与水花](visuals/water-foam.md) | 颜色、尺度、岸边与瀑布落点 |
| [瀑布表现](visuals/waterfall-visuals.md) | 水帘与首版实现说明 |
| [BGM 与风声](../demoWithMeowa/1/assets/meowa/audio/README.md) | 音源、循环淡化与试听 |
| [全局战斗音效](gameplay/fan-auto-attack.md#全局战斗音效管理) | 共享预算、优先级、密集合并、人物听觉中心、分组混音及新攻击接入 |
| [细雨与天气](../demoWithMeowa/1/assets/meowa/weather/README.md) | 雨声、镜头水滴及天气配置 |

## 历史参考与反馈

- [本体弹射概念图](references/body-ricochet/)：蓄力、动作与场景玩法参考；当前运动框架见人物本体弹射文档，参考图不作为动画帧。
- [Meowa 动画反馈](technical/meowa-animation-feedback.md)：原始观察、调用证据与已接入结果。[证据包](references/meowa-animation-feedback.zip) 和 [原始证据目录](references/meowa-animation-feedback/) 保留。
- 已确认的界面参考与提取组件：[装备与技能](references/equipment-skills-reference/)、[背包](references/inventory-reference/)、[人物属性条](references/player-bars-reference/) 与 [技能栏参考图](media/skill-hud-preview/reference.png)。

## 目录维护

功能说明和仍被引用的实机图片、动画、试听保留在这里。一次性截图、检查脚本、分析结果和临时下载放到 `D:\.codexfile\work\<任务名>`。过时地图方案与过程截图不再保留；历史可从 Git 记录追溯。

功能文档记录当前用法、接口和必要对照，避免重复总体设计或堆积任务流水。未接入的玩法标明提案，保留原型与历史参考注明适用范围。
