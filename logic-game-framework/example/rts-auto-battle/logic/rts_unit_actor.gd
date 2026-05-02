## RtsUnitActor - RTS 兵种(单位) Actor
##
## RtsBattleActor 的子类: 持兵种 enum + 强类型 attribute_set + ability_set。
## 所有具体战斗单位走此类(M1 Phase 1: melee / ranged 两种, 按数值表区分)。
##
## P1.1 重命名自 RtsCharacterActor; class_name 改 RtsUnitActor 与城堡战争语境对齐
## (Unit / Building 二元结构, 不再叫 Character)。
##
## 决策来源: architecture-baseline.md §4 (RtsBattleActor 子类家族)
class_name RtsUnitActor
extends RtsBattleActor


# ========== Stance ==========

## P2.4 — 攻击姿态枚举:
##   - HOLD_FIRE: 不主动选目标, AutoTargetSystem 不写 _cached_target_id (玩家手动指挥才打)
##   - DEFENSIVE: 仅在 1.5 × attack_range 内有敌时选目标 (被动接战)
##   - AGGRESSIVE: 默认; 任何敌人都进入候选 (按 priority + 距离评分)
enum Stance {
	HOLD_FIRE,
	DEFENSIVE,
	AGGRESSIVE,
}

const DEFENSIVE_ENGAGE_RANGE_FACTOR: float = 1.5


# ========== 字段 ==========

## 兵种 enum (RtsUnitClassConfig.UnitClass)
var unit_class: RtsUnitClassConfig.UnitClass

## 强类型 attribute_set: 公共 hp/max_hp 视图也通过此字段暴露。
## 公共代码读 hp 走 get_attribute_set() 接口; 专属代码读 atk/def/move_speed 直接用此字段。
var attribute_set: RtsUnitAttributeSet

## P2.4 — 攻击姿态; 默认 AGGRESSIVE, smoke / 玩家命令可调。
##
## 注: 仅 RtsUnitActor 有 stance; RtsBuildingActor 始终按 target_layer_mask 主动接战, 没有
## "HOLD_FIRE / DEFENSIVE" 的语义。
var stance: int = Stance.AGGRESSIVE

# 注: P2.8 起 current_target_id / unit_tags / target_priorities / _cached_target_id / target_layer_mask
# 已上推到 RtsBattleActor 基类 (单位 + 建筑共用), 此处不再重复声明。
# Cooldown tag (ATTACK_COOLDOWN_TAG) 也在基类 — 单位/建筑共用 add_auto_duration_tag 计冷却。


# ========== 初始化 ==========

func _init(p_unit_class: RtsUnitClassConfig.UnitClass) -> void:
	unit_class = p_unit_class
	type = "Character"

	var stats := RtsUnitClassConfig.get_stats(p_unit_class)
	_display_name = stats.name

	# actor_id 留默认空串; _on_id_assigned 在 add_actor 后 sync 真 ID。
	attribute_set = RtsUnitAttributeSet.new()
	# max_hp 必须先于 hp: cross-attr clamp(hp <= max_hp) 在 set_hp_base 时按当前 max_hp 截。
	attribute_set.set_max_hp_base(stats.max_hp)
	attribute_set.set_hp_base(stats.hp)
	attribute_set.set_atk_base(stats.atk)
	attribute_set.set_def_base(stats.def)
	attribute_set.set_move_speed_base(stats.move_speed)
	attribute_set.set_attack_speed_base(stats.attack_speed)
	attribute_set.set_attack_range_base(stats.attack_range)

	# 兵种 collision_radius (P1.2 push-out 必需, 与 attack_range 联动)
	collision_radius = stats.collision_radius

	# P2.4: 拷贝 unit_tags / target_priorities (每个 actor 独立副本, 调方可 override)
	unit_tags = stats.unit_tags.duplicate()
	target_priorities = stats.target_priorities.duplicate(true)

	# P2.8: layer + 武器命中 mask (默认 GROUND 层 + 能打 GROUND; flying 单位 stats 会覆盖到 AIR / MASK_GROUND)
	movement_layer = stats.default_movement_layer
	target_layer_mask = stats.target_layer_mask

	ability_set = AbilitySet.new(get_id(), attribute_set)


# ========== RtsBattleActor 合同实现 ==========

func get_attribute_set() -> BaseGeneratedAttributeSet:
	return attribute_set


# ========== P2.8 攻击协议 override (从 attribute_set 拿数值) ==========

func get_atk() -> float:
	return attribute_set.atk if attribute_set != null else 0.0


func get_def() -> float:
	return attribute_set.def if attribute_set != null else 0.0


func get_attack_range() -> float:
	return attribute_set.attack_range if attribute_set != null else 0.0


func get_attack_speed() -> float:
	return attribute_set.attack_speed if attribute_set != null else 0.0


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
