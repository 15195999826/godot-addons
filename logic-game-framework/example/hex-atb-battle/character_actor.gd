## CharacterActor - 角色 Actor
##
## 继承自 Actor，实现 ATB 系统和战斗属性
class_name CharacterActor
extends Actor


# ========== 常量 ==========

const ATB_FULL := 100.0


# ========== 属性 ==========

var character_class: HexBattleClassConfig.CharacterClass
## 生成式属性集
var attribute_set: HexBattleCharacterAttributeSet
var ability_set: BattleAbilitySet
var _is_dead: bool = false

## AI 策略
var ai_strategy: AIStrategy

## 当前位置（六边形坐标）
## 使用 HexCoord.invalid() 表示未设置位置，在 _init 中初始化
var hex_position: HexCoord = HexCoord.invalid()

## 移动 Ability ID
var _move_ability_id: String = ""

## 职业技能 Ability ID
var _skill_ability_id: String = ""

## 队伍 ID
var _team_id: int = -1

## ATB 行动条（0-100）
var _atb_gauge: float = 0.0


# ========== 初始化 ==========

func _init(p_character_class: HexBattleClassConfig.CharacterClass) -> void:
	character_class = p_character_class
	type = "Character"
	
	var class_config := HexBattleClassConfig.get_class_config(character_class)
	_display_name = class_config.name
	
	attribute_set = HexBattleCharacterAttributeSet.new(get_id())
	_setup_attribute_constraints()
	var stats := class_config.stats
	# max_hp 必须在 hp 之前设置，否则 pre_change 约束（hp ≤ max_hp）
	# 会用默认的 max_hp=100 来 clamp hp，导致 hp > 100 的角色初始不满血
	attribute_set.set_max_hp_base(stats["max_hp"])
	attribute_set.set_hp_base(stats["hp"])
	attribute_set.set_atk_base(stats["atk"])
	attribute_set.set_def_base(stats["def"])
	attribute_set.set_speed_base(stats["speed"])
	ability_set = BattleAbilitySet.create_battle_ability_set(get_id(), attribute_set)
	ai_strategy = AIStrategyFactory.get_strategy(character_class)


## 设置属性约束
func _setup_attribute_constraints() -> void:
	# hp 的 current 值不超过 max_hp
	# 注意：hp base ≥ 0 已通过 minValue 配置实现
	attribute_set.set_pre_change(func(attr_name: String, inout_value: Dictionary) -> void:
		if attr_name == "hp":
			var max_hp := attribute_set.max_hp
			if inout_value["value"] > max_hp:
				inout_value["value"] = max_hp
	)


## ID 被 add_actor 分配后，同步 ability_set 和 attribute_set 的 owner 引用
func _on_id_assigned() -> void:
	ability_set.owner_actor_id = get_id()
	attribute_set.actor_id = get_id()


## 装备技能（在 HexBattle 初始化时调用）
func equip_abilities() -> void:
	var move_ability := Ability.new(HexBattleMove.ABILITY, get_id())
	ability_set.grant_ability(move_ability)
	_move_ability_id = move_ability.id
	
	var skill_config := HexBattleSkillConfig.get_class_skill(character_class)
	var skill_ability := Ability.new(skill_config, get_id())
	ability_set.grant_ability(skill_ability)
	_skill_ability_id = skill_ability.id
	_grant_class_passives()


## 根据职业装备被动技能
func _grant_class_passives() -> void:
	# 战士：荆棘反伤
	if character_class == HexBattleClassConfig.CharacterClass.WARRIOR:
		var thorn_passive := Ability.new(HexBattleThorn.ABILITY, get_id())
		ability_set.grant_ability(thorn_passive)

	# 狂战士：死亡爆发（亡语 - 死亡时对所有敌方造成 20 点纯粹伤害）
	if character_class == HexBattleClassConfig.CharacterClass.BERSERKER:
		var deathrattle := Ability.new(HexBattleDeathrattleAoe.ABILITY, get_id())
		ability_set.grant_ability(deathrattle)

	# 法师：生命力 + 活力（互相依赖的被动，用于验证收敛机制）
	# 生命力：atk += max_hp * 0.01
	# 活力：max_hp += atk * 0.1
	if character_class == HexBattleClassConfig.CharacterClass.MAGE:
		var vitality_passive := Ability.new(HexBattleVitality.ABILITY, get_id())
		var vigor_passive := Ability.new(HexBattleVigor.ABILITY, get_id())
		ability_set.grant_ability(vitality_passive)
		ability_set.grant_ability(vigor_passive)
		Log.debug("CharacterActor", "[收敛验证] 法师装备了互相依赖的被动：生命力 + 活力")


