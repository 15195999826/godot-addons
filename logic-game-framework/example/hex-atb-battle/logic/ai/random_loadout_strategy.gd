## RandomLoadoutStrategy - demo_random_frontend 专用的通用技能 AI。
##
## 目标不是打得聪明, 而是让随机替换后的主技能能在 production HexBattleProcedure
## 里真实跑起来: self / ally / enemy / cone 技能都走同一个入口。
class_name RandomLoadoutStrategy
extends AIStrategy


const STATUS_UTILITY_BY_SKILL := {
	"skill_expose": "buff_expose",
	"skill_silence": "buff_silence",
	"skill_stun": "buff_stun",
	"skill_break": "buff_break",
}


func decide(actor: CharacterActor, battle: HexWorldGameplayInstance) -> Dictionary:
	var skill := actor.get_skill_ability()
	if skill != null and not actor.ability_set.is_on_cooldown(skill.config_id):
		var skill_decision := _decide_skill(actor, skill, battle)
		if not skill_decision.is_empty():
			return skill_decision
	var fallback_skill := _get_fallback_skill(actor, skill)
	if fallback_skill != null and not actor.ability_set.is_on_cooldown(fallback_skill.config_id):
		var fallback_decision := _decide_skill(actor, fallback_skill, battle)
		if not fallback_decision.is_empty():
			return fallback_decision
	return _decide_movement(actor, battle)


func _decide_skill(actor: CharacterActor, skill: Ability, battle: HexWorldGameplayInstance) -> Dictionary:
	if skill.has_ability_tag("self") and battle.can_use_skill_on(actor, skill, actor):
		return _make_targeted_skill_decision(skill, actor)

	var candidates := _collect_valid_targets(actor, skill, battle)
	if candidates.is_empty():
		return {}
	if STATUS_UTILITY_BY_SKILL.has(skill.config_id):
		candidates = _filter_targets_without_status(candidates, STATUS_UTILITY_BY_SKILL[skill.config_id])
		if candidates.is_empty():
			return {}

	if skill.has_ability_tag("heal"):
		var wounded := _filter_wounded(candidates)
		if wounded.is_empty():
			return {}
		return _make_targeted_skill_decision(skill, _select_lowest_hp_percent(wounded))

	if skill.has_ability_tag("ally"):
		return _make_targeted_skill_decision(skill, _select_lowest_hp_percent(candidates))

	return _make_targeted_skill_decision(skill, _select_lowest_hp(candidates))


func _get_fallback_skill(actor: CharacterActor, primary_skill: Ability) -> Ability:
	if primary_skill != null and primary_skill.config_id == HexBattleStrike.CONFIG_ID:
		return null
	return actor.ability_set.find_ability_by_config_id(HexBattleStrike.CONFIG_ID)


func _collect_valid_targets(
	actor: CharacterActor,
	skill: Ability,
	battle: HexWorldGameplayInstance
) -> Array[CharacterActor]:
	var targets: Array[CharacterActor] = []
	for target in battle.get_alive_actors():
		if _should_skip_target(actor, skill, target):
			continue
		if battle.can_use_skill_on(actor, skill, target):
			targets.append(target)
	return targets


func _filter_targets_without_status(
	candidates: Array[CharacterActor],
	status_config_id: String
) -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	for target in candidates:
		if not target.ability_set.has_ability(status_config_id):
			result.append(target)
	return result


func _should_skip_target(actor: CharacterActor, skill: Ability, target: CharacterActor) -> bool:
	if skill.has_ability_tag("enemy"):
		return target.get_team_id() == actor.get_team_id()
	if skill.has_ability_tag("ally"):
		return target.get_team_id() != actor.get_team_id()
	if skill.has_ability_tag("self"):
		return target.get_id() != actor.get_id()
	return target.get_id() == actor.get_id()


func _filter_wounded(candidates: Array[CharacterActor]) -> Array[CharacterActor]:
	var wounded: Array[CharacterActor] = []
	for target in candidates:
		if target.attribute_set.hp < target.attribute_set.max_hp:
			wounded.append(target)
	return wounded


func _make_targeted_skill_decision(skill: Ability, target: CharacterActor) -> Dictionary:
	var decision := _make_skill_decision(skill, target)
	if skill.has_ability_tag("cone"):
		decision["target_coord"] = target.hex_position
	return decision


func _decide_movement(actor: CharacterActor, battle: HexWorldGameplayInstance) -> Dictionary:
	var enemies := _get_enemies(actor, battle)
	if not actor.hex_position.is_valid() or enemies.is_empty():
		return { "type": "skip" }
	var nearest := _select_nearest(actor, enemies)
	var move_coord := _move_toward(actor, nearest.hex_position)
	if move_coord != null:
		return _make_move_decision(actor, move_coord)
	return { "type": "skip" }
