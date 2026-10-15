class_name CoreSoundBank
extends Resource

## 已制作的核心操作音效；每个事件对应一组可替换的原生音源。
@export var cues: Dictionary = {}

# 顺序与原四十条试听一致，变体沿用各事件的音源顺序。
const AUDITION := [
	[&"charge_start", "蓄力与弹射", "蓄力起手", "开始蓄力时触发。"],
	[&"charge_loop", "蓄力与弹射", "蓄力持续", "持续蓄力时循环播放。"],
	[&"charge_ready", "蓄力与弹射", "满蓄提示", "达到满蓄时只提示一次。"],
	[&"launch", "蓄力与弹射", "发射", "松开蓄力、发射人物本体时触发。"],
	[&"flight_end", "蓄力与弹射", "飞行结束收势", "本次弹射正常结束时触发。"],
	[&"bounce_stone", "反弹与拨怪", "石材反弹", "撞到石墙、石柱等石材障碍时触发。"],
	[&"bounce_wood", "反弹与拨怪", "木材反弹", "撞到木箱、木桶等木质障碍时触发。"],
	[&"bounce_metal", "反弹与拨怪", "金属反弹", "撞到铁栅栏等金属障碍时触发。"],
	[&"push_stun", "反弹与拨怪", "拨怪眩晕", "实际拨动并眩晕怪物时触发。"],
	[&"player_hurt", "人物状态", "人物受伤", "人物实际扣血时触发。"],
	[&"low_health", "人物状态", "濒危提醒", "首次进入濒危区时提示，不连续重复。"],
	[&"defeat", "人物状态", "战败", "人物生命耗尽、进入失败结算时触发。"],
	[&"enemy_hit_soft", "怪物反馈", "软质怪物受击", "普通生物受到常规攻击时触发。"],
	[&"enemy_hit_hard", "怪物反馈", "硬壳怪物受击", "裂瓷壶兽受到常规攻击时触发。"],
	[&"slime_death", "怪物反馈", "史莱姆死亡", "史莱姆或小史莱姆死亡时触发。"],
	[&"creature_death", "怪物反馈", "普通生物死亡", "冲锋虫、花兽、苔蛙等死亡时触发。"],
	[&"split_spawn", "怪物反馈", "分裂幼体出现", "壶兽分裂的幼体实际生成时触发。"],
	[&"experience", "经验与成长", "收取经验", "收取经验时提示，短间隔拾取会合并。"],
	[&"level_up", "经验与成长", "升级", "实际获得升级时触发。"],
	[&"card_reveal", "经验与成长", "卡牌揭晓", "每轮候选牌揭晓时播放一次。"],
	[&"reroll", "经验与成长", "成功重抽", "实际替换一组候选牌时触发。"],
	[&"growth_apply", "经验与成长", "成长选择生效", "确认学习或升级成功时触发。"],
	[&"wave_start", "波次", "开战", "实际开始一波战斗时触发。"],
	[&"horde_arrival", "波次", "怪潮入场", "成批怪潮实际入场时提示。"],
	[&"wave_clear", "波次", "清波完成", "完成整波清怪时触发。"],
	[&"storm_strike", "奔雷涌潮", "首片引雷", "按雷片发声，不按每只怪物叠加。"],
	[&"storm_chain", "奔雷涌潮", "后续链式传播", "传播逐层减弱；这里按第一层试听。"],
]

func clips_for(cue: StringName) -> Array:
	return cues.get(cue, [])

func audition_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for row in AUDITION:
		var clips := clips_for(row[0])
		for index in clips.size():
			entries.append({"id": "S%02d" % (entries.size() + 1), "cue": row[0], "group": row[1],
				"label": row[2] + (" · 变体 %d" % (index + 1) if clips.size() > 1 else ""),
				"purpose": row[3], "clip": clips[index]})
	return entries
