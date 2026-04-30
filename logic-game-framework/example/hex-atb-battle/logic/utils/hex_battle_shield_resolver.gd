## HexBattleShieldResolver - 护盾结算器（项目层纯结算工具）
##
## 输入：actor + 已修正后的伤害值 + 伤害类型
## 输出：实际生命伤害 + 护盾吸收总量 + 护盾消耗记录
##
## 副作用：仅修改各 ShieldComponent.current（这是它的职责）。
##         不 push 事件、不扣 actor.hp、不触发 on_break / on_expire 回调，也不 expire ability。
##         这些由调用方（HexBattleDamageUtils.apply_damage）按文档流程顺序处理。
##
## 排序规则（确定性）：
##   1. damage_type 过滤：硬过滤，护盾的 damage_types 不含本次类型则直接跳过
##   2. priority 降序：高优先级先消耗
##   3. grant_index 降序：同优先级时后获得的先消耗（LIFO）
##   4. ability.id 字典序升序：兜底 determinism
##
## 仅静态方法，不持有状态。
class_name HexBattleShieldResolver


## 单次结算的返回结果。
class Result extends RefCounted:
	## 穿透护盾后实际打到生命的伤害（>= 0）
	var life_damage: float = 0.0
	## 本次伤害被护盾吸收的总量
	var shield_absorbed: float = 0.0
	## 消耗记录数组，每条字段见下方说明
	var consumption_records: Array[Dictionary] = []


## resolve - 计算护盾吸收 + 提交护盾容量变更
##
## consumption_records 每条字段：
##   shield_ability_id / shield_config_id / owner_actor_id / source_actor_id /
##   capacity / remaining / priority / absorbed / broken / damage_type
##
## 调用方需对每个 broken=true 的记录在伤害事件 push 之后、actor 移除之前
## 触发 ShieldComponent.on_break 回调并 expire 对应 ability。
static func resolve(actor: Object, incoming_damage: float, damage_type: String) -> Result:
	var result := Result.new()
	if actor == null or incoming_damage <= 0.0:
		result.life_damage = maxf(0.0, incoming_damage)
		return result

	var ability_set: AbilitySet = null
	if "ability_set" in actor:
		ability_set = actor.get("ability_set") as AbilitySet
	if ability_set == null:
		result.life_damage = incoming_damage
		return result

	var candidates := _collect_candidates(ability_set, damage_type)
	if candidates.is_empty():
		result.life_damage = incoming_damage
		return result

	candidates.sort_custom(_compare_candidates)

	var remaining := incoming_damage
	for entry in candidates:
		if remaining <= 0.0:
			break
		var shield: HexBattleShieldComponent = entry["shield"]
		var consume_result := shield.consume(remaining, damage_type)
		var absorbed: float = consume_result["absorbed"] as float
		if absorbed <= 0.0:
			continue
		remaining -= absorbed
		result.shield_absorbed += absorbed
		var record := shield.get_state_snapshot()
		record["absorbed"] = absorbed
		record["broken"] = consume_result["broken"]
		record["damage_type"] = damage_type
		result.consumption_records.append(record)

	result.life_damage = maxf(0.0, remaining)
	return result


## 找出所有可参与本次伤害结算的护盾候选。
## 返回每条 { ability, shield, grant_index } 的字典。
static func _collect_candidates(ability_set: AbilitySet, damage_type: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var abilities := ability_set.get_abilities()
	for i in range(abilities.size()):
		var ability := abilities[i]
		if ability == null or ability.is_expired():
			continue
		var shield := _find_shield_component(ability)
		if shield == null:
			continue
		if shield.current <= 0.0:
			continue
		if not shield.can_absorb(damage_type):
			continue
		candidates.append({
			"ability": ability,
			"shield": shield,
			"grant_index": i,
		})
	return candidates


## 排序：priority desc → grant_index desc → ability.id asc
static func _compare_candidates(a: Dictionary, b: Dictionary) -> bool:
	var sa: HexBattleShieldComponent = a["shield"]
	var sb: HexBattleShieldComponent = b["shield"]
	if sa.priority != sb.priority:
		return sa.priority > sb.priority
	var ia: int = a["grant_index"] as int
	var ib: int = b["grant_index"] as int
	if ia != ib:
		return ia > ib
	var ability_a: Ability = a["ability"]
	var ability_b: Ability = b["ability"]
	return ability_a.id < ability_b.id


static func _find_shield_component(ability: Ability) -> HexBattleShieldComponent:
	for component in ability.get_all_components():
		if component is HexBattleShieldComponent:
			return component as HexBattleShieldComponent
	return null
