# 项目文档

当前 Godot 项目：`demoWithMeowa/1`。正式连续地图与视觉测试地图分开维护；设计草案中的建议和灰盒数值仍可调整。

## 玩法与地图

| 文档 | 内容 |
| --- | --- |
| [慢节奏波次生存草案](rpg-game-design.md) | 已确认方向、核心内容规模与后续候选；本轮不估算工期 |
| [战斗核心设计](combat-core-design.md) | 八类普通怪、精英首领、十种攻击、二十四种增益及构筑关系 |
| [南侧战斗区域](battle-area-plan.md) | 已确认并搭建的开阔战斗面、外围台地、基础波次入口与参数；沿用最新 Lumina 视觉 |
| [波次循环灰盒](wave-graybox.md) | 操作、敌人与基础攻击参数；挑战 UI 当前默认隐藏 |
| [怪物刷新与波次基础](wave-spawning.md) | 18／28／40 分批进场、同场上限 24、顶部透明波次文字、刷新保护与扩展接口 |
| [A01 自动扇击](fan-auto-attack.md) | 本局技能框架、八级扇击／连斩／持续旋转、真实升级卡与实机动画 |
| [A02 雷光贯穿视觉预览](light-pierce.md) | Meowa 透明枪锋、光丝拖尾、八帧命中动画与 Q/E 实机预览；当前为视觉版 |
| [本局战斗增益](combat-buffs.md) | 伤害、冷却、范围的升级卡、叠加、封顶与参数调节 |
| [无尽波次](endless-waves.md) | 无限续波、清波休整、数量和节奏增长、上限与参数 |
| [地图效果接入](map-effects.md) | 通用效果场景、正式地图连接与调节入口 |
| [参数总览与 Style](parameters-and-styles.md) | Godot 七类参数入口、控制对象、R 切光影天气与 T 重试 |
| [游戏启动性能](startup-performance.md) | 正式地图草花区域检索瓶颈、优化前后计时与后续方案 |
| [正式地图说明](../demoWithMeowa/1/scenes/world/README.md) | 出生区、台地、建筑与通行结构 |
| [地表画笔](../demoWithMeowa/1/addons/terrain_painter/README.md) | 地表绘制、画笔配置、保存与撤销 |
| [编辑器地图切换](../demoWithMeowa/1/addons/map_switcher/README.md) | 打开、运行与设置默认开发地图 |
| [训练小屋](training-hut.md) | 交互、训练属性、建筑参数与存档 |
| [第一只史莱姆](first-slime.md) | 外观、巡逻与追踪；正式战斗使用波次组件的生命与接触伤害 |
| [种植操作](farming.md) | 保留的锄地、播种、浇水原型；本次 Demo 暂不纳入 |
| [种植交互提示](farming-ui.md) | 保留的像素提示原型；本次 Demo 暂不纳入 |
| [3D 豌豆射手视觉原型](peashooter.md) | 保留的体积与材质预览；本次 Demo 暂不纳入 |

## 人物与界面

| 文档 | 内容 |
| --- | --- |
| [人物跳跃与下落](player-jump.md) | 动画、跳跃物理与台阶通行 |
| [人物瞬移闪身](player-dodge.md) | 位移、碰撞、残影、音效与环境反馈 |
| [人物受光](character-lighting.md) | 侧光、背光与亮边参数 |
| [玩家与怪物遮挡轮廓](player-occlusion.md) | 建筑遮挡、动画帧采样与轮廓参数 |
| [人物、装备与技能界面](equipment-skills-ui.md) | 管理页配置、手帐动效与历史技能测试说明 |
| [背包与物品快捷栏](inventory-ui.md) | 库存、分类、物品栏与使用入口 |
| [人物属性条](player-bars-reference/README.md) | 真实生命与魔力绑定、接口及布局参数 |
| [技能栏](skill-hud.md) | 已确认的小尺寸空槽与视觉参数 |
| [UI 操作音效](ui-audio.md) | 共用声音、操作对应与音量配置 |
| [人物动作音效](movement-audio.md) | 地表脚步过渡、起跳与落地 |

## 视觉与声音

| 文档 | 内容 |
| --- | --- |
| [项目视觉设计](visual-design.md) | Lumina 原则在当前家园、连续地图与战斗内容中的应用、实际基准和后续视觉优先级 |
| [草地与光照明暗层次](value-lighting-sample.md) | 保留草底中间色、拓宽草花色阶、暖主光与冷色半球补光，以及原版切换与同机位实机 |
| [HD-2D 视觉复刻教程](hd2d-visual-tutorial.md) | 分阶段实现方法、提示词、参数与拍摄检查 |
| [地图局部光斑](map-accent-light.md) | 全局氛围与稀疏暖色点缀 |
| [远景空气光](atmospheric-light.md) | 远景光束、辉光与体积散射 |
| [草地光影](grass-lighting.md) | 草丛受光、程序化法线与旋转时的阴影 |
| [像素美术统一样板](pixel-art-sample.md) | 草地、卵石路、墙面、屋瓦的像素尺度、实机对比与检查器材质切换 |
| [材质色阶统一](pixel-color-ramps.md) | 四类材质各五档底色、同机位实机对比与色板调节 |
| [草地与花草样板](foliage-visual-sample.md) | 草底对比、花草五色色阶、同色花簇与密度；实机对比及恢复入口 |
| [环境动态的时段与区域差异](environment-dynamics.md) | 自然风、光点的时段渐变和家园／战区差异，保留统一雨量；参数与动态实机 |
| [边缘、植被与受光](surface-integration.md) | 路边草缘、台地衔接、簇内层次及地表／建筑／人物独立法线；实机图与恢复参数 |
| [萤火虫](fireflies.md) | 光点颜色、亮度、大小与明暗变化 |
| [水面光照](water-lighting.md) | 高光、扰动、反射与参数 |
| [泡沫与水花](water-foam.md) | 颜色、尺度、岸边与瀑布落点 |
| [瀑布表现](waterfall-visuals.md) | 水帘与首版实现说明 |
| [日照演示](daylight-preview.md) | 保留作对照的可选功能，默认关闭 |
| [BGM 与风声](../demoWithMeowa/1/assets/meowa/audio/README.md) | 音源、循环淡化与试听 |
| [全局战斗音效](fan-auto-attack.md#全局战斗音效管理) | 共享预算、优先级、密集合并、人物听觉中心、分组混音及新攻击接入 |
| [细雨与天气](../demoWithMeowa/1/assets/meowa/weather/README.md) | 雨声、镜头水滴及天气配置 |

## 历史参考与反馈

- [仙门灯会历史方案](archive/lantern-festival-design.md)：保留早期设计供参考，不作为当前世界题材或实现要求。
- [Meowa 动画反馈](meowa-animation-feedback.md)：原始观察、调用证据与已接入结果。[证据包](meowa-animation-feedback.zip) 和 `meowa-animation-feedback/` 原样保留。
- 已确认的界面参考与提取组件保留在 `equipment-skills-reference/`、`inventory-reference/`、`player-bars-reference/` 和 `skill-hud-preview/reference.png`。

## 目录维护

功能说明和仍被引用的实机图片、动画、试听保留在这里。一次性截图、检查脚本、分析结果和临时下载放到 `D:\.codexfile\work\<任务名>`；历史设计放到 `archive/`，并标明适用范围。

2026-10-13 清理了四份已被后续文档取代的早期光影／水面集成报告，以及 67 个未再使用的阶段预览。清理前的副本和文件清单位于 `D:\.codexfile\work\docs-cleanup\`。
