## AIStrategy - AI 策略基类
##
## 定义 AI 决策接口。策略对象是无状态的共享实例，
## decide() 方法禁止修改 self（与 Action 设计一致）。
##
## 返回值格式与原 _decide_action() 一致：
##   { "type": "skill", "ability_instance_id": ..., "target_actor_id": ... }
##   { "type": "move", "ability_instance_id": ..., "target_coord": ... }
##   { "type": "skip" }
class_name AIStrategy


## AI 决策：决定 actor 本回合的行动
## 子类必须覆盖此方法
func decide(actor: CharacterActor, battle: HexBattle) -> Dictionary:
	return { "type": "skip" }


# ============================================================
# 通用工具方法（子类共用）
# ============================================================

## 收集敌方存活单位
func _get_enemies(actor: CharacterActor, battle: HexBattle) -> Array[CharacterActor]:
	var enemies: Array[CharacterActor] = []
	for a in battle.get_alive_actors():
		if a.get_team_id() != actor.get_team_id():
			enemies.append(a)
	return enemies


## 收集友方存活单位（不含自己）
func _get_allies(actor: CharacterActor, battle: HexBattle) -> Array[CharacterActor]:
	var allies: Array[CharacterActor] = []
	for a in battle.get_alive_actors():
		if a.get_team_id() == actor.get_team_id() and a.get_id() != actor.get_id():
			allies.append(a)
	return allies


## 获取技能有效目标列表
func _get_valid_skill_targets(actor: CharacterActor, skill: Ability, battle: HexBattle) -> Array[CharacterActor]:
	var targets: Array[CharacterActor] = []
	for target in battle.get_alive_actors():
		if battle.can_use_skill_on(actor, skill, target):
			targets.append(target)
	return targets


## 从候选列表中选择 HP 最低的目标
func _select_lowest_hp(candidates: Array[CharacterActor]) -> CharacterActor:
	if candidates.is_empty():
		return null
	var best: CharacterActor = candidates[0]
	for i in range(1, candidates.size()):
		if candidates[i].attribute_set.hp < best.attribute_set.hp:
			best = candidates[i]
	return best


## 从候选列表中选择 HP 百分比最低的目标
func _select_lowest_hp_percent(candidates: Array[CharacterActor]) -> CharacterActor:
	if candidates.is_empty():
		return null
	var best: CharacterActor = candidates[0]
	var best_pct := best.attribute_set.hp / best.attribute_set.max_hp
	for i in range(1, candidates.size()):
		var pct := candidates[i].attribute_set.hp / candidates[i].attribute_set.max_hp
		if pct < best_pct:
			best_pct = pct
			best = candidates[i]
	return best


## 从候选列表中选择最近的目标
func _select_nearest(actor: CharacterActor, candidates: Array[CharacterActor]) -> CharacterActor:
	if candidates.is_empty():
		return null
	var my_pos := actor.hex_position
	var best: CharacterActor = candidates[0]
	var best_dist := my_pos.distance_to(best.hex_position)
	for i in range(1, candidates.size()):
		var dist := my_pos.distance_to(candidates[i].hex_position)
		if dist < best_dist:
			best_dist = dist
			best = candidates[i]
	return best


## 构建技能决策结果
func _make_skill_decision(skill: Ability, target: CharacterActor) -> Dictionary:
	return {
		"type": "skill",
		"ability_instance_id": skill.id,
		"target_actor_id": target.get_id(),
	}


## 构建移动决策结果
func _make_move_decision(actor: CharacterActor, coord: HexCoord) -> Dictionary:
	return {
		"type": "move",
		"ability_instance_id": actor.get_move_ability().id,
		"target_coord": coord,
	}


## 向目标移动：从邻居格子中选出最接近 target_pos 的可用格子
func _move_toward(actor: CharacterActor, target_pos: HexCoord) -> HexCoord:
	var my_pos := actor.hex_position
	var current_dist := my_pos.distance_to(target_pos)
	var neighbors: Array[HexCoord] = my_pos.get_neighbors()
	var best_coord: HexCoord = null
	var best_dist := current_dist  # 必须比当前更近才移动
	for n in neighbors:
		if _is_tile_available(n):
			var dist := n.distance_to(target_pos)
			if dist < best_dist:
				best_dist = dist
				best_coord = n
	return best_coord


## 远离目标移动：从邻居格子中选出最远离 threat_pos 的可用格子
func _move_away_from(actor: CharacterActor, threat_pos: HexCoord) -> HexCoord:
	var my_pos := actor.hex_position
	var current_dist := my_pos.distance_to(threat_pos)
	var neighbors: Array[HexCoord] = my_pos.get_neighbors()
	var best_coord: HexCoord = null
	var best_dist := current_dist  # 必须比当前更远才移动
	for n in neighbors:
		if _is_tile_available(n):
			var dist := n.distance_to(threat_pos)
			if dist > best_dist:
				best_dist = dist
				best_coord = n
	return best_coord


## 检查格子是否可用（存在、未占用、未预订）
func _is_tile_available(coord: HexCoord) -> bool:
	return UGridMap.model.has_tile(coord) \
		and not UGridMap.model.is_occupied(coord) \
		and not UGridMap.model.is_reserved(coord)
