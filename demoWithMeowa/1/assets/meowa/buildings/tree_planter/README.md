# 树池建筑样板

整棵树由 Meowa 单物体像素生成并去背景，`tree.png` 为原生 128×128 RGBA，未重采样或再次像素化。原始不透明文件保存在忽略导入的 `source/`。花草复用现有 Meowa 素材，花坛壁与压顶分别使用独立的 `../materials/masonry.png` 和 `../materials/limestone.png`，盆内使用 `../materials/compost.png`，长椅使用 `../ricochet/wood.png`。这些材质均保留 Meowa 原生 64px，不复用路面或地板。

Godot「地图切换」选择「树池建筑预览」即可在当前正式世界的相机、光影和天气下查看；Q/E 旋转，R 切光影和天气。预览不写人物存档、不运行波次挑战。

将 `res://scenes/buildings/tree_planter.tscn` 从文件系统拖入 `world.tscn`，选择 **TreePlanter 根节点**整体移动、绕 Y 旋转或复制。原点是地面底部，+Z 是长椅正面；放在平整地面后可点击 Inspector「贴合地面」。移动根节点不重建地形或全图花草。参数修改只重建当前树池。

Inspector 可调花坛宽／深／高、树图及根部锚点、像素尺寸、树冠风摆、受光起伏、花草比例、长椅／路灯／碰撞开关和材质。默认树图每像素 0.025 米，64px 材质每块 1.6 米，约 40 像素／米。替换树图时按新图片的根部位置修改 `tree_anchor`。

`stone_texture` 控制花坛壁，`cap_texture` 控制整石压顶，`wood_texture` 控制长椅，可独立替换。

树冠、树干共用一张直立贴图，只随相机水平朝向转动；它不具有真实三维侧面。材质接收现有方向光、路灯和阴影，树冠轻微风摆跟随 Weather 的开关与强度。路灯复用公共金色漂浮粒子，地面光束关闭。
