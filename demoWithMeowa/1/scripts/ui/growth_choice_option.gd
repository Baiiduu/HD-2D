@tool
class_name GrowthChoiceOption
extends Resource

enum Category { GENERAL, LEARN_SKILL, UPGRADE_SKILL, GLOBAL_BUFF }
enum Rarity { AUTO = -1, COMMON, EPIC, LEGENDARY, MYTHIC }

## 本轮候选项的稳定标识；UI 只回传它，不执行成长效果。
@export var id: StringName
@export var title := ""
@export_multiline var description := ""
@export var icon: Texture2D
## 独立卡面插画；空槽暂用原图标，不把图标拉伸成整幅插画。
@export var illustration: Texture2D
## 卡框、解锁与品阶权重共用品级；AUTO 兼容已有 epic 标记。
@export var rarity: Rarity = Rarity.AUTO
@export var enabled := true
@export var category: Category = Category.GENERAL
## 旧资源的史诗标记；显式 rarity 优先，获得后的续级进入普通池。
@export var epic := false
var growth_level := 0
var hide_category := false
## 动态候选的抽牌分组；界面仍使用共有增益布局，不改变旧分类编号。
var ricochet_growth := false

func get_card_rarity() -> int:
	return (Rarity.EPIC if epic else Rarity.COMMON) if rarity == Rarity.AUTO else rarity
