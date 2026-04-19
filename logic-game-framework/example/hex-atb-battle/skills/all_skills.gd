## 所有"每文件一技能"技能的 timeline 注册目录
##
## 唯一职责：把所有技能的 TimelineData 注册到 TimelineRegistry。
## 消费点：hex_battle.gd::_register_timelines / SkillPreviewBattle.gd（沙盒战斗）
##
## 加一个有 timeline 的新技能 = 下面 register_all_timelines() 里加一行（每个 TimelineData 一行）。
## 纯被动技能（无 timeline，如 Thorn / DeathrattleAoe / Vitality / Vigor）= 此文件不用动。
class_name HexBattleAllSkills


static func register_all_timelines() -> void:
	TimelineRegistry.register(HexBattleMove.MOVE_TIMELINE)
	TimelineRegistry.register(HexBattleStrike.STRIKE_TIMELINE)
	TimelineRegistry.register(HexBattlePreciseShot.PRECISE_SHOT_TIMELINE)
	TimelineRegistry.register(HexBattlePreciseShot.PRECISE_SHOT_HIT_TIMELINE)
	TimelineRegistry.register(HexBattleFireball.FIREBALL_TIMELINE)
	TimelineRegistry.register(HexBattleFireball.FIREBALL_HIT_TIMELINE)
	TimelineRegistry.register(HexBattleCrushingBlow.CRUSHING_BLOW_TIMELINE)
	TimelineRegistry.register(HexBattleSwiftStrike.SWIFT_STRIKE_TIMELINE)
	TimelineRegistry.register(HexBattleHolyHeal.HOLY_HEAL_TIMELINE)
	TimelineRegistry.register(HexBattlePoison.POISON_TIMELINE)
	TimelineRegistry.register(HexBattlePoisonBuff.POISON_TICK_TIMELINE)
