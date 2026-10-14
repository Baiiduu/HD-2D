class_name WaveEnemyCatalog
extends Resource

## 新怪物登记在此；波次可用 Enemy Id 引用，未参与开场的召唤体也会建立本局快照。
@export var enemies: Array[WaveEnemyDefinition] = []

func validation_error() -> String:
	var ids := {}
	for enemy in enemies:
		if not enemy or enemy.enemy_id == &"": return "怪物目录中存在空资源或空 Enemy Id"
		if ids.has(enemy.enemy_id): return "怪物目录重复 Enemy Id：" + String(enemy.enemy_id)
		ids[enemy.enemy_id] = enemy
	for enemy in enemies:
		var error := enemy.catalog_error(ids)
		if not error.is_empty(): return error
	return ""
