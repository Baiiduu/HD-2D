# 角色动画尝试路线报告

整理日期：2026-10-16。范围：当前双剑动画对话中的试作、已留存的圣女骑士动作／骨架资料，以及独立的程序武器试验。

本报告整理既有产物，没有重新调用生成服务。**“已产出”不代表已经验收；最新双剑圣女素材仍是美术试验，尚未完成正式角色整套替换。**

图片阅读入口：[网页图文预览](<character_animation_attempts_report.html>)（包含图集、GIF和原生文件链接；可用浏览器打开）。

## 阅读方式

- 每个方案依次列出实现方法、实际参考或关联资料、图集预览、动画检视、原生序列图和结果判断。参考图与方案产物明确分开。
- 像素成品的预览只作整数倍率最近邻放大；原生PNG不缩放。较大的动作草图直接展示缩小预览，原尺寸图集在同节提供链接，避免一次载入多张数千万像素大图。
- “原生”指该阶段实际保存的帧画布，不代表所有阶段都是64或96像素美术。1254、1792等大图明确按动作草图记录。
- 从PNG临时补做的回放只用于检视。未留存原时长时采用100毫秒／帧；原生图集不包含预览标号、棋盘格或额外缩放。
- 原调用参考参数缺失时，会写明“关联资料”或“未核实”；没有序列产物的分支不会配上一套无关结果。

## 分支索引

