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


## 不缓存为 static var:Godot 4.6 Windows headless 会在此类静态数组 + 静态读取函数形态下退出崩溃。
static func _build_manifest() -> Array[_Entry]:
	var arr: Array[_Entry] = []
	# Active skills(timeline-driven)
	arr.append(_Entry.new(HexBattleMove.ABILITY,         [HexBattleMove.MOVE_TIMELINE]))
	arr.append(_Entry.new(HexBattleStrike.ABILITY,       [HexBattleStrike.STRIKE_TIMELINE]))
	arr.append(_Entry.new(HexBattleExecute.ABILITY,      [HexBattleExecute.EXECUTE_TIMELINE]))
	arr.append(_Entry.new(HexBattleCrushingBlow.ABILITY, [HexBattleCrushingBlow.CRUSHING_BLOW_TIMELINE]))
	arr.append(_Entry.new(HexBattleSwiftStrike.ABILITY,  [HexBattleSwiftStrike.SWIFT_STRIKE_TIMELINE]))
	arr.append(_Entry.new(HexBattlePreciseShot.ABILITY,  [HexBattlePreciseShot.PRECISE_SHOT_TIMELINE, HexBattlePreciseShot.PRECISE_SHOT_HIT_TIMELINE]))
	arr.append(_Entry.new(HexBattleFireball.ABILITY,     [HexBattleFireball.FIREBALL_TIMELINE, HexBattleFireball.FIREBALL_HIT_TIMELINE]))
	arr.append(_Entry.new(HexBattleChainLightning.ABILITY, [HexBattleChainLightning.CHAIN_LIGHTNING_CAST_TIMELINE, HexBattleChainLightning.CHAIN_LIGHTNING_HIT_TIMELINE]))
	arr.append(_Entry.new(HexBattleShadowStep.ABILITY,    [HexBattleShadowStep.SHADOW_STEP_TIMELINE]))
	arr.append(_Entry.new(HexBattleStance.ABILITY,        [HexBattleStance.STANCE_TIMELINE]))
	arr.append(_Entry.new(HexBattleDemonForm.ABILITY,     [HexBattleDemonForm.DEMON_FORM_TICK_TIMELINE]))
	arr.append(_Entry.new(HexBattleHolyHeal.ABILITY,     [HexBattleHolyHeal.HOLY_HEAL_TIMELINE]))
	arr.append(_Entry.new(HexBattlePoison.ABILITY,       [HexBattlePoison.POISON_TIMELINE]))
	arr.append(_Entry.new(HexBattleWard.ABILITY,         [HexBattleWard.WARD_TIMELINE]))
	arr.append(_Entry.new(HexBattlePhysicalShield.ABILITY, [HexBattlePhysicalShield.PHYSICAL_SHIELD_TIMELINE]))
	arr.append(_Entry.new(HexBattleMagicalShield.ABILITY,  [HexBattleMagicalShield.MAGICAL_SHIELD_TIMELINE]))
	arr.append(_Entry.new(HexBattleSurge.ABILITY,        [HexBattleSurge.SURGE_TIMELINE]))
	arr.append(_Entry.new(HexBattleWallBreaker.ABILITY,  [HexBattleWallBreaker.WALL_BREAKER_TIMELINE]))
	arr.append(_Entry.new(HexBattleKnockbackPunch.ABILITY, [HexBattleKnockbackPunch.KNOCKBACK_PUNCH_TIMELINE]))
	arr.append(_Entry.new(HexBattleExpose.ABILITY,        [HexBattleExpose.EXPOSE_TIMELINE]))
	arr.append(_Entry.new(HexBattleStun.ABILITY,          [HexBattleStun.STUN_TIMELINE]))
	arr.append(_Entry.new(HexBattleSilence.ABILITY,       [HexBattleSilence.SILENCE_TIMELINE]))
	arr.append(_Entry.new(HexBattleBreak.ABILITY,         [HexBattleBreak.BREAK_TIMELINE]))
	arr.append(_Entry.new(HexBattleSummonTotem.ABILITY,   [HexBattleSummonTotem.SUMMON_TIMELINE]))
	arr.append(_Entry.new(HexBattleSpawnFireTile.ABILITY, [HexBattleSpawnFireTile.SPAWN_FIRE_TILE_TIMELINE]))
	arr.append(_Entry.new(HexBattleCleanse.ABILITY,       [HexBattleCleanse.CLEANSE_TIMELINE]))
	arr.append(_Entry.new(HexBattleSwap.ABILITY,          [HexBattleSwap.SWAP_TIMELINE]))
	arr.append(_Entry.new(HexBattleLifesteal.ABILITY,     [HexBattleLifesteal.LIFESTEAL_TIMELINE]))
	arr.append(_Entry.new(HexBattlePiercingLine.ABILITY,  [HexBattlePiercingLine.PIERCING_LINE_TIMELINE]))
	arr.append(_Entry.new(HexBattleGridCone.ABILITY,      [HexBattleGridCone.GRID_CONE_TIMELINE]))
	arr.append(_Entry.new(HexBattleAngleCone.ABILITY,     [HexBattleAngleCone.ANGLE_CONE_TIMELINE]))
	# Pure passives(no timeline)
	arr.append(_Entry.new(HexBattleGeneralPassive.ABILITY,  [HexBattleGeneralPassive.REGEN_TIMELINE]))
	arr.append(_Entry.new(HexBattleVampiricTraining.ABILITY, []))
	arr.append(_Entry.new(HexBattleVitalitySurge.ABILITY,   []))
	arr.append(_Entry.new(HexBattleThorn.ABILITY,           []))
	arr.append(_Entry.new(HexBattleDeathrattleAoe.ABILITY,  []))
	arr.append(_Entry.new(HexBattleVitality.ABILITY,        []))
	arr.append(_Entry.new(HexBattleVigor.ABILITY,           []))
	arr.append(_Entry.new(HexBattleTotemAttack.ABILITY,     [HexBattleTotemAttack.TICK_TIMELINE]))
	arr.append(_Entry.new(HexBattleTotemLifetime.create_config(HexBattleTotemLifetime.DEFAULT_DURATION_MS), []))
	arr.append(_Entry.new(HexBattleFireTilePulse.ABILITY,   [HexBattleFireTilePulse.PULSE_TIMELINE]))
	arr.append(_Entry.new(HexBattleFireTileLifetime.create_config(HexBattleFireTileLifetime.DEFAULT_DURATION_MS), []))
	# Buffs(non-skill ability,但其 tick timeline 也要注册)
	arr.append(_Entry.new(HexBattlePoisonBuff.POISON_BUFF,  [HexBattlePoisonBuff.POISON_TICK_TIMELINE]))
	arr.append(_Entry.new(HexBattleWardBuff.WARD_BUFF,      []))
	arr.append(_Entry.new(HexBattleShieldBuffs.PHYSICAL_SHIELD_BUFF, []))
	arr.append(_Entry.new(HexBattleShieldBuffs.MAGICAL_SHIELD_BUFF,  []))
	arr.append(_Entry.new(HexBattleSurgeBuff.SURGE_BUFF,    [HexBattleSurgeBuff.SURGE_TICK_TIMELINE]))
	arr.append(_Entry.new(HexBattleExposeBuff.EXPOSE_BUFF,  []))
	arr.append(_Entry.new(HexBattleStunBuff.create_config(HexBattleStunBuff.DEFAULT_DURATION_MS), []))
	arr.append(_Entry.new(HexBattleSilenceBuff.create_config(HexBattleSilenceBuff.DEFAULT_DURATION_MS), []))
	arr.append(_Entry.new(HexBattleBreakBuff.create_config(HexBattleBreakBuff.DEFAULT_DURATION_MS), []))
	return arr


## 把所有 TimelineData 注册进 TimelineRegistry。战斗启动时调一次。
static func register_all_timelines() -> void:
	for entry in _build_manifest():
		for tl in entry.timelines:
			TimelineRegistry.register(tl)


## 返回 manifest 里所有 AbilityConfig(含 skill / passive / buff)
static func all_abilities() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = []
	for entry in _build_manifest():
		out.append(entry.ability)
	return out
