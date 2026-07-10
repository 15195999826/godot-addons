## HexBattle 技能 / Buff 总清单(单一花名册)
##
## 一份 manifest 同时驱动:
##   - register_all_timelines() - 战斗启动时把所有 timeline 注册到 TimelineRegistry
##   - all_abilities()           - SkillPreview / 工具层枚举所有 AbilityConfig
##
## 加新技能 / Buff = 加一行 config;它的 timeline 经 builder.timeline(data) 已挂在
## config 树上, register_all_timelines() 用 collect_timelines() 自动收集注册 ——
## 不再手抄 timeline 列表(旧 _Entry 双列记账已删, 抄漏第二列的失效面不复存在)。
## 共享标准节奏(HexBattleStdTimelines)被多个 config 携带同一引用, 注册幂等。
class_name HexBattleAllSkills


## 不缓存为 static var:Godot 4.6 Windows headless 会在此类静态数组 + 静态读取函数形态下退出崩溃。
static func _build_manifest() -> Array[AbilityConfig]:
	var arr: Array[AbilityConfig] = []
	# Active skills(timeline-driven)
	arr.append(HexBattleMove.ABILITY)
	arr.append(HexBattleStrike.ABILITY)
	arr.append(HexBattleExecute.ABILITY)
	arr.append(HexBattleCrushingBlow.ABILITY)
	arr.append(HexBattleSwiftStrike.ABILITY)
	arr.append(HexBattlePreciseShot.ABILITY)
	arr.append(HexBattleFireball.ABILITY)
	arr.append(HexBattleChainLightning.ABILITY)
	arr.append(HexBattleShadowStep.ABILITY)
	arr.append(HexBattleStance.ABILITY)
	arr.append(HexBattleDemonForm.ABILITY)
	arr.append(HexBattleHolyHeal.ABILITY)
	arr.append(HexBattlePoison.ABILITY)
	arr.append(HexBattleWard.ABILITY)
	arr.append(HexBattlePhysicalShield.ABILITY)
	arr.append(HexBattleMagicalShield.ABILITY)
	arr.append(HexBattleSurge.ABILITY)
	arr.append(HexBattleWallBreaker.ABILITY)
	arr.append(HexBattleKnockbackPunch.ABILITY)
	arr.append(HexBattleExpose.ABILITY)
	arr.append(HexBattleStun.ABILITY)
	arr.append(HexBattleSilence.ABILITY)
	arr.append(HexBattleBreak.ABILITY)
	arr.append(HexBattleSummonTotem.ABILITY)
	arr.append(HexBattleSpawnFireTile.ABILITY)
	arr.append(HexBattleCleanse.ABILITY)
	arr.append(HexBattleSwap.ABILITY)
	arr.append(HexBattleLifesteal.ABILITY)
	arr.append(HexBattlePiercingLine.ABILITY)
	arr.append(HexBattleGridCone.ABILITY)
	arr.append(HexBattleAngleCone.ABILITY)
	# Pure passives(无 timeline 或自带 tick timeline)
	arr.append(HexBattleGeneralPassive.ABILITY)
	arr.append(HexBattleVampiricTraining.ABILITY)
	arr.append(HexBattlePassiveDaedalusCriticalStrike.ABILITY)
	arr.append(HexBattleVitalitySurge.ABILITY)
	arr.append(HexBattleThorn.ABILITY)
	arr.append(HexBattleDeathrattleAoe.ABILITY)
	arr.append(HexBattleVitality.ABILITY)
	arr.append(HexBattleVigor.ABILITY)
	arr.append(HexBattleTotemAttack.ABILITY)
	arr.append(HexBattleTotemLifetime.create_config(HexBattleTotemLifetime.DEFAULT_DURATION_MS))
	arr.append(HexBattleFireTilePulse.ABILITY)
	arr.append(HexBattleFireTileLifetime.create_config(HexBattleFireTileLifetime.DEFAULT_DURATION_MS))
	# Buffs(non-skill ability,其 tick timeline 也随 config 收集注册)
	arr.append(HexBattlePoisonBuff.POISON_BUFF)
	arr.append(HexBattleWardBuff.WARD_BUFF)
	arr.append(HexBattleShieldBuffs.PHYSICAL_SHIELD_BUFF)
	arr.append(HexBattleShieldBuffs.MAGICAL_SHIELD_BUFF)
	arr.append(HexBattleSurgeBuff.SURGE_BUFF)
	arr.append(HexBattleExposeBuff.EXPOSE_BUFF)
	arr.append(HexBattleStunBuff.create_config(HexBattleStunBuff.DEFAULT_DURATION_MS))
	arr.append(HexBattleSilenceBuff.create_config(HexBattleSilenceBuff.DEFAULT_DURATION_MS))
	arr.append(HexBattleBreakBuff.create_config(HexBattleBreakBuff.DEFAULT_DURATION_MS))
	return arr


## 把所有 timeline 注册进 TimelineRegistry。战斗启动时调一次。
## 来源 = 各 config 树携带的 TimelineData(builder.timeline 写入), 同引用重复注册幂等。
static func register_all_timelines() -> void:
	for cfg in _build_manifest():
		for tl in cfg.collect_timelines():
			TimelineRegistry.register(tl)


## 返回 manifest 里所有 AbilityConfig(含 skill / passive / buff)
static func all_abilities() -> Array[AbilityConfig]:
	return _build_manifest()
