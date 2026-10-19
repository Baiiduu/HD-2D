class_name CoreSoundBank
extends Resource

## 已制作的核心操作音效；每个事件对应一组可替换的原生音源。
@export var cues: Dictionary = {}

# 原四十条试听顺序保持，新事件追加在末尾；变体沿用各事件的音源顺序。
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
	[&"enemy_hit_soft", "怪物反馈", "软质怪物受击", "其它攻击沿用的软质受击；World 可选混合模式中额外减弱作材质层。"],
	[&"enemy_hit_hard", "怪物反馈", "硬壳怪物受击", "其它攻击沿用的硬壳受击；World 可选混合模式中额外减弱作材质层。"],
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
	[&"flight_loop", "蓄力与弹射", "弹射动能气流", "飞行与绕群时循环，随实际速度变化；这里按参考速度试听。"],
	[&"kill_slime_retired", "停用候选", "旧史莱姆击杀候选 · 变体 1（停用）", "停用，仅供对照试听，不参与实战随机池。"],
	[&"kill_slime", "击杀反馈", "史莱姆击杀确认 · 变体 2", "真实致死瞬间的弹性爆破与厚实冲击；普通命中不播放。"],
	[&"kill_group", "击杀反馈", "附近群杀强调", "附近短时间多次击杀合并一次；这里按普通群杀档试听。"],
	[&"kill_air", "击杀反馈", "尸体抛飞气流", "死亡短顿结束、实际抛飞开始时触发，密集尸体合并。"],
	[&"kill_land", "击杀反馈", "尸体落地与碰墙", "已有死亡演出确实落地或碰墙时触发；碰墙略轻。"],
	[&"enemy_hit_common", "通用命中", "人物攻击命中", "同一 Meowa 母版的轻微音高变化；World 普攻与弹射攻击真实命中后随机一条，击杀优先确认声。"],
	[&"leaf_windup", "怪物招式", "冲锋虫蓄势", "实际锁线冲锋预告；密集预告合并声音，视觉提示保留。"],
	[&"lantern_shot", "怪物招式", "花兽吐籽", "花兽实际出手的吐籽声。"],
	[&"frog_pulse", "怪物招式", "苔蛙鼓舞", "苔蛙实际发出移速脉冲；作为轻伴随声，不压过人物命中。"],
	[&"pot_shatter", "怪物招式", "壶兽碎裂", "壶兽真实死亡碎裂；幼体出现另有提示。"],
	[&"charge_wind", "蓄力与弹射", "蓄力聚力风", "风向人物盘旋汇聚，随真实蓄力渐强；松手短淡出，这里按满蓄试听。"],
]

func clips_for(cue: StringName) -> Array:
	return cues.get(cue, [])

static func playback_cue(cue: StringName) -> StringName:
	if cue == &"storm_strike": return &"ricochet_storm_start"
	if cue == &"storm_chain": return &"ricochet_storm_chain"
	if cue == &"kill_slime_retired": return &"core:kill_slime"
	if cue in [&"leaf_windup", &"lantern_shot", &"frog_pulse", &"pot_shatter"]: return cue
	return StringName("core:" + cue)

func audition_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for row in AUDITION:
		var clips := clips_for(row[0])
		for index in clips.size():
			entries.append({"id": "S%02d" % (entries.size() + 1), "cue": row[0], "group": row[1],
				"label": row[2] + (" · 变体 %d" % (index + 1) if clips.size() > 1 else ""),
				"purpose": row[3], "clip": clips[index]})
	return entries
