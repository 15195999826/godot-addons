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

const SKIP_LOG_PREFIX := "[RandomAI:SKIP]"


func decide(actor: CharacterActor, battle: HexWorldGameplayInstance) -> Dictionary:
	var debug := _new_skip_debug_context(actor)
	var skill := actor.get_skill_ability()
	if skill == null:
		debug["primary_reason"] = "missing_primary_skill"
	else:
		debug["primary_skill"] = skill.config_id
		if actor.ability_set.is_on_cooldown(skill.config_id):
			debug["primary_reason"] = _cooldown_reason()
		else:
			var skill_decision := _decide_skill(actor, skill, battle, debug, "primary")
			if not skill_decision.is_empty():
				return skill_decision

	var fallback_skill := _get_fallback_skill(actor, skill)
	if fallback_skill == null:
		debug["fallback_reason"] = "no_fallback_skill"
	else:
		debug["fallback_skill"] = fallback_skill.config_id
		if actor.ability_set.is_on_cooldown(fallback_skill.config_id):
			debug["fallback_reason"] = _cooldown_reason()
		else:
			var fallback_decision := _decide_skill(actor, fallback_skill, battle, debug, "fallback")
			if not fallback_decision.is_empty():
				return fallback_decision

	var movement_decision := _decide_movement(actor, battle, debug)
	if movement_decision.get("type", "") == "skip":
		_log_skip(actor, battle, debug)
	return movement_decision


func _decide_skill(
	actor: CharacterActor,
	skill: Ability,
	battle: HexWorldGameplayInstance,
	debug: Dictionary,
	phase: String
) -> Dictionary:
	if skill.has_ability_tag("self") and battle.can_use_skill_on(actor, skill, actor):
		return _make_targeted_skill_decision(skill, actor)

	var candidates := _collect_valid_targets(actor, skill, battle)
	debug["%s_valid_targets" % phase] = candidates.size()
	if candidates.is_empty():
		debug["%s_reason" % phase] = "no_valid_target"
		return {}
	if STATUS_UTILITY_BY_SKILL.has(skill.config_id):
		var status_config_id := str(STATUS_UTILITY_BY_SKILL[skill.config_id])
		candidates = _filter_targets_without_status(candidates, status_config_id)
		debug["%s_valid_targets_without_status" % phase] = candidates.size()
		if candidates.is_empty():
			debug["%s_reason" % phase] = "all_targets_have_status:%s" % status_config_id
			return {}

	if skill.has_ability_tag("heal"):
		var wounded := _filter_wounded(candidates)
		debug["%s_wounded_targets" % phase] = wounded.size()
		if wounded.is_empty():
			debug["%s_reason" % phase] = "no_wounded_target"
			return {}
		return _make_targeted_skill_decision(skill, _select_lowest_hp_percent(wounded))

	if skill.has_ability_tag("ally"):
		return _make_targeted_skill_decision(skill, _select_lowest_hp_percent(candidates))

	return _make_targeted_skill_decision(skill, _select_lowest_hp(candidates))


func _get_fallback_skill(actor: CharacterActor, primary_skill: Ability) -> Ability:
	if primary_skill != null and primary_skill.config_id == HexBattleStrike.CONFIG_ID:
		return null
	return actor.ability_set.find_ability_by_config_id(HexBattleStrike.CONFIG_ID)


func _new_skip_debug_context(actor: CharacterActor) -> Dictionary:
	return {
		"actor_id": actor.get_id(),
		"actor_name": actor.get_display_name(),
		"actor_pos": _format_coord(actor.hex_position),
		"primary_skill": "",
		"primary_reason": "",
		"fallback_skill": "",
		"fallback_reason": "",
		"movement_reason": "",
	}


func _cooldown_reason() -> String:
	return "cooldown"


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


func _decide_movement(
	actor: CharacterActor,
	battle: HexWorldGameplayInstance,
	debug: Dictionary
) -> Dictionary:
	var enemies := _get_enemies(actor, battle)
	if not actor.hex_position.is_valid():
		debug["movement_reason"] = "invalid_actor_position"
		return _skip_decision(str(debug["movement_reason"]))
	if enemies.is_empty():
		debug["movement_reason"] = "no_alive_enemies"
		return _skip_decision(str(debug["movement_reason"]))
	var nearest := _select_nearest(actor, enemies)
	debug["nearest_enemy"] = "%s/%s" % [nearest.get_display_name(), nearest.get_id()]
	debug["nearest_pos"] = _format_coord(nearest.hex_position)
	debug["nearest_distance"] = actor.hex_position.distance_to(nearest.hex_position)
	debug["available_neighbors"] = _count_available_neighbors(actor)
	debug["closer_neighbors"] = _count_closer_neighbors(actor, nearest.hex_position)
	var move_coord := _move_toward(actor, nearest.hex_position)
	if move_coord != null:
		return _make_move_decision(actor, move_coord)
	debug["movement_reason"] = "no_strictly_closer_available_neighbor"
	return _skip_decision(str(debug["movement_reason"]))


func _skip_decision(reason: String) -> Dictionary:
	return {
		"type": "skip",
		"reason": reason,
	}


func _count_available_neighbors(actor: CharacterActor) -> int:
	if not actor.hex_position.is_valid():
		return 0
	var count := 0
	var neighbors: Array[HexCoord] = actor.hex_position.get_neighbors()
	for coord in neighbors:
		if _is_tile_available(coord):
			count += 1
	return count


func _count_closer_neighbors(actor: CharacterActor, target_pos: HexCoord) -> int:
	if not actor.hex_position.is_valid() or not target_pos.is_valid():
		return 0
	var current_dist := actor.hex_position.distance_to(target_pos)
	var count := 0
	var neighbors: Array[HexCoord] = actor.hex_position.get_neighbors()
	for coord in neighbors:
		if _is_tile_available(coord) and coord.distance_to(target_pos) < current_dist:
			count += 1
	return count


func _log_skip(
	actor: CharacterActor,
	battle: HexWorldGameplayInstance,
	debug: Dictionary
) -> void:
	var battle_id := battle.id if battle != null else ""
	var message := (
		"%s battle=%s actor_id=%s actor_name=\"%s\" pos=%s primary=%s primary_reason=%s "
		+ "fallback=%s fallback_reason=%s movement_reason=%s nearest=\"%s\" nearest_pos=%s "
		+ "nearest_distance=%s available_neighbors=%s closer_neighbors=%s"
	) % [
			SKIP_LOG_PREFIX,
			battle_id,
			actor.get_id(),
			actor.get_display_name(),
			_format_coord(actor.hex_position),
			str(debug.get("primary_skill", "")),
			str(debug.get("primary_reason", "")),
			str(debug.get("fallback_skill", "")),
			str(debug.get("fallback_reason", "")),
			str(debug.get("movement_reason", "")),
			str(debug.get("nearest_enemy", "")),
			str(debug.get("nearest_pos", "")),
			str(debug.get("nearest_distance", "")),
			str(debug.get("available_neighbors", "")),
			str(debug.get("closer_neighbors", "")),
		]
	print(message)


func _format_coord(coord: HexCoord) -> String:
	if coord == null or not coord.is_valid():
		return "invalid"
	return "(%d,%d)" % [coord.q, coord.r]
