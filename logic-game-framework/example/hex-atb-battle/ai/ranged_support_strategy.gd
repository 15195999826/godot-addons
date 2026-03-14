## RangedSupportStrategy - 远程辅助策略
##
## 适用职业：牧师
##
## 决策优先级：
## 1. 技能就绪 + 射程内有受伤队友 → 治疗 HP% 最低的队友
## 2. 射程内无受伤队友 → 向 HP% 最低的受伤队友移动
## 3. 所有队友满血 → 跳过（原地等待）
class_name RangedSupportStrategy
extends AIStrategy


func decide(actor: CharacterActor, battle: HexBattle) -> Dictionary:
	var skill := actor.get_skill_ability()
	var skill_ready := not actor.ability_set.is_on_cooldown(skill.config_id)

	# 1. 技能就绪 → 找射程内 HP% 最低的受伤队友
	if skill_ready:
		var valid_targets := _get_valid_skill_targets(actor, skill, battle)
		# 只治疗受伤的队友
		var wounded: Array[CharacterActor] = []
		for target in valid_targets:
			if target.attribute_set.hp < target.attribute_set.max_hp:
				wounded.append(target)

		if wounded.size() > 0:
			var target := _select_lowest_hp_percent(wounded)
			return _make_skill_decision(skill, target)

	# 2. 找全场受伤队友，向其移动
	var allies := _get_allies(actor, battle)
	var wounded_allies: Array[CharacterActor] = []
	for ally in allies:
		if ally.attribute_set.hp < ally.attribute_set.max_hp:
			wounded_allies.append(ally)

	if wounded_allies.size() > 0 and actor.hex_position.is_valid():
		var target_ally := _select_lowest_hp_percent(wounded_allies)
		var move_coord := _move_toward(actor, target_ally.hex_position)
		if move_coord != null:
			return _make_move_decision(actor, move_coord)

	# 3. 所有队友满血或无法移动 → 跳过
	return { "type": "skip" }
