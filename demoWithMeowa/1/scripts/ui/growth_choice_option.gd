@tool
class_name GrowthChoiceOption
extends Resource

enum Category { GENERAL, LEARN_SKILL, UPGRADE_SKILL, GLOBAL_BUFF }

## 本轮候选项的稳定标识；UI 只回传它，不执行成长效果。
@export var id: StringName
@export var title := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var enabled := true
@export var category: Category = Category.GENERAL
## 动态候选的抽牌分组；界面仍使用共有增益布局，不改变旧分类编号。
var ricochet_growth := false