# ========== 队伍 ==========

func set_team_id(id: int) -> void:
	_team_id = id
	_team = str(id)


func get_team_id() -> int:
	return _team_id


# ========== Ability 访问 ==========

## 获取移动 Ability
func get_move_ability() -> Ability:
	return ability_set.find_ability_by_id(_move_ability_id)


## 获取技能 Ability
func get_skill_ability() -> Ability:
	return ability_set.find_ability_by_id(_skill_ability_id)


## 获取 AbilitySet（实现 IAbilitySetOwner 协议）
func get_ability_set() -> BattleAbilitySet:
	return ability_set

## 获取当前属性快照
func get_stats() -> Dictionary:
	return {
		"hp": attribute_set.hp,
		"max_hp": attribute_set.max_hp,
		"atk": attribute_set.atk,
		"def": attribute_set.def,
		"speed": attribute_set.speed,
	}


# ========== ATB 系统 ==========

## 获取 ATB 值
func get_atb_gauge() -> float:
	return _atb_gauge


## 累积 ATB（按速度）
func accumulate_atb(dt: float) -> void:
	_atb_gauge += (attribute_set.speed / 1000.0) * dt


## 是否可以行动
func can_act() -> bool:
	return _atb_gauge >= ATB_FULL


## 重置 ATB
func reset_atb() -> void:
	_atb_gauge = 0.0


# ========== 生命周期 ==========

## 检查是否死亡
func check_death() -> bool:
	if attribute_set.hp <= 0 and not _is_dead:
		_is_dead = true
		return true
	return false

func is_dead() -> bool:
	return _is_dead


## 覆盖框架虚函数：死亡的角色不再响应 PreEvent handler
## 例如：反伤 passive 在死后不再触发；复活后自动恢复响应（无需重新注册 handler）
func is_pre_event_responsive() -> bool:
	return not _is_dead


# ========== 录像支持（覆盖 Actor 基类方法） ==========

## 获取配置 ID（覆盖基类）
func _get_config_id() -> String:
	return HexBattleClassConfig.class_to_string(character_class)


## 获取队伍 ID（覆盖基类）
func _get_team_int() -> int:
	return _team_id


## 获取位置（覆盖基类，返回 hex 坐标作为 Vector3）
## 格式：Vector3(q, r, 0)，第三个分量保留用于高度扩展
## 具体含义由 configs.positionFormats["Character"] = "hex" 声明
func _get_position() -> Vector3:
	if not hex_position.is_valid():
		return Vector3.ZERO
	return Vector3(hex_position.q, hex_position.r, 0)


## 获取属性快照（覆盖基类）
func get_attribute_snapshot() -> Dictionary:
	return get_stats()


## 获取 Ability 快照（覆盖基类）
func get_ability_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ability in ability_set.get_abilities():
		result.append({
			"instance_id": ability.id,
			"config_id": ability.config_id,
		})
	return result


## 获取 Tag 快照（覆盖基类）
func get_tag_snapshot() -> Dictionary:
	return ability_set.get_all_tags()


## 设置录像回调（覆盖基类）
func setup_recording(ctx: RecordingContext) -> Array[Callable]:
	var unsubscribes: Array[Callable] = []
	unsubscribes.append_array(RecordingUtils.record_attribute_changes(attribute_set, ctx))
	unsubscribes.append_array(RecordingUtils.record_ability_set_changes(ability_set, ctx))
	unsubscribes.append_array(RecordingUtils.record_actor_lifecycle(self, ctx))
	return unsubscribes


# ========== 序列化 ==========

func serialize() -> Dictionary:
	var base := serialize_base()
	base["character_class"] = HexBattleClassConfig.class_to_string(character_class)
	base["hex_position"] = hex_position.to_dict() if hex_position.is_valid() else {}
	base["atb_gauge"] = _atb_gauge
	base["attribute_set"] = attribute_set._raw.serialize()
	return base
