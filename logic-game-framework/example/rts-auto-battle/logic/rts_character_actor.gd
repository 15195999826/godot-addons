## RtsCharacterActor - RTS 兵种角色 Actor
##
## RtsBattleActor 的子类: 持兵种 enum + 数值 attribute_set + ability_set + attack cooldown 状态机。
## 所有具体战斗单位走此类(M0 只有 melee / ranged 两种, 区分仅在 unit_class 与数值表)。
class_name RtsCharacterActor
extends RtsBattleActor


# ========== 字段 ==========

## 兵种 enum
var unit_class: RtsUnitClassConfig.UnitClass

## 强类型 attribute_set: 公共 hp/max_hp 视图也通过此字段暴露
var attribute_set: RtsUnitAttributeSet

## AbilitySet — 战斗管线平权(留 hook 给 buff/passive); 直接用 core AbilitySet, 不依赖 hex 例子的
## BattleAbilitySet (RTS 用 actor.attack_cooldown_remaining 自管 cooldown, 不走 tag 过期路径)。
var ability_set: AbilitySet

## RTS 实时 cooldown(秒); = 0 时 AI 决定攻击, 攻击后重置为 1 / attack_speed
var attack_cooldown_remaining: float = 0.0

## 当前目标的 actor id; 空表示没目标(初始 / 目标已死)
var current_target_id: String = ""


# ========== 初始化 ==========

func _init(p_unit_class: RtsUnitClassConfig.UnitClass) -> void:
	unit_class = p_unit_class
	type = "Character"

	var stats := RtsUnitClassConfig.get_stats(p_unit_class)
	_display_name = stats.name

	attribute_set = RtsUnitAttributeSet.new(get_id())
	# max_hp 必须先于 hp: cross-attr clamp(hp <= max_hp) 在 set_hp_base 时按当前 max_hp 截。
	attribute_set.set_max_hp_base(stats.max_hp)
	attribute_set.set_hp_base(stats.hp)
	attribute_set.set_atk_base(stats.atk)
	attribute_set.set_def_base(stats.def)
	attribute_set.set_move_speed_base(stats.move_speed)
	attribute_set.set_attack_speed_base(stats.attack_speed)
	attribute_set.set_attack_range_base(stats.attack_range)

	ability_set = AbilitySet.new(get_id(), attribute_set)


# ========== Actor 合同 ==========

## ID 被 add_actor 分配后, 同步 ability_set / attribute_set 内引用的 owner_id。
func _on_id_assigned() -> void:
	ability_set.owner_actor_id = get_id()
	attribute_set.actor_id = get_id()


# ========== AbilitySet 协议 ==========

## RtsAutoBattleProcedure 通过 has_method("get_ability_set") 探测; 显式提供。
func get_ability_set() -> AbilitySet:
	return ability_set


# ========== Cooldown 控制 ==========

## tick 推进 cooldown(秒)。procedure 每 tick 调用一次。
func tick_attack_cooldown(dt: float) -> void:
	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining = max(0.0, attack_cooldown_remaining - dt)


## 是否冷却完毕、可发起 basic attack
func can_attack() -> bool:
	return attack_cooldown_remaining <= 0.0 and not is_dead()


## 重置 cooldown 为 1 / attack_speed
func reset_attack_cooldown() -> void:
	var atk_speed := attribute_set.attack_speed
	if atk_speed <= 0.0:
		attack_cooldown_remaining = 9999.0
	else:
		attack_cooldown_remaining = 1.0 / atk_speed


# ========== 录像支持 ==========

func _get_config_id() -> String:
	return RtsUnitClassConfig.to_string_name(unit_class)


func get_attribute_snapshot() -> Dictionary:
	return attribute_set.snapshot()


func get_ability_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ability in ability_set.get_abilities():
		result.append({
			"instance_id": ability.id,
			"config_id": ability.config_id,
		})
	return result


func get_tag_snapshot() -> Dictionary:
	return ability_set.get_all_tags()
