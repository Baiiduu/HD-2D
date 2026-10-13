class_name WaveEnemyDefinition
extends Resource

## 替换怪物场景即可换行为；场景根节点须继承 WaveEnemy。
@export_group("怪物资源")
@export var scene: PackedScene
@export var display_name := "史莱姆"
@export_group("战斗数值与经验")
@export_range(1.0, 10000.0, 1.0) var health := 20.0
@export_range(0.0, 10.0, 0.05) var move_speed := 1.35
## 传给怪物自身的招式，不由波次控制器判断命中。
@export_range(0.0, 1000.0, 1.0) var attack_damage := 8.0
## 真正击败后掉落的本局经验；召唤体等可设为 0。
@export_range(0, 10000, 1) var experience_reward := 3
## 刷新时给怪物保留的半径，米；避免嵌进墙或与其他出场怪物重叠。
@export_range(0.1, 2.0, 0.05, "suffix:m") var spawn_clearance := 0.35
