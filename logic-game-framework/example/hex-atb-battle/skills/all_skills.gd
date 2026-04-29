## HexBattle 技能 / Buff 总清单(单一花名册)
##
## 一份 manifest 同时驱动:
##   - register_all_timelines() - 战斗启动时把所有 TimelineData 注册到 TimelineRegistry
##   - all_abilities()           - SkillPreview / 工具层枚举所有 AbilityConfig
##
## 加新技能 / Buff = 在 _build_manifest() 里加一行 _Entry.new(...);消费侧自动跟随。
## 纯被动技能(无 timeline)传 [];Buff 也走这里(buff 自己的 tick timeline 也要注册)。
class_name HexBattleAllSkills


## 一项条目 = 一个 AbilityConfig + 它需要注册的 timelines
class _Entry extends RefCounted:
	var ability: AbilityConfig
	var timelines: Array[TimelineData]

	func _init(p_ability: AbilityConfig, p_timelines: Array[TimelineData]) -> void:
		ability = p_ability
		timelines = p_timelines


static var ALL: Array[_Entry] = _build_manifest()


static func _build_manifest() -> Array[_Entry]:
	var arr: Array[_Entry] = []
	# Active skills(timeline-driven)
	arr.append(_Entry.new(HexBattleMove.ABILITY,         [HexBattleMove.MOVE_TIMELINE]))
	arr.append(_Entry.new(HexBattleStrike.ABILITY,       [HexBattleStrike.STRIKE_TIMELINE]))
	arr.append(_Entry.new(HexBattleCrushingBlow.ABILITY, [HexBattleCrushingBlow.CRUSHING_BLOW_TIMELINE]))
	arr.append(_Entry.new(HexBattleSwiftStrike.ABILITY,  [HexBattleSwiftStrike.SWIFT_STRIKE_TIMELINE]))
	arr.append(_Entry.new(HexBattlePreciseShot.ABILITY,  [HexBattlePreciseShot.PRECISE_SHOT_TIMELINE, HexBattlePreciseShot.PRECISE_SHOT_HIT_TIMELINE]))
	arr.append(_Entry.new(HexBattleFireball.ABILITY,     [HexBattleFireball.FIREBALL_TIMELINE, HexBattleFireball.FIREBALL_HIT_TIMELINE]))
	arr.append(_Entry.new(HexBattleHolyHeal.ABILITY,     [HexBattleHolyHeal.HOLY_HEAL_TIMELINE]))
	arr.append(_Entry.new(HexBattlePoison.ABILITY,       [HexBattlePoison.POISON_TIMELINE]))
	arr.append(_Entry.new(HexBattleWard.ABILITY,         [HexBattleWard.WARD_TIMELINE]))
	arr.append(_Entry.new(HexBattleSurge.ABILITY,        [HexBattleSurge.SURGE_TIMELINE]))
	arr.append(_Entry.new(HexBattleWallBreaker.ABILITY,  [HexBattleWallBreaker.WALL_BREAKER_TIMELINE]))
	arr.append(_Entry.new(HexBattleKnockbackPunch.ABILITY, [HexBattleKnockbackPunch.KNOCKBACK_PUNCH_TIMELINE]))
	# Pure passives(no timeline)
	arr.append(_Entry.new(HexBattleThorn.ABILITY,           []))
	arr.append(_Entry.new(HexBattleDeathrattleAoe.ABILITY,  []))
	arr.append(_Entry.new(HexBattleVitality.ABILITY,        []))
	arr.append(_Entry.new(HexBattleVigor.ABILITY,           []))
	# Buffs(non-skill ability,但其 tick timeline 也要注册)
	arr.append(_Entry.new(HexBattlePoisonBuff.POISON_BUFF,  [HexBattlePoisonBuff.POISON_TICK_TIMELINE]))
	arr.append(_Entry.new(HexBattleSurgeBuff.SURGE_BUFF,    [HexBattleSurgeBuff.SURGE_TICK_TIMELINE]))
	return arr


## 把所有 TimelineData 注册进 TimelineRegistry。战斗启动时调一次。
static func register_all_timelines() -> void:
	for entry in ALL:
		for tl in entry.timelines:
			TimelineRegistry.register(tl)


## 返回 manifest 里所有 AbilityConfig(含 skill / passive / buff)
static func all_abilities() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = []
	for entry in ALL:
		out.append(entry.ability)
	return out
