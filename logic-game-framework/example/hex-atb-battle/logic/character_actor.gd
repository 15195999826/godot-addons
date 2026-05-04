## CharacterActor - 角色 Actor
##
## HexBattleActor 的子类, 实现 ATB 系统、AI 策略、职业技能。
## 公共基础设施 (hex_position / ability_set / is_dead / check_death / 录像) 由 HexBattleActor 提供。
class_name CharacterActor
extends HexBattleActor


# ========== 常量 ==========

const ATB_FULL := 100.0


# ========== 字段 ==========

var character_class: HexBattleClassConfig.CharacterClass

## 强类型 attribute_set: 角色专属 atk / def / speed 通过此字段直接访问。
## 公共代码 (DamageUtils / game_state_utils) 走 get_attribute_set() 拿基类视图读 hp/max_hp。
var attribute_set: HexBattleCharacterAttributeSet

## AI 策略
var ai_strategy: AIStrategy

## 移动 Ability ID
var _move_ability_id: String = ""

## 职业技能 Ability ID
var _skill_ability_id: String = ""

## 队伍 ID
var _team_id: int = -1

## ATB 行动条 (0-100)
var _atb_gauge: float = 0.0


# ========== 初始化 ==========

func _init(p_character_class: HexBattleClassConfig.CharacterClass) -> void:
	character_class = p_character_class
	type = "Character"

	var class_config := HexBattleClassConfig.get_class_config(character_class)
	_display_name = class_config.name

	attribute_set = HexBattleCharacterAttributeSet.new(get_id())
	var stats := class_config.stats
	# max_hp 必须在 hp 之前设置: 跨属性 clamp (hp ≤ max_hp) 会在 set_hp_base 时
	# 用当前 max_hp 做 clamp, 若 max_hp 还是默认 100, hp > 100 的角色会被截到 100。
	attribute_set.set_max_hp_base(stats["max_hp"])
	attribute_set.set_hp_base(stats["hp"])
	attribute_set.set_atk_base(stats["atk"])
	attribute_set.set_def_base(stats["def"])
	attribute_set.set_speed_base(stats["speed"])
	ability_set = BattleAbilitySet.create_battle_ability_set(get_id(), attribute_set)
	ai_strategy = AIStrategyFactory.get_strategy(character_class)
	collision_profile = CollisionProfile.default_character()


## 装备技能 (在 HexBattle 初始化时调用)
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
	# 战士: 荆棘反伤
	if character_class == HexBattleClassConfig.CharacterClass.WARRIOR:
		var thorn_passive := Ability.new(HexBattleThorn.ABILITY, get_id())
		ability_set.grant_ability(thorn_passive)

	# 狂战士: 死亡爆发 (亡语 - 死亡时对所有敌方造成 20 点纯粹伤害)
	if character_class == HexBattleClassConfig.CharacterClass.BERSERKER:
		var deathrattle := Ability.new(HexBattleDeathrattleAoe.ABILITY, get_id())
		ability_set.grant_ability(deathrattle)

	# 法师: 生命力 + 活力 (互相依赖的被动, 用于验证收敛机制)
	if character_class == HexBattleClassConfig.CharacterClass.MAGE:
		var vitality_passive := Ability.new(HexBattleVitality.ABILITY, get_id())
		var vigor_passive := Ability.new(HexBattleVigor.ABILITY, get_id())
		ability_set.grant_ability(vitality_passive)
		ability_set.grant_ability(vigor_passive)
		Log.debug("CharacterActor", "[收敛验证] 法师装备了互相依赖的被动: 生命力 + 活力")


# ========== HexBattleActor 合同实现 ==========

func get_attribute_set() -> HexBattleActorAttributeSet:
	return attribute_set


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


## 获取当前属性快照 (角色专属: 含 atk / def / speed)
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


## 累积 ATB (按速度)
func accumulate_atb(dt: float) -> void:
	_atb_gauge += (attribute_set.speed / 1000.0) * dt


## 是否可以行动
func can_act() -> bool:
	if _atb_gauge < ATB_FULL:
		return false
	if ability_set != null and ability_set.has_tag(HexBattleActionLockStatus.TAG_CANT_ACT):
		return false
	return true


## 重置 ATB
func reset_atb() -> void:
	_atb_gauge = 0.0


# ========== 录像支持 (覆盖基类) ==========

## 配置 ID 用职业名, 让 replay 能区分不同职业的视觉 / 数值
func _get_config_id() -> String:
	return HexBattleClassConfig.class_to_string(character_class)


## 队伍 ID
func _get_team_int() -> int:
	return _team_id


## 角色 attribute snapshot 含完整 stats (覆盖基类的 hp/max_hp 默认实现)
func get_attribute_snapshot() -> Dictionary:
	return get_stats()


# ========== 序列化 ==========

func serialize() -> Dictionary:
	var base := super.serialize()
	base["character_class"] = HexBattleClassConfig.class_to_string(character_class)
	base["atb_gauge"] = _atb_gauge
	return base
