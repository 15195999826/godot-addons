## MeleeAttackStrategy - 近战攻击策略
##
## 适用职业：战士、狂战士、刺客
##
## 决策优先级：
## 1. 技能就绪 + 射程内有敌人 → 攻击 HP 最低的敌人
## 2. 否则 → 向最近敌人移动
## 3. 无法移动 → 跳过
class_name MeleeAttackStrategy
extends AIStrategy


func decide(actor: CharacterActor, battle: HexBattle) -> Dictionary:
	var skill := actor.get_skill_ability()
	var skill_ready := not actor.ability_set.is_on_cooldown(skill.config_id)

	# 1. 技能就绪 → 找射程内 HP 最低的敌人
	if skill_ready:
		var valid_targets := _get_valid_skill_targets(actor, skill, battle)
		if valid_targets.size() > 0:
			var target := _select_lowest_hp(valid_targets)
			return _make_skill_decision(skill, target)

	# 2. 向最近敌人移动
	var enemies := _get_enemies(actor, battle)
	if actor.hex_position.is_valid() and enemies.size() > 0:
		var nearest := _select_nearest(actor, enemies)
		var move_coord := _move_toward(actor, nearest.hex_position)
		if move_coord != null:
			return _make_move_decision(actor, move_coord)

	# 3. 跳过
	return { "type": "skip" }
