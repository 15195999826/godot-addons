## RangedAttackStrategy - 远程攻击策略
##
## 适用职业：弓箭手、法师
##
## 决策优先级：
## 1. 技能就绪 + 射程内有敌人 → 攻击 HP 最低的敌人
## 2. 射程内无敌人 → 向最近敌人移动（缩短距离进入射程）
## 3. 技能 CD 中 + 敌人已在身边 → 远离最近敌人（风筝）
## 4. 无法移动 → 跳过
class_name RangedAttackStrategy
extends AIStrategy


func decide(actor: CharacterActor, battle: HexBattle) -> Dictionary:
	var skill := actor.get_skill_ability()
	var skill_ready := not actor.ability_set.is_on_cooldown(skill.config_id)
	var skill_range := skill.get_meta_int(HexBattleSkillMetaKeys.RANGE, 1)

	# 1. 技能就绪 → 找射程内 HP 最低的敌人
	if skill_ready:
		var valid_targets := _get_valid_skill_targets(actor, skill, battle)
		if valid_targets.size() > 0:
			var target := _select_lowest_hp(valid_targets)
			return _make_skill_decision(skill, target)

	var enemies := _get_enemies(actor, battle)
	if not actor.hex_position.is_valid() or enemies.is_empty():
		return { "type": "skip" }

	var nearest := _select_nearest(actor, enemies)
	var dist_to_nearest := actor.hex_position.distance_to(nearest.hex_position)

	# 2. 技能就绪但射程外 → 靠近敌人进入射程
	if skill_ready:
		var move_coord := _move_toward(actor, nearest.hex_position)
		if move_coord != null:
			return _make_move_decision(actor, move_coord)

	# 3. 技能 CD 中 + 敌人太近（距离 <= 2）→ 风筝后撤
	if dist_to_nearest <= 2:
		var retreat_coord := _move_away_from(actor, nearest.hex_position)
		if retreat_coord != null:
			return _make_move_decision(actor, retreat_coord)

	# 4. 跳过（技能 CD 中且距离安全，原地等待）
	return { "type": "skip" }
