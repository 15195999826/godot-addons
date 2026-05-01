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

## 当前目标的 actor id; 空表示没目标(初始 / 目标已死)。
## P1.5 后由 RtsUnitController 维护; 此字段保留作为单位状态的统一入口。
var current_target_id: String = ""

## P2.4 — 单位归类 tag (供敌方 target_priorities 匹配)。从 unit_class config 拷过来,
## 调方可在 spawn 后 override (如 boss 加 ["elite"] tag)。
var unit_tags: Array[String] = []

## P2.4 — 目标优先级表 [{tag: String, weight: float}, ...]; AutoTargetSystem 用此评分。
## 默认从 unit_class config 拷; smoke / 玩家命令可 override。
var target_priorities: Array[Dictionary] = []

## P2.4 — 攻击姿态; 默认 AGGRESSIVE, smoke / 玩家命令可调。
var stance: int = Stance.AGGRESSIVE

## P2.4 — AutoTargetSystem 写入的目标缓存 actor id (空=暂无目标)。
## 每 RESCAN_INTERVAL_TICKS (20) tick 全量重算; 目标死亡当 tick 立即重算 (不等下个 scan)。
##
## RtsBasicAttackStrategy.decide 读此字段决定 AttackActivity 的 target_id。
## 不要把 controller / activity 的 actor.current_target_id 与此混淆: current_target_id 是
## "当前正在打的 target", _cached_target_id 是 "AutoTargetSystem 推荐的下一 target"。
var _cached_target_id: String = ""

## P1.6 (修 M4) 后, cooldown 走 ability_set.tag_container.add_auto_duration_tag, 不再用
## 裸 float 字段。查询走 is_attack_on_cooldown() / can_attack(), 启动走 start_attack_cooldown()。
## 时长在 ms 单位(与 LGF tag_container 内部 logic_time 对齐, hex 同 unit)。
const ATTACK_COOLDOWN_TAG: String = "rts_attack_cooldown"


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

	# 兵种 collision_radius (P1.2 push-out 必需, 与 attack_range 联动)
	collision_radius = stats.collision_radius

	# P2.4: 拷贝 unit_tags / target_priorities (每个 actor 独立副本, 调方可 override)
	unit_tags = stats.unit_tags.duplicate()
	target_priorities = stats.target_priorities.duplicate(true)

	ability_set = AbilitySet.new(get_id(), attribute_set)


# ========== RtsBattleActor 合同实现 ==========

func get_attribute_set() -> BaseGeneratedAttributeSet:
	return attribute_set


# ========== Cooldown 控制 (P1.6 走 LGF tag-duration) ==========

## 是否冷却中(查 ability_set.tag_container 上的 attack_cooldown tag)。
func is_attack_on_cooldown() -> bool:
	if ability_set == null:
		return false
	return ability_set.has_tag(ATTACK_COOLDOWN_TAG)


## 是否冷却完毕、可发起 basic attack。
func can_attack() -> bool:
	return not is_attack_on_cooldown() and not is_dead()


## 启动 attack cooldown — 走 LGF tag-duration 机制。
##
## duration 用 ms (与 LGF logic_time 同 unit, 见 BattleProcedure.get_logic_time);
## attack_speed 是次/秒, 所以 cooldown_ms = 1000.0 / attack_speed。
func start_attack_cooldown() -> void:
	if ability_set == null:
		return
	var atk_speed: float = attribute_set.attack_speed
	var duration_ms: float = 1000.0 / atk_speed if atk_speed > 0.0 else 99999000.0
	ability_set.add_auto_duration_tag(ATTACK_COOLDOWN_TAG, duration_ms)


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