| 编号 | 尝试路线 | 当前状态 |
| --- | --- | --- |
| 02 | [纯文字分镜直接生成中间帧](#case-02) | 已尝试，效果不理想；未找到对应序列 |
| 03 | [圣女骑士：Meowa 战斗站姿与关键帧](#case-03) | 关键姿势试作 |
| 04 | [切换角色时的转换后动作（Meowa N1，8帧）](#case-04) | 已指定为切换角色时的转换后动作，已归档 finalart，未接入游戏 |
| 05 | [二维骨架六帧：先确定全身运动](#case-05) | 骨架底稿已产出 |
| 06 | [二维骨架六帧：横扫＋反斜上切](#case-06) | 骨架方案已产出 |
| 07 | [空间骨架六帧：透视横扫与斜劈](#case-07) | 空间结构稿已产出 |
| 08 | [Meowa 六帧全身动作候选](#case-08) | 完整六帧候选已恢复可看 |
| 09 | [现有单剑参考→双剑五个关键姿势](#case-09) | 粗动作改编试验 |
| 10 | [双剑完整13帧：第一轮重建](#case-10) | 被要求返修人体 |
| 11 | [双剑完整13帧：逐帧人体与相邻帧审查](#case-11) | 人体审查版本，非最终定稿 |
| 12 | [双剑完整13帧：等长武器与透视修订](#case-12) | 武器审查版本 |
| 13 | [圣女角色：蹬跳、腾挪、反弹13姿势](#case-13) | 大图动作设计稿 |
| 14 | [双剑旋转攻击16帧与29帧合并](#case-14) | 大图动作预演 |
| 15 | [动作重排：22帧持续攻击与7帧反弹墙](#case-15) | 已完成序列拆分 |
| 16 | [旋转抽帧：17帧持续攻击](#case-16) | 已确定的后续动作参考顺序 |
| 17 | [Meowa 原生64×64：前五帧](#case-17) | 第一组原生像素产物 |
| 18 | [Meowa 原生64×64：第6–10帧初版](#case-18) | 被指出人物尺度不一致 |
| 19 | [统一骨架与重绘64×64：大小修正试验](#case-19) | 因改变原动作被否定 |
| 20 | [96×96扩边：前五帧保留主体并增加剑气](#case-20) | 后续尺度参照组 |
| 21 | [96像素批量“只修大小”：中间试验A](#case-21) | 中间试验，未采用 |
| 22 | [96像素十帧联合“只修大小”：中间试验B](#case-22) | 中间试验，未采用 |
| 23 | [保持原动作的尺度引导→Meowa清稿：第6–10帧](#case-23) | 后续继续制作时使用的版本 |
| 24 | [继续制作第11–17帧，形成17帧像素序列](#case-24) | 已交付待验收 |
| 25 | [新形象迁移：前十帧批量编辑试版](#case-25) | 批量迁移试版，部分帧未采用 |
| 26 | [新形象迁移：逐帧严格编辑＋保留原轨迹](#case-26) | 最新已交付，待验收 |
| 27 | [程序控制刚体武器：24帧空间斜砍](#case-27) | 程序武器验证完成，未做完整角色 |
| 28 | [程序结构稿→AI外观→误差检查与修帧](#case-28) | 仅讨论，未完成端到端验证 |

## 路线关系

圣女站姿 → N1转换后动作／六帧骨架试验；已有单剑参考 → 五关键姿势 → 完整13帧 → 人体审查 → 武器审查；圣女蹬跳13姿势 → 追加16帧旋转 → 合并29帧 → 拆为22攻击＋7反弹 → 抽为17攻击 → Meowa原生64 → 扩边96与尺度修正 → 17帧像素产物 → 前10帧新形象迁移。程序刚体武器属于独立验证支线。

<a id="case-02"></a>

## 02｜纯文字分镜直接生成中间帧

**状态：** 已尝试，效果不理想；未找到对应序列

**实现方案：** 把脑中模糊的漫画或电影动作写成逐帧文字，让模型同时推断身体运动、角色外观、像素表达与首尾衔接。

**实现结果与限制：** 用户明确反馈效果不理想。当前可读素材中没有能可靠归属这一轮的完整帧序列，因此不展示其他路线的结果冒充本轮产物。

**参考图：** 没有可核实的该分支输入图存档；本节不补造参考图。

**图集预览与原生序列图：** 无可核实产物。

---

<a id="case-03"></a>

## 03｜圣女骑士：Meowa 战斗站姿与关键帧

**状态：** 关键姿势试作

**实现方案：** 用角色外观参考和明确战斗站姿，先让Meowa建立一手举剑、一手低位持剑的造型；另行制作普攻起始帧F1与反斜上切F4，测试角色形象能否迁移到指定全身姿势。

**实现结果与限制：** 已有64×64战斗姿势，以及96×96的F1、F4独立试作。F1与F4不是完整六帧动画，不将它们串成连续动画宣称完成。

### 实现过程中使用的参考与关联资料

**参考：当时留存的角色／姿势参考**。

![当时留存的角色／姿势参考（参考输入）](<../../references/character-animation/character_animation_report/references/33eeb60939/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/33eeb60939/original.png>)

**参考：横扫蓄力F1结构稿（关联存档）**。

![横扫蓄力F1结构稿（关联存档）（参考输入）](<../../references/character-animation/character_animation_report/references/270fa65a77/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/270fa65a77/original.png>)

**参考：反斜上切F4结构稿（关联存档）**。

![反斜上切F4结构稿（关联存档）（参考输入）](<../../references/character-animation/character_animation_report/references/405d768953/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/405d768953/original.png>)

### 该方案的序列效果

**图集预览｜圣女骑士：Meowa 战斗站姿与关键帧｜1 帧／姿势｜原始帧最大画布 64×64**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![圣女骑士：Meowa 战斗站姿与关键帧图集预览](<../../references/character-animation/character_animation_report/case-03/main/atlas-preview-01.png>)

**原生序列图：64×64 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![圣女骑士：Meowa 战斗站姿与关键帧原生序列图](<../../references/character-animation/character_animation_report/case-03/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-03/main/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/meowa-saint-pose-20261014/outputs/修改参考图1的人物姿势_匹配参考图2_双腿左右拉开站稳_上方手臂举剑过头顶_剑身_646b9557/remove_bg.png

### 同分支补充产物：F1 横扫蓄力起始帧

**图集预览｜F1 横扫蓄力起始帧｜1 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![F1 横扫蓄力起始帧图集预览](<../../references/character-animation/character_animation_report/case-03/additional-01/atlas-preview-01.png>)

**原生序列图：96×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![F1 横扫蓄力起始帧原生序列图](<../../references/character-animation/character_animation_report/case-03/additional-01/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-03/additional-01/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-attack-start-frame-meowa-20261014/delivery/F1_start.png

### 同分支补充产物：F4 左剑反斜上切

**图集预览｜F4 左剑反斜上切｜1 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![F4 左剑反斜上切图集预览](<../../references/character-animation/character_animation_report/case-03/additional-02/atlas-preview-01.png>)

**原生序列图：96×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![F4 左剑反斜上切原生序列图](<../../references/character-animation/character_animation_report/case-03/additional-02/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-03/additional-02/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-normal-attack-6f-f04-20261014/delivery/normal_attack_6f_F4.png

---

<a id="case-04"></a>

## 04｜切换角色时的转换后动作（Meowa N1，8帧）

**最终归档：** [下载转换后动作（动画、图集与8张原生帧）](<../../../finalart/character_switch_post_transform_meowa_n1/character_switch_post_transform_meowa_n1.zip>)。96×96／帧；保留整理版与Meowa原始时序版。

**状态：** 已指定为切换角色时的转换后动作，已归档 finalart，未接入游戏

**实现方案：** 先制作N01准备姿势与N04主斩姿势，再让Meowa生成压低重心、上剑斜劈、随挥和回收。产物解码为原生帧，调整各帧播放时长。

**实现结果与限制：** 可解码的96×96、8帧完整试作已经存在，保留原始Meowa版本和整理后的播放版本。它证明可以快速得到动画候选，但不能据此认定人体、剑长和动作已经验收。

### 实现过程中使用的参考与关联资料

**参考：N01 准备姿势**。

![N01 准备姿势（参考输入）](<../../references/character-animation/character_animation_report/references/97890aa9b7/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/97890aa9b7/original.png>)

**参考：N04 主斩姿势**。

![N04 主斩姿势（参考输入）](<../../references/character-animation/character_animation_report/references/b669a134c2/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/b669a134c2/original.png>)

### 该方案的序列效果

**图集预览｜切换角色时的转换后动作（Meowa N1，8帧）｜8 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![切换角色时的转换后动作（Meowa N1，8帧）图集预览](<../../../finalart/character_switch_post_transform_meowa_n1/atlas-preview.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![切换角色时的转换后动作（Meowa N1，8帧）动画检视](<../../../finalart/character_switch_post_transform_meowa_n1/preview.gif>)

[打开原始动画文件](<../../../finalart/character_switch_post_transform_meowa_n1/animation.webp>)

**原生序列图：768×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![切换角色时的转换后动作（Meowa N1，8帧）原生序列图](<../../../finalart/character_switch_post_transform_meowa_n1/spritesheet.png>)

[打开／保存原生序列图](<../../../finalart/character_switch_post_transform_meowa_n1/spritesheet.png>)

**当前归档文件：** finalart/character_switch_post_transform_meowa_n1/animation.webp（源动作 Meowa N1）

### 同帧的原始Meowa时间版

这一项与N1整理版是同一组原生帧，区别在播放时长；下面按服务返回的原时长播放，画面仅作3倍最近邻显示。

![N1原始Meowa时间版](<../../../finalart/character_switch_post_transform_meowa_n1/preview-meowa-original.gif>)

[打开原始Meowa无损动画](<../../../finalart/character_switch_post_transform_meowa_n1/animation-meowa-original.webp>)

---

<a id="case-05"></a>

## 05｜二维骨架六帧：先确定全身运动

**状态：** 骨架底稿已产出

**实现方案：** 用二维关节点和骨段先规定肩线、髋线、支撑腿、双臂与两把剑的位置，绘制六个动作底稿，再以底稿指导角色绘制。

**实现结果与限制：** 已有六帧骨架与播放预演；本节产物是动作结构稿，不是角色像素成品。

**播放说明：** 原记录主要用于粗动作审查；报告以100毫秒／帧播放结构稿。

### 实现过程中使用的参考与关联资料

**参考：战斗站姿骨架**。

![战斗站姿骨架（参考输入）](<../../references/character-animation/character_animation_report/references/96af2ea348/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/96af2ea348/original.png>)

### 该方案的序列效果

**图集预览｜二维骨架六帧：先确定全身运动｜6 帧／姿势｜原始帧最大画布 360×330**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![二维骨架六帧：先确定全身运动图集预览](<../../references/character-animation/character_animation_report/case-05/main/atlas-preview-01.png>)

**动画检视**（展示用尺寸）

![二维骨架六帧：先确定全身运动动画检视](<../../references/character-animation/character_animation_report/case-05/main/animation-review.gif>)

**原生序列图：1800×660 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-05/main/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-stickman-6f-20261014/F01_skeleton.png；D:/.codexfile/work/saint-stickman-6f-20261014/F02_skeleton.png；其余 4 张按文件名顺序读取。

---

<a id="case-06"></a>

## 06｜二维骨架六帧：横扫＋反斜上切

**状态：** 骨架方案已产出

**实现方案：** 在六帧骨架上重新安排双剑分工与上下半身配合，明确横扫和反斜上切的接力、脚步与肩胯扭转。F1、F4像素试作是与该类关键姿势控制相关的后续尝试。

**实现结果与限制：** 已有完整六帧骨架图；骨架本身可固定位置，但后续图像生成不会自动严格执行这些坐标。

### 实现过程中使用的参考与关联资料

**参考：横扫／斜切的起始战斗骨架**。

![横扫／斜切的起始战斗骨架（参考输入）](<../../references/character-animation/character_animation_report/references/f319a4ffb4/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/f319a4ffb4/original.png>)

### 该方案的序列效果

**图集预览｜二维骨架六帧：横扫＋反斜上切｜6 帧／姿势｜原始帧最大画布 360×330**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![二维骨架六帧：横扫＋反斜上切图集预览](<../../references/character-animation/character_animation_report/case-06/main/atlas-preview-01.png>)

**动画检视**（展示用尺寸）

![二维骨架六帧：横扫＋反斜上切动画检视](<../../references/character-animation/character_animation_report/case-06/main/animation-review.gif>)

**原生序列图：1800×660 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-06/main/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-stickman-sweep-chop-6f-20261014/F01_skeleton.png；D:/.codexfile/work/saint-stickman-sweep-chop-6f-20261014/F02_skeleton.png；其余 4 张按文件名顺序读取。

---

<a id="case-07"></a>

## 07｜空间骨架六帧：透视横扫与斜劈

**状态：** 空间结构稿已产出

**实现方案：** 建立空间关节与双剑端点，用统一相机投影六个姿势，把朝向镜头时的缩短与转体关系先画成底稿。

**实现结果与限制：** 已有六帧空间底稿、姿态数据和程序。验证了结构参考的生成，尚未证明后续Meowa能严格复现全部空间坐标。

### 实现过程中使用的参考与关联资料

**参考：统一空间站姿底稿**。

![统一空间站姿底稿（参考输入）](<../../references/character-animation/character_animation_report/references/24a6d0dac8/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/24a6d0dac8/original.png>)

### 该方案的序列效果

**图集预览｜空间骨架六帧：透视横扫与斜劈｜6 帧／姿势｜原始帧最大画布 400×400**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![空间骨架六帧：透视横扫与斜劈图集预览](<../../references/character-animation/character_animation_report/case-07/main/atlas-preview-01.png>)

**动画检视**（展示用尺寸）

![空间骨架六帧：透视横扫与斜劈动画检视](<../../references/character-animation/character_animation_report/case-07/main/animation-review.gif>)

**原生序列图：2000×800 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-07/main/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-perspective-sweep-chop-6f-20261014/F01_3d.png；D:/.codexfile/work/saint-perspective-sweep-chop-6f-20261014/F02_3d.png；其余 4 张按文件名顺序读取。

---

<a id="case-08"></a>

## 08｜Meowa 六帧全身动作候选

**状态：** 完整六帧候选已恢复可看

**实现方案：** 以双剑骑士战斗站姿与全身挥击描述制作六帧候选，检查动作的身体参与程度。该文件虽然扩展名为.bin，实际能够按WebP解码，报告按原字节保留为.webp供查看。

**实现结果与限制：** 本次整理确认这是96×96、6帧WebP，而不是无效文件。没有完整留存该次调用的参考参数，因此不能声称六张骨架都实际作为输入。

### 实现过程中使用的参考与关联资料

**参考：同阶段留存的骑士准备姿势（关联资料，非已核实的该次输入）**。

![同阶段留存的骑士准备姿势（关联资料，非已核实的该次输入）（参考输入）](<../../references/character-animation/character_animation_report/references/97890aa9b7/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/97890aa9b7/original.png>)

### 该方案的序列效果

**图集预览｜Meowa 六帧全身动作候选｜6 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![Meowa 六帧全身动作候选图集预览](<../../references/character-animation/character_animation_report/case-08/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![Meowa 六帧全身动作候选动画检视](<../../references/character-animation/character_animation_report/case-08/main/animation-review.gif>)

[打开原始动画文件](<../../references/character-animation/character_animation_report/case-08/main/animation-original.webp>)

**原生序列图：576×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![Meowa 六帧全身动作候选原生序列图](<../../references/character-animation/character_animation_report/case-08/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-08/main/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-n1-battlestance-motion-6f-20261014/The_dual-sword_knight_performs_one_powerful_full-body_combo_facing_screen-right_a_horizontal_sweep_with_her_an_bc51adea/result_output_url.bin

---

<a id="case-09"></a>

## 09｜现有单剑参考→双剑五个关键姿势

**状态：** 粗动作改编试验

**实现方案：** 从参考第三行选准备、蓄势、主斩、随挥和收势五个姿势，保留原全身运动，给另一把剑安排护持任务；先比较双剑配合再扩展帧数。

**实现结果与限制：** 已有五姿势对照和预演。用户随后明确要求遵照原参考完整13帧，不能把五关键姿势替代成最终帧数。

### 实现过程中使用的参考与关联资料

**参考：原始单剑动作参考**。

![原始单剑动作参考（参考输入）](<../../references/character-animation/character_animation_report/references/5b6e97d12e/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/5b6e97d12e/original.png>)

**参考：实际抽出的五个关键姿势**。

![实际抽出的五个关键姿势（参考输入）](<../../references/character-animation/character_animation_report/references/2d62b41b06/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/2d62b41b06/original.png>)

### 原参考的拆分产物

原参考曾先按第一行和第三行拆分，保留原像素与背景；第三行后来作为双剑改编的动作来源。

**第一行动作条带**

![第一行动作条带](<../../references/character-animation/character_animation_report/references/source-action-strips/attack-1-sequence.png>)

[打开原尺寸条带](<../../references/character-animation/character_animation_report/references/source-action-strips/attack-1-sequence.png>)

**第三行完整13姿势条带**

![第三行完整13姿势条带](<../../references/character-animation/character_animation_report/references/source-action-strips/attack-3-sequence.png>)

[打开原尺寸条带](<../../references/character-animation/character_animation_report/references/source-action-strips/attack-3-sequence.png>)

### 该方案的序列效果

**图集预览｜现有单剑参考→双剑五个关键姿势｜5 帧／姿势｜原始帧最大画布 600×460**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![现有单剑参考→双剑五个关键姿势图集预览](<../../references/character-animation/character_animation_report/case-09/main/atlas-preview-01.png>)

**动画检视**（展示用尺寸）

![现有单剑参考→双剑五个关键姿势动画检视](<../../references/character-animation/character_animation_report/case-09/main/animation-review.gif>)

**原生序列图：3000×460 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-09/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-study/dual-pose-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-study/dual-pose-02.png；其余 3 张按文件名顺序读取。

---

<a id="case-10"></a>

## 10｜双剑完整13帧：第一轮重建

**状态：** 被要求返修人体

**实现方案：** 完全依照第三行的13个参考动作逐张改编，维持一手主斩、一手护持，保留过渡与收势，不主动减少帧数。

**实现结果与限制：** 帧数得到保留，但用户指出多帧主体人体错误，说明完整帧数不等于完整动作质量。

### 实现过程中使用的参考与关联资料

**参考：原始13帧动作参考**。

![原始13帧动作参考（参考输入）](<../../references/character-animation/character_animation_report/references/cdc99c461c/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/cdc99c461c/original.png>)

### 该方案的序列效果

**图集预览｜双剑完整13帧：第一轮重建｜13 帧／姿势｜原始帧最大画布 512×400**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![双剑完整13帧：第一轮重建图集预览](<../../references/character-animation/character_animation_report/case-10/main/atlas-preview-01.png>)

![双剑完整13帧：第一轮重建图集预览](<../../references/character-animation/character_animation_report/case-10/main/atlas-preview-02.png>)

**动画检视**（展示用尺寸）

![双剑完整13帧：第一轮重建动画检视](<../../references/character-animation/character_animation_report/case-10/main/animation-review.gif>)

**原生序列图：2560×1200 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-10/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-13-frame-study/dual-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-13-frame-study/dual-02.png；其余 11 张按文件名顺序读取。

---

<a id="case-11"></a>

## 11｜双剑完整13帧：逐帧人体与相邻帧审查

**状态：** 人体审查版本，非最终定稿

**实现方案：** 执行“生成当前帧→检查人体和握剑→与上一帧比较→返修再继续”；去除刀光干扰，审查躯干、肩胯、双腿及手臂。记录中第4、12、13帧曾退回修改。

**实现结果与限制：** 已有无剑光的主体审查稿、相邻帧对照和交互审查页面。之后仍暴露出护持剑短剑化、剑长与透视不合理的问题。

### 实现过程中使用的参考与关联资料

**参考：原始13帧动作参考**。

![原始13帧动作参考（参考输入）](<../../references/character-animation/character_animation_report/references/cdc99c461c/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/cdc99c461c/original.png>)

**参考：上一轮13帧对照**。

![上一轮13帧对照（参考输入）](<../../references/character-animation/character_animation_report/references/0c93d408b5/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/0c93d408b5/original.png>)

### 该方案的序列效果

**图集预览｜双剑完整13帧：逐帧人体与相邻帧审查｜13 帧／姿势｜原始帧最大画布 1254×1254**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![双剑完整13帧：逐帧人体与相邻帧审查图集预览](<../../references/character-animation/character_animation_report/case-11/main/atlas-preview-01.png>)

![双剑完整13帧：逐帧人体与相邻帧审查图集预览](<../../references/character-animation/character_animation_report/case-11/main/atlas-preview-02.png>)

**动画检视**（展示用尺寸）

![双剑完整13帧：逐帧人体与相邻帧审查动画检视](<../../references/character-animation/character_animation_report/case-11/main/animation-review.gif>)

**原生序列图：6270×3762 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-11/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-sequential-review/frame-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-sequential-review/frame-02.png；其余 11 张按文件名顺序读取。

---

<a id="case-12"></a>

## 12｜双剑完整13帧：等长武器与透视修订

**状态：** 武器审查版本

**实现方案：** 在人体审查基础上，把两把剑按同一物理规格处理；分别检查握点、剑格、剑尖、方向、遮挡及相邻帧变化，避免把护持剑画成另一种短剑。

**实现结果与限制：** 已有13帧武器修订稿与剑轴检查页面。二维轴线只是审查估计，不能证明三维透视严格正确，仍属于审查稿。

### 实现过程中使用的参考与关联资料

**参考：原动作13帧**。

![原动作13帧（参考输入）](<../../references/character-animation/character_animation_report/references/cdc99c461c/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/cdc99c461c/original.png>)

**参考：上一轮主体审查图集**。

![上一轮主体审查图集（参考输入）](<../../references/character-animation/character_animation_report/references/517ed9377d/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/517ed9377d/original.png>)

### 该方案的序列效果

**图集预览｜双剑完整13帧：等长武器与透视修订｜13 帧／姿势｜原始帧最大画布 1254×1254**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![双剑完整13帧：等长武器与透视修订图集预览](<../../references/character-animation/character_animation_report/case-12/main/atlas-preview-01.png>)

![双剑完整13帧：等长武器与透视修订图集预览](<../../references/character-animation/character_animation_report/case-12/main/atlas-preview-02.png>)

**动画检视**（展示用尺寸）

![双剑完整13帧：等长武器与透视修订动画检视](<../../references/character-animation/character_animation_report/case-12/main/animation-review.gif>)

**原生序列图：6270×3762 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-12/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-equal-length-review/frame-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/dual-sword-equal-length-review/frame-02.png；其余 11 张按文件名顺序读取。

---

<a id="case-13"></a>

## 13｜圣女角色：蹬跳、腾挪、反弹13姿势

**状态：** 大图动作设计稿

**实现方案：** 把弹射从低姿滑行改为连续蹬地、上挑、收腿转体、下落劈斩、落地压缩和再次起跳；另外安排接墙压缩、蹬墙改向与反斩。

**实现结果与限制：** 已有13张透明大图和动作设定图。原记录明确存在局部体型与剑长漂移，不能当作已定稿的游戏像素动画。

**播放说明：** 原交付是动作序列设定图；报告以100毫秒／帧提供额外审查回放。

### 实现过程中使用的参考与关联资料

**参考：起始姿势参考的8倍检视存档**。

![起始姿势参考的8倍检视存档（参考输入）](<../../references/character-animation/character_animation_report/references/c878774f6a/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/c878774f6a/original.png>)

**参考：结束姿势参考的8倍检视存档**。

![结束姿势参考的8倍检视存档（参考输入）](<../../references/character-animation/character_animation_report/references/1a243f7d15/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/1a243f7d15/original.png>)

### 同阶段的局部返修与补充参考

**参考：第2姿势的双剑修订引导存档**。

![第2姿势的双剑修订引导存档（参考输入）](<../../references/character-animation/character_animation_report/references/161161d2a5/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/161161d2a5/original.png>)

### 该方案的序列效果

**图集预览｜圣女角色：蹬跳、腾挪、反弹13姿势｜13 帧／姿势｜原始帧最大画布 1254×1254**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![圣女角色：蹬跳、腾挪、反弹13姿势图集预览](<../../references/character-animation/character_animation_report/case-13/main/atlas-preview-01.png>)

![圣女角色：蹬跳、腾挪、反弹13姿势图集预览](<../../references/character-animation/character_animation_report/case-13/main/atlas-preview-02.png>)

**动画检视**（展示用尺寸）

![圣女角色：蹬跳、腾挪、反弹13姿势动画检视](<../../references/character-animation/character_animation_report/case-13/main/animation-review.gif>)

**原生序列图：6270×3762 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-13/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-hop-dual-sword-sequence/pose-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-hop-dual-sword-sequence/pose-02.png；其余 11 张按文件名顺序读取。

---

<a id="case-14"></a>

## 14｜双剑旋转攻击16帧与29帧合并

**状态：** 大图动作预演

**实现方案：** 在原13姿势之后增加16帧转圈斩，参考“死神式持续旋转”的动作意图，设计正面、侧面、背面与回正；双剑随转体扫动，头发和披风跟随。

**实现结果与限制：** 旋转段已有16帧；与前段合并为29帧。此阶段仍是动作预演，局部剑长和人物尺度没有完全稳定。

### 实现过程中使用的参考与关联资料

**参考：旋转段角色及站姿参考**。

![旋转段角色及站姿参考（参考输入）](<../../references/character-animation/character_animation_report/references/ee4468b778/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/ee4468b778/original.png>)

**参考：前段蹬跳动作设定**。

![前段蹬跳动作设定（参考输入）](<../../references/character-animation/character_animation_report/references/76b9930b52/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/76b9930b52/original.png>)

### 同阶段的局部返修与补充参考

**参考：旋转中段的姿态与等长双剑引导存档（每次调用的输入参数未全部留存）**。

![旋转中段的姿态与等长双剑引导存档（每次调用的输入参数未全部留存）（参考输入）](<../../references/character-animation/character_animation_report/references/e001f6081b/reference-preview-01.png>)

![旋转中段的姿态与等长双剑引导存档（每次调用的输入参数未全部留存）（参考输入）](<../../references/character-animation/character_animation_report/references/e001f6081b/reference-preview-02.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/e001f6081b/reference-native-atlas.png>)

### 该方案的序列效果

**图集预览｜双剑旋转攻击16帧与29帧合并｜16 帧／姿势｜原始帧最大画布 1792×1536**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![双剑旋转攻击16帧与29帧合并图集预览](<../../references/character-animation/character_animation_report/case-14/main/atlas-preview-01.png>)

![双剑旋转攻击16帧与29帧合并图集预览](<../../references/character-animation/character_animation_report/case-14/main/atlas-preview-02.png>)

**动画检视**（展示用尺寸）

![双剑旋转攻击16帧与29帧合并动画检视](<../../references/character-animation/character_animation_report/case-14/main/animation-review.gif>)

**原生序列图：8960×6144 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-14/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-dual-sword-spin/pose-14.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-dual-sword-spin/pose-15.png；其余 14 张按文件名顺序读取。

### 同分支补充产物：合并后的完整29帧

**图集预览｜合并后的完整29帧｜29 帧／姿势｜原始帧最大画布 1792×1536**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![合并后的完整29帧图集预览](<../../references/character-animation/character_animation_report/case-14/additional-01/atlas-preview-01.png>)

![合并后的完整29帧图集预览](<../../references/character-animation/character_animation_report/case-14/additional-01/atlas-preview-02.png>)

![合并后的完整29帧图集预览](<../../references/character-animation/character_animation_report/case-14/additional-01/atlas-preview-03.png>)

![合并后的完整29帧图集预览](<../../references/character-animation/character_animation_report/case-14/additional-01/atlas-preview-04.png>)

**动画检视**（展示用尺寸）

![合并后的完整29帧动画检视](<../../references/character-animation/character_animation_report/case-14/additional-01/animation-review.gif>)

**原生序列图：8960×9216 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-14/additional-01/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-dual-sword-spin/combo-frames/pose-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-dual-sword-spin/combo-frames/pose-02.png；其余 27 张按文件名顺序读取。

---

<a id="case-15"></a>

## 15｜动作重排：22帧持续攻击与7帧反弹墙

**状态：** 已完成序列拆分

**实现方案：** 按用户指定顺序，把原1–6帧与原14–29帧接为22帧持续攻击；原7–13帧独立成为反弹墙动作，不再混在持续攻击中。

**实现结果与限制：** 这是一条编排分支，复用已有绘制结果，没有重新解决人体和武器漂移。

### 实现过程中使用的参考与关联资料

**参考：编排前完整29帧**。

![编排前完整29帧（参考输入）](<../../references/character-animation/character_animation_report/references/c6bcc14140/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/c6bcc14140/original.png>)

### 该方案的序列效果

**图集预览｜动作重排：22帧持续攻击与7帧反弹墙｜22 帧／姿势｜原始帧最大画布 1792×1536**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![动作重排：22帧持续攻击与7帧反弹墙图集预览](<../../references/character-animation/character_animation_report/case-15/main/atlas-preview-01.png>)

![动作重排：22帧持续攻击与7帧反弹墙图集预览](<../../references/character-animation/character_animation_report/case-15/main/atlas-preview-02.png>)

![动作重排：22帧持续攻击与7帧反弹墙图集预览](<../../references/character-animation/character_animation_report/case-15/main/atlas-preview-03.png>)

**动画检视**（展示用尺寸）

![动作重排：22帧持续攻击与7帧反弹墙动画检视](<../../references/character-animation/character_animation_report/case-15/main/animation-review.gif>)

**原生序列图：8960×7680 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-15/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-reordered-actions/continuous-attack-22/frames/continuous-attack-22-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-reordered-actions/continuous-attack-22/frames/continuous-attack-22-02.png；其余 20 张按文件名顺序读取。

### 同分支补充产物：独立反弹墙7帧

**图集预览｜独立反弹墙7帧｜7 帧／姿势｜原始帧最大画布 1792×1536**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![独立反弹墙7帧图集预览](<../../references/character-animation/character_animation_report/case-15/additional-01/atlas-preview-01.png>)

**动画检视**（展示用尺寸）

![独立反弹墙7帧动画检视](<../../references/character-animation/character_animation_report/case-15/additional-01/animation-review.gif>)

**原生序列图：8960×3072 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-15/additional-01/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-reordered-actions/wall-rebound-07/frames/wall-rebound-07-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-reordered-actions/wall-rebound-07/frames/wall-rebound-07-02.png；其余 5 张按文件名顺序读取。

---

<a id="case-16"></a>

## 16｜旋转抽帧：17帧持续攻击

**状态：** 已确定的后续动作参考顺序

**实现方案：** 前6帧不动，将旋转段16帧删去5帧、保留11帧，得到17帧持续攻击；保留被选中帧原有时长。

**实现结果与限制：** 这是后续Meowa原生像素重建的动作顺序来源。22帧中的保留索引为1、2、3、4、5、6、7、8、10、12、13、15、16、18、19、21、22。

### 实现过程中使用的参考与关联资料

**参考：抽帧前持续攻击22帧**。

![抽帧前持续攻击22帧（参考输入）](<../../references/character-animation/character_animation_report/references/4869fcfbd4/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/4869fcfbd4/original.png>)

### 该方案的序列效果

**图集预览｜旋转抽帧：17帧持续攻击｜17 帧／姿势｜原始帧最大画布 1792×1536**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![旋转抽帧：17帧持续攻击图集预览](<../../references/character-animation/character_animation_report/case-16/main/atlas-preview-01.png>)

![旋转抽帧：17帧持续攻击图集预览](<../../references/character-animation/character_animation_report/case-16/main/atlas-preview-02.png>)

**动画检视**（展示用尺寸）

![旋转抽帧：17帧持续攻击动画检视](<../../references/character-animation/character_animation_report/case-16/main/animation-review.gif>)

**原生序列图：8960×6144 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-16/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-reordered-actions/continuous-attack-22/frames/continuous-attack-22-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/saint-reordered-actions/continuous-attack-22/frames/continuous-attack-22-02.png；其余 15 张按文件名顺序读取。

---

<a id="case-17"></a>

## 17｜Meowa 原生64×64：前五帧

**状态：** 第一组原生像素产物

**实现方案：** 把17帧中的前五个大图动作作为姿势参考，另提供64×64外观母版，让Meowa逐帧重建透明原生像素；检查人体、手握剑与前后衔接。

**实现结果与限制：** 已有5张原生64×64。人物与双剑可以容纳，但部分剑尖距离边缘只剩1–2像素，后续动作空间偏紧。

### 实现过程中使用的参考与关联资料

**参考：上传的64×64外观母版**。

![上传的64×64外观母版（参考输入）](<../../references/character-animation/character_animation_report/references/a158441236/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/a158441236/original.png>)

**参考：实际大图动作参考01–05**。

![实际大图动作参考01–05（参考输入）](<../../references/character-animation/character_animation_report/references/4a6a7aa2b7/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/4a6a7aa2b7/reference-native-atlas.png>)

**参考：实际64像素姿势引导**。

![实际64像素姿势引导（参考输入）](<../../references/character-animation/character_animation_report/references/fcd5f72a7d/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/fcd5f72a7d/reference-native-atlas.png>)

### 该方案的序列效果

**图集预览｜Meowa 原生64×64：前五帧｜5 帧／姿势｜原始帧最大画布 64×64**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![Meowa 原生64×64：前五帧图集预览](<../../references/character-animation/character_animation_report/case-17/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![Meowa 原生64×64：前五帧动画检视](<../../references/character-animation/character_animation_report/case-17/main/animation-review.gif>)

**原生序列图：320×64 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![Meowa 原生64×64：前五帧原生序列图](<../../references/character-animation/character_animation_report/case-17/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-17/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel64-first5/frames/attack-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel64-first5/frames/attack-02.png；其余 3 张按文件名顺序读取。

---

<a id="case-18"></a>

## 18｜Meowa 原生64×64：第6–10帧初版

**状态：** 被指出人物尺度不一致

**实现方案：** 沿用母版与前五帧造型，逐帧转换第6–10帧；按武器位移，仅在第6、7、9帧添加刀光。

**实现结果与限制：** 用户指出人物大小不一致。这组保留为尺度问题的直接对照，不能再称为已经统一尺度的版本。

### 实现过程中使用的参考与关联资料

**参考：64×64角色外观母版**。

![64×64角色外观母版（参考输入）](<../../references/character-animation/character_animation_report/references/0d905fbfc3/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/0d905fbfc3/original.png>)

**参考：该组实际姿势引导**。

![该组实际姿势引导（参考输入）](<../../references/character-animation/character_animation_report/references/2e960d93e1/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/2e960d93e1/reference-native-atlas.png>)

### 同阶段的局部返修与补充参考

**参考：第7–10帧的局部返修参考存档**。

![第7–10帧的局部返修参考存档（参考输入）](<../../references/character-animation/character_animation_report/references/088ca5e988/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/088ca5e988/reference-native-atlas.png>)

### 该方案的序列效果

**图集预览｜Meowa 原生64×64：第6–10帧初版｜5 帧／姿势｜原始帧最大画布 64×64**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![Meowa 原生64×64：第6–10帧初版图集预览](<../../references/character-animation/character_animation_report/case-18/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![Meowa 原生64×64：第6–10帧初版动画检视](<../../references/character-animation/character_animation_report/case-18/main/animation-review.gif>)

**原生序列图：320×64 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![Meowa 原生64×64：第6–10帧初版原生序列图](<../../references/character-animation/character_animation_report/case-18/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-18/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel64-06-10/frames/attack-06.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel64-06-10/frames/attack-07.png；其余 3 张按文件名顺序读取。

---

<a id="case-19"></a>

## 19｜统一骨架与重绘64×64：大小修正试验

**状态：** 因改变原动作被否定

**实现方案：** 准备统一头身、躯干和四肢的骨架引导，再让Meowa整体重绘，希望统一身体大小与像素单位。

**实现结果与限制：** 大小较整齐，但改动了原动作与站姿。用户明确要求“修正大小不要改变动作”，因此这一版没有作为后续动作母版。

### 实现过程中使用的参考与关联资料

**参考：同角色外观参考**。

![同角色外观参考（参考输入）](<../../references/character-animation/character_animation_report/references/f05af865d1/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/f05af865d1/original.png>)

**参考：实际统一骨架引导**。

![实际统一骨架引导（参考输入）](<../../references/character-animation/character_animation_report/references/0344d063af/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/0344d063af/reference-native-atlas.png>)

### 同阶段的局部返修与补充参考

**参考：统一人体试验的固定角色母版**。

![统一人体试验的固定角色母版（参考输入）](<../../references/character-animation/character_animation_report/references/033e0f081e/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/033e0f081e/original.png>)

**参考：该分支发型修订的实际动画输入**。

![该分支发型修订的实际动画输入（参考输入）](<../../references/character-animation/character_animation_report/references/3a91f3f93e/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/3a91f3f93e/original.webp>)

### 该方案的序列效果

**图集预览｜统一骨架与重绘64×64：大小修正试验｜5 帧／姿势｜原始帧最大画布 64×64**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![统一骨架与重绘64×64：大小修正试验图集预览](<../../references/character-animation/character_animation_report/case-19/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![统一骨架与重绘64×64：大小修正试验动画检视](<../../references/character-animation/character_animation_report/case-19/main/animation-review.gif>)

[打开原始动画文件](<../../references/character-animation/character_animation_report/case-19/main/animation-original.webp>)

**原生序列图：320×64 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![统一骨架与重绘64×64：大小修正试验原生序列图](<../../references/character-animation/character_animation_report/case-19/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-19/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel64-06-10-uniform/attack-06-10-uniform-native.webp

---

<a id="case-20"></a>

## 20｜96×96扩边：前五帧保留主体并增加剑气

**状态：** 后续尺度参照组

**实现方案：** 把原64×64人物按整数像素平移放入96×96透明画布，不放大主体；用Meowa生成挥剑方向相符的刀光，并保留独立效果层。

**实现结果与限制：** 为长剑、弧形刀光和腾空动作增加余量。此组成为后续人物尺度的参照，画布变化不代表人物本身变大。

### 实现过程中使用的参考与关联资料

**参考：原64像素前五帧**。

![原64像素前五帧（参考输入）](<../../references/character-animation/character_animation_report/references/ed413db6fa/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/ed413db6fa/original.png>)

**参考：96像素扩边透明输入存档**。

![96像素扩边透明输入存档（参考输入）](<../../references/character-animation/character_animation_report/references/fd0c94d106/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/fd0c94d106/reference-native-atlas.png>)

### 同阶段的局部返修与补充参考

**参考：实际提交生成时的纯绿背景输入**。

![实际提交生成时的纯绿背景输入（参考输入）](<../../references/character-animation/character_animation_report/references/c1563fd975/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/c1563fd975/reference-native-atlas.png>)

### 该方案的序列效果

**图集预览｜96×96扩边：前五帧保留主体并增加剑气｜5 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![96×96扩边：前五帧保留主体并增加剑气图集预览](<../../references/character-animation/character_animation_report/case-20/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![96×96扩边：前五帧保留主体并增加剑气动画检视](<../../references/character-animation/character_animation_report/case-20/main/animation-review.gif>)

**原生序列图：480×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![96×96扩边：前五帧保留主体并增加剑气原生序列图](<../../references/character-animation/character_animation_report/case-20/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-20/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel96-first5-swordqi/frames/attack-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel96-first5-swordqi/frames/attack-02.png；其余 3 张按文件名顺序读取。

### 同方案保留的独立剑气层

这是当时交付的5格96×96独立效果图层，与人物主体分开保存。

![独立剑气原生图层](<../../references/character-animation/character_animation_report/case-20/effects/swordqi-original-sheet-96.png>)

[打开独立剑气原生图层](<../../references/character-animation/character_animation_report/case-20/effects/swordqi-original-sheet-96.png>)

---

<a id="case-21"></a>

## 21｜96像素批量“只修大小”：中间试验A

**状态：** 中间试验，未采用

**实现方案：** 把原6–10帧扩边后，与已确认的1–5帧尺度参考一起交给Meowa，要求仅统一人体大小与比例，不更换动作。

**实现结果与限制：** 提示词中的“只改大小”没有提供硬约束；这一轮曾出现复制早先姿势、动作被替换的情况。保留结果用于与最终引导清稿路线比较。

### 实现过程中使用的参考与关联资料

**参考：实际尺度参考**。

![实际尺度参考（参考输入）](<../../references/character-animation/character_animation_report/references/01ebfcf731/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/01ebfcf731/original.png>)

**参考：该次原6–10动作输入**。

![该次原6–10动作输入（参考输入）](<../../references/character-animation/character_animation_report/references/86bdd58443/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/86bdd58443/original.webp>)

### 该方案的序列效果

**图集预览｜96像素批量“只修大小”：中间试验A｜5 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![96像素批量“只修大小”：中间试验A图集预览](<../../references/character-animation/character_animation_report/case-21/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![96像素批量“只修大小”：中间试验A动画检视](<../../references/character-animation/character_animation_report/case-21/main/animation-review.gif>)

[打开原始动画文件](<../../references/character-animation/character_animation_report/case-21/main/animation-original.webp>)

**原生序列图：480×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![96像素批量“只修大小”：中间试验A原生序列图](<../../references/character-animation/character_animation_report/case-21/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-21/main/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-06-10-pose-locked-scale96-01a13daf/pose-preserving-size-correction/这是大小修正_不是重新设计动作_参考图是已确认的第1至5帧_按原生像素同倍率横排_d26a4dfd/frames_edit.webp

### 同分支补充产物：只修第7帧大小的单帧尝试（不构成五帧序列）

**图集预览｜只修第7帧大小的单帧尝试（不构成五帧序列）｜1 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![只修第7帧大小的单帧尝试（不构成五帧序列）图集预览](<../../references/character-animation/character_animation_report/case-21/additional-01/atlas-preview-01.png>)

**原生序列图：96×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![只修第7帧大小的单帧尝试（不构成五帧序列）原生序列图](<../../references/character-animation/character_animation_report/case-21/additional-01/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-21/additional-01/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-06-10-pose-locked-scale96-01a13daf/frame07-size-only-original-action/仅把现有这位双剑女骑士的人物体格放大约20_匹配同一角色前五帧的人物大小_保持_45ca969c/remove_bg.png

---

<a id="case-22"></a>

## 22｜96像素十帧联合“只修大小”：中间试验B

**状态：** 中间试验，未采用

**实现方案：** 把1–10帧放在同一动画输入里，让模型以1–5帧为标准修正后五帧，尝试减少分组导致的尺度差。

**实现结果与限制：** 联合输入仍出现重复或替换姿势的问题，未能保证逐帧动作不变，因此不作为最终版本。

### 实现过程中使用的参考与关联资料

**参考：实际十帧输入**。

![实际十帧输入（参考输入）](<../../references/character-animation/character_animation_report/references/5c69bb96fe/reference-preview-01.png>)

![实际十帧输入（参考输入）](<../../references/character-animation/character_animation_report/references/5c69bb96fe/reference-preview-02.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/5c69bb96fe/original.webp>)

### 该方案的序列效果

**图集预览｜96像素十帧联合“只修大小”：中间试验B｜10 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![96像素十帧联合“只修大小”：中间试验B图集预览](<../../references/character-animation/character_animation_report/case-22/main/atlas-preview-01.png>)

![96像素十帧联合“只修大小”：中间试验B图集预览](<../../references/character-animation/character_animation_report/case-22/main/atlas-preview-02.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![96像素十帧联合“只修大小”：中间试验B动画检视](<../../references/character-animation/character_animation_report/case-22/main/animation-review.gif>)

[打开原始动画文件](<../../references/character-animation/character_animation_report/case-22/main/animation-original.webp>)

**原生序列图：960×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![96像素十帧联合“只修大小”：中间试验B原生序列图](<../../references/character-animation/character_animation_report/case-22/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-22/main/native-sequence.png>)

**结果对应的源文件：** D:/.codexfile/work/saint-06-10-pose-locked-scale96-01a13daf/ten-original-actions-size-only/仅修正这段10帧动画中第6至10帧的人物尺度_第1至5帧是已经确认的原动作和人物大小_bedec5d5/frames_edit.webp

---

<a id="case-23"></a>

## 23｜保持原动作的尺度引导→Meowa清稿：第6–10帧

**状态：** 后续继续制作时使用的版本

**实现方案：** 先在一次性输入引导中纠正身体尺度，尽量保留原关节角度、朝向、步伐和剑向，再让Meowa只整理像素边缘、握柄与清晰度。最终产物不进行缩放，只做抠背景和整数像素定位。 输入引导允许为尺寸参考进行处理，不能把这些引导文件冒充原生像素成品。

**实现结果与限制：** 比直接要求模型统一大小更可控；已有96×96的6–10帧、与1–5帧同倍率对照和原动作比较。仍需以逐帧审查判断姿势是否保持。

### 实现过程中使用的参考与关联资料

**参考：1–5帧尺度参照**。

![1–5帧尺度参照（参考输入）](<../../references/character-animation/character_animation_report/references/01ebfcf731/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/01ebfcf731/original.png>)

**参考：最终使用的锁定姿势与尺度引导**。

![最终使用的锁定姿势与尺度引导（参考输入）](<../../references/character-animation/character_animation_report/references/2250b9e088/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/2250b9e088/reference-native-atlas.png>)

### 同阶段的局部返修与补充参考

**参考：第8帧尺寸引导中的武器整理参考**。

![第8帧尺寸引导中的武器整理参考（参考输入）](<../../references/character-animation/character_animation_report/references/4ad5f887d6/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/4ad5f887d6/original.png>)

### 该方案的序列效果

**图集预览｜保持原动作的尺度引导→Meowa清稿：第6–10帧｜5 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![保持原动作的尺度引导→Meowa清稿：第6–10帧图集预览](<../../references/character-animation/character_animation_report/case-23/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![保持原动作的尺度引导→Meowa清稿：第6–10帧动画检视](<../../references/character-animation/character_animation_report/case-23/main/animation-review.gif>)

**原生序列图：480×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![保持原动作的尺度引导→Meowa清稿：第6–10帧原生序列图](<../../references/character-animation/character_animation_report/case-23/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-23/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-06-10-pose-preserved96/frames/attack-06.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-06-10-pose-preserved96/frames/attack-07.png；其余 3 张按文件名顺序读取。

---

<a id="case-24"></a>

## 24｜继续制作第11–17帧，形成17帧像素序列

**状态：** 已交付待验收

**实现方案：** 按既定17帧顺序，取背身旋转、转回正面与收势的原动作作为共同尺度引导；用Meowa批量清稿，单独返修第14帧缺剑和第15帧姿势与低位剑方向。

**实现结果与限制：** 已有7张新帧与完整17帧预览。第11–17对应原大图旋转帧20、22、23、25、26、28、29。最新圣华形象迁移尚未覆盖这7帧。

### 实现过程中使用的参考与关联资料

**参考：实际七帧动作引导**。

![实际七帧动作引导（参考输入）](<../../references/character-animation/character_animation_report/references/5bfcdbab7d/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/5bfcdbab7d/original.webp>)

**参考：使用的第10帧尺度／画风参考**。

![使用的第10帧尺度／画风参考（参考输入）](<../../references/character-animation/character_animation_report/references/8101094715/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/8101094715/original.png>)

**参考：第14帧返修动作输入**。

![第14帧返修动作输入（参考输入）](<../../references/character-animation/character_animation_report/references/26efb4cd64/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/26efb4cd64/original.png>)

**参考：第15帧返修动作输入**。

![第15帧返修动作输入（参考输入）](<../../references/character-animation/character_animation_report/references/5d3e2968f5/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/5d3e2968f5/original.png>)

### 该方案的序列效果

**图集预览｜继续制作第11–17帧，形成17帧像素序列｜7 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![继续制作第11–17帧，形成17帧像素序列图集预览](<../../references/character-animation/character_animation_report/case-24/main/atlas-preview-01.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![继续制作第11–17帧，形成17帧像素序列动画检视](<../../references/character-animation/character_animation_report/case-24/main/animation-review.gif>)

**原生序列图：672×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![继续制作第11–17帧，形成17帧像素序列原生序列图](<../../references/character-animation/character_animation_report/case-24/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-24/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-11-17-pose96/frames/attack-11.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-11-17-pose96/frames/attack-12.png；其余 5 张按文件名顺序读取。

### 同分支补充产物：迁移前形象的完整17帧

**图集预览｜迁移前形象的完整17帧｜17 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![迁移前形象的完整17帧图集预览](<../../references/character-animation/character_animation_report/case-24/additional-01/atlas-preview-01.png>)

![迁移前形象的完整17帧图集预览](<../../references/character-animation/character_animation_report/case-24/additional-01/atlas-preview-02.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![迁移前形象的完整17帧动画检视](<../../references/character-animation/character_animation_report/case-24/additional-01/animation-review.gif>)

**原生序列图：960×192 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![迁移前形象的完整17帧原生序列图](<../../references/character-animation/character_animation_report/case-24/additional-01/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-24/additional-01/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel96-first5-swordqi/frames/attack-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-pixel96-first5-swordqi/frames/attack-02.png；其余 15 张按文件名顺序读取。

---

<a id="case-25"></a>

## 25｜新形象迁移：前十帧批量编辑试版

**状态：** 批量迁移试版，部分帧未采用

**实现方案：** 把现有1–5与6–10两组原生96像素动画，配合同一张从“圣华之剑”海报裁出的角色参考，分两组用Meowa迁移发型、冠环、铠甲、披风和剑格。

**实现结果与限制：** 首版外观较统一，但第1、6帧等剑向与刀光发生偏移，部分朝向也被参考姿势影响；未直接采用整组。

### 实现过程中使用的参考与关联资料

**参考：用户上传的完整形象参考**。

![用户上传的完整形象参考（参考输入）](<../../references/character-animation/character_animation_report/references/73c3c11280/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/73c3c11280/original.png>)

**参考：实际使用的聚焦外观参考**。

![实际使用的聚焦外观参考（参考输入）](<../../references/character-animation/character_animation_report/references/455d64a19e/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/455d64a19e/original.png>)

**参考：输入动画1–5**。

![输入动画1–5（参考输入）](<../../references/character-animation/character_animation_report/references/9bf40f1e29/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/9bf40f1e29/original.webp>)

**参考：输入动画6–10**。

![输入动画6–10（参考输入）](<../../references/character-animation/character_animation_report/references/8f7fb9912f/reference-preview-01.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/8f7fb9912f/original.webp>)

### 该方案的序列效果

**图集预览｜新形象迁移：前十帧批量编辑试版｜10 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![新形象迁移：前十帧批量编辑试版图集预览](<../../references/character-animation/character_animation_report/case-25/main/atlas-preview-01.png>)

![新形象迁移：前十帧批量编辑试版图集预览](<../../references/character-animation/character_animation_report/case-25/main/atlas-preview-02.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![新形象迁移：前十帧批量编辑试版动画检视](<../../references/character-animation/character_animation_report/case-25/main/animation-review.gif>)

**原生序列图：960×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![新形象迁移：前十帧批量编辑试版原生序列图](<../../references/character-animation/character_animation_report/case-25/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-25/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-reference-reskin-first10-96/inspection/candidate-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-reference-reskin-first10-96/inspection/candidate-02.png；其余 8 张按文件名顺序读取。

---

<a id="case-26"></a>

## 26｜新形象迁移：逐帧严格编辑＋保留原轨迹

**状态：** 最新已交付，待验收

**实现方案：** 把参考裁成头饰、胸甲、腿甲与剑格细节，减少完整参考姿势干扰；逐帧严格编辑并与原图比较，单独返修第9帧侧面朝向。最终选用较贴近动作的候选：第4、5帧沿用批量版，其余主要来自逐帧版；部分外侧刀光、武器轨迹及少量边缘像素保留原帧，避免生成漂移。

**实现结果与限制：** 前十帧已有96×96透明PNG、无损动画和同倍率对照。不是全部像素都由同一次生成产生，也没有做到程序意义上的逐点几何锁定；当前是待用户验收的最新形象版本。

### 实现过程中使用的参考与关联资料

**参考：完整形象参考**。

![完整形象参考（参考输入）](<../../references/character-animation/character_animation_report/references/73c3c11280/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/73c3c11280/original.png>)

**参考：逐帧编辑实际使用的外观细节参考**。

![逐帧编辑实际使用的外观细节参考（参考输入）](<../../references/character-animation/character_animation_report/references/77e6d6c301/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/77e6d6c301/original.png>)

**参考：原生动作输入1–10**。

![原生动作输入1–10（参考输入）](<../../references/character-animation/character_animation_report/references/786ce556bd/reference-preview-01.png>)

![原生动作输入1–10（参考输入）](<../../references/character-animation/character_animation_report/references/786ce556bd/reference-preview-02.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/786ce556bd/reference-native-atlas.png>)

**参考：第9帧朝向返修前的迁移图**。

![第9帧朝向返修前的迁移图（参考输入）](<../../references/character-animation/character_animation_report/references/73e1fe010d/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/73e1fe010d/original.png>)

### 该方案的序列效果

**图集预览｜新形象迁移：逐帧严格编辑＋保留原轨迹｜10 帧／姿势｜原始帧最大画布 96×96**

预览按原帧顺序排列；以整数倍率最近邻放大，背景棋盘格仅用于检视。

![新形象迁移：逐帧严格编辑＋保留原轨迹图集预览](<../../references/character-animation/character_animation_report/case-26/main/atlas-preview-01.png>)

![新形象迁移：逐帧严格编辑＋保留原轨迹图集预览](<../../references/character-animation/character_animation_report/case-26/main/atlas-preview-02.png>)

**动画检视**（像素分支为慢放，非原生帧文件）

![新形象迁移：逐帧严格编辑＋保留原轨迹动画检视](<../../references/character-animation/character_animation_report/case-26/main/animation-review.gif>)

**原生序列图：960×96 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

![新形象迁移：逐帧严格编辑＋保留原轨迹原生序列图](<../../references/character-animation/character_animation_report/case-26/main/native-sequence.png>)

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-26/main/native-sequence.png>)

**结果对应的源文件：** C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-reference-reskin-first10-96/frames/attack-01.png；C:/Users/PC/.codex/visualizations/2026/10/15/01a13daf-c9be-7fd2-9ba6-93226b01beaf/meowa-reference-reskin-first10-96/frames/attack-02.png；其余 8 张按文件名顺序读取。

---

<a id="case-27"></a>

## 27｜程序控制刚体武器：24帧空间斜砍

**状态：** 程序武器验证完成，未做完整角色

**实现方案：** 使用Python、NumPy和Pillow定义同一把刚性剑、固定透视相机、连续空间旋转、深度遮挡和历史刀刃拖影，再软件光栅化为漫画风帧图。不是Meowa或imagegen生成。

**实现结果与限制：** 已有24帧640×640透明PNG、GIF和约束技术说明。它只验证单把武器的几何运动，并非完整角色或96像素双剑动画，也不等于AI会严格遵守同样规则。

### 实现过程中使用的参考与关联资料

**参考：该讨论的像素挥剑／拖影参考**。

![该讨论的像素挥剑／拖影参考（参考输入）](<../../references/character-animation/character_animation_report/references/eebbb17262/display.png>)

[打开参考原文件／原尺寸参考图集](<../../references/character-animation/character_animation_report/references/eebbb17262/original.png>)

### 该方案的序列效果

**图集预览｜程序控制刚体武器：24帧空间斜砍｜24 帧／姿势｜原始帧最大画布 640×640**

预览按原帧顺序排列；大图／结构稿仅在此预览缩小，下面的原生序列图保留原始像素。

![程序控制刚体武器：24帧空间斜砍图集预览](<../../references/character-animation/character_animation_report/case-27/main/atlas-preview-01.png>)

![程序控制刚体武器：24帧空间斜砍图集预览](<../../references/character-animation/character_animation_report/case-27/main/atlas-preview-02.png>)

![程序控制刚体武器：24帧空间斜砍图集预览](<../../references/character-animation/character_animation_report/case-27/main/atlas-preview-03.png>)

**动画检视**（展示用尺寸）

![程序控制刚体武器：24帧空间斜砍动画检视](<../../references/character-animation/character_animation_report/case-27/main/animation-review.gif>)

画面外的帧号只用于检视，确保GIF保留每一张源帧；原生序列图没有叠加帧号。

**原生序列图：3200×3200 PNG**。按行从左到右读取；每格保持原始画布，不裁人物、不缩放、不插值。

[打开／保存原生序列图](<../../references/character-animation/character_animation_report/case-27/main/native-sequence.png>)

**结果对应的源文件：** E:/meowjitoProject/HD-2D/demoWithMeowa/1/art_test/knight_greatsword_slash/frames/slash_01.png；E:/meowjitoProject/HD-2D/demoWithMeowa/1/art_test/knight_greatsword_slash/frames/slash_02.png；其余 22 张按文件名顺序读取。

---

<a id="case-28"></a>

## 28｜程序结构稿→AI外观→误差检查与修帧

**状态：** 仅讨论，未完成端到端验证

**实现方案：** 拟由程序固定握点、剑尖、投影、轮廓和遮挡，AI参考结构稿绘制外观，再叠加检查并返修；精确拖影可继续由程序生成。

**实现结果与限制：** 目前是讨论方案，没有完整角色的端到端合格序列。生成模型可能改动结构稿；把二维图贴到三维模型再投影会重采样，不能与“保留最终原生像素”直接等同。

**参考图：** 没有可核实的该分支输入图存档；本节不补造参考图。

**图集预览与原生序列图：** 无可核实产物。

---

## 仅讨论过、尚未查到本项目执行产物的其他候选路线

| 候选路线 | 原讨论中的用途 | 当前可核实状态 |
| --- | --- | --- |
| 真人／影视／现有游戏动作参考 | 先获取重心、步伐和挥剑路径 | 现有动画参考已实际采用；没有查到真人拍摄或动作捕捉素材。 |
| 先生成动作视频，再抽关键姿势 | 把模糊动作变成可观看候选 | 曾提及Luma等方向，没有找到本项目对应的视频生成序列。 |
| 专用像素首尾补帧 | 从起始与结束图生成过渡 | 曾讨论PixelLab等能力，没有找到本项目实际调用结果。 |
| 现成3D人偶与动作库 | 用固定镜头获取复杂转体底稿 | 已有程序骨架和剑体投影试验；没有找到完整角色绑定、Mixamo动作或角色三维渲染交付。 |
| 委托动画师制作粗动作 | 先确认火柴人／剪影动作，再做像素 | 仅为建议，没有找到委托产物。 |
| 普通视频光流补帧 | 对相近姿势补充过渡 | 曾提及RIFE，不是已执行并验证的项目路线。 |


### 未找到可对应完整序列的角色方向记录

项目约束还记录过B“绯红剑客”方向：栗色短发、红白短外套、明确腰线、深色长裤短靴与双剑。本次未找到能可靠对应这一方向的完整动画序列及原始参考，因此不将白发圣女试作当作该方向的完成结果。

## 游戏接入与验收边界

- PlayerActionVisuals预留普通攻击、蓄力、飞行、飞行攻击和收尾五类动作槽，空槽沿用现有动画。
- 上述双剑圣女素材尚未构成完整、多方向、正式验收后的角色替换。第11–17帧尚未迁移为最新“圣华之剑”形象。
- 程序可以确定自己绘制的武器几何、轨迹、投影和深度；这不意味着图像生成模型会严格执行参考中的每个坐标。
- 继续制作仍需分别检查单帧人体与握剑、同规格双剑的合理投影、相邻动作、身体尺度及刀光方向。报告中的失败与中间版本保留用于这些对照。

## 来源与文件说明

图像均来自已留存的项目资源、用户上传参考、当前对话产物和既有工作目录。报告配套图片存放在docs/references/character-animation/character_animation_report/，Markdown位于 docs/visuals/character-animation/。没有覆盖或移动原始素材。

单把武器试验的详细约束：[knight_greatsword_slash_constraints.md](<../../references/character-animation/knight_greatsword_slash/knight_greatsword_slash_constraints.md>)

## 跨分支代表帧速览

每格仅取该方案中间的一帧，便于快速辨认版本；完整动作效果以上面各节的图集与动画为准。

![跨分支效果速览](<../../references/character-animation/character_animation_report/overview-01.png>)

![跨分支效果速览](<../../references/character-animation/character_animation_report/overview-02.png>)

![跨分支效果速览](<../../references/character-animation/character_animation_report/overview-03.png>)
