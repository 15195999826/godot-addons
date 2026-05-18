## Dota2UnitActor - lane creep（单位）Actor
##
## Dota2BattleActor 子类：持兵种 enum + 强类型 Dota2UnitAttributeSet + ability_set。
## actor-attributes.md：专属代码直接 unit.attribute_set.attack_damage；公共代码走
## get_attribute_set() 拿 hp/max_hp 视图。spawn 顺序 max_hp 先于 hp（cross-clamp 不误截）。
## 基础攻击 Ability 在 add_actor 后由 equip_basic_attack() 装备（owner id 已就位）。
class_name Dota2UnitActor
extends Dota2BattleActor


var unit_type: Dota2UnitTypeConfig.UnitType
var attribute_set: Dota2UnitAttributeSet


func _init(p_unit_type: Dota2UnitTypeConfig.UnitType) -> void:
	unit_type = p_unit_type
	type = "Dota2Unit"

	var stats := Dota2UnitTypeConfig.get_stats(p_unit_type)
	_display_name = stats.display_name

	attribute_set = Dota2UnitAttributeSet.new()
	# max_hp 必须先于 hp：cross-attr clamp (hp <= max_hp) 在 set_hp_base 时按当前 max_hp 截。
	attribute_set.set_max_hp_base(stats.max_hp)
	attribute_set.set_hp_base(stats.hp)
	attribute_set.set_attack_damage_base(stats.attack_damage)
	attribute_set.set_attack_range_base(stats.attack_range)
	attribute_set.set_attack_interval_ms_base(stats.attack_interval_ms)
	attribute_set.set_move_speed_base(stats.move_speed)
	attribute_set.set_aggro_range_base(stats.aggro_range)

	collision_radius = stats.collision_radius
	ability_set = AbilitySet.new(get_id(), attribute_set)


# ========== Dota2BattleActor 合同实现 ==========

func get_attribute_set() -> Dota2BattleActorAttributeSet:
	return attribute_set


# ========== Ability 装备（add_actor 之后调，owner id 已就位）==========

## 装备基础攻击 Ability。spawner 在 world.add_actor() 后调 —— 此时 get_id() 是真 id，
## Ability.owner_actor_id / ability_set.owner_actor_id 都对得上。
func equip_basic_attack() -> void:
	if ability_set.has_ability(Dota2BasicAttackAbility.CONFIG_ID):
		return
	var ability := Ability.new(Dota2BasicAttackAbility.ABILITY, get_id())
	ability_set.grant_ability(ability)


func get_basic_attack_ability() -> Ability:
	return ability_set.find_ability_by_config_id(Dota2BasicAttackAbility.CONFIG_ID)


# ========== 查询 / 快照 ==========

func get_unit_type_id() -> String:
	return Dota2UnitTypeConfig.to_string_name(unit_type)


func _get_config_id() -> String:
	return get_unit_type_id()


func get_attribute_snapshot() -> Dictionary:
	return {
		"hp": attribute_set.hp,
		"max_hp": attribute_set.max_hp,
		"attack_damage": attribute_set.attack_damage,
		"attack_range": attribute_set.attack_range,
		"attack_interval_ms": attribute_set.attack_interval_ms,
		"move_speed": attribute_set.move_speed,
		"aggro_range": attribute_set.aggro_range,
	}
