## Dota2BattleActor - dota2-auto-battle 战斗 Actor 基类
##
## README.md（Actor 与属性 节）：基类**不**持具体 attribute_set 字段；子类各持强类型字段，
## 经 get_attribute_set() 暴露 hp/max_hp 公共视图。这样专属代码（攻击读 attack_damage）
## 仍可走 unit.attribute_set.attack_damage 而不被基类 shadow。
##
## 基类返回 Dota2BattleActorAttributeSet（非 Unit）是为了不阻塞将来的
## Dota2TowerActor / Dota2BuildingActor —— 它们也 take damage、共享 hp/max_hp 视图。
## 与 hex HexBattleActor 同构。
class_name Dota2BattleActor
extends Actor


# ========== 公共字段 ==========

## AbilitySet —— 基础攻击 / 未来 buff / passive 都挂这里（战斗管线平权）。
## 子类负责实例化（unit 用 actor id + Dota2UnitAttributeSet）。
var ability_set: AbilitySet = null

## 连续逻辑坐标（像素）；战斗判定的"事实"，由 movement adapter 写回。
var position_2d: Vector2 = Vector2.ZERO

## 当前帧速度（像素/秒）；adapter 写，仅信息性（debug / facing）。
var velocity: Vector2 = Vector2.ZERO

## 圆形碰撞半径（像素）；交给 sim-nav 适配器作 unit clearance（硬阻挡）。
var collision_radius: float = 12.0

## 队伍 ID（0=left, 1=right; -1=未分配）。
var team_id: int = -1

## 可选 debug 镜像：当前攻击目标 id。**非**权威 —— 权威在 controller 的
## AttackTargetIntent.payload.target_id；此字段仅供 snapshot / debug 面板，
## 由 procedure 每 tick 从 current_intent 同步，execution/decision 不读它。
var debug_current_target_id: String = ""

## 死亡标志（数据驱动：hp <= 0 时 check_death 设置）。
var _is_dead: bool = false


# ========== 公共合同（子类必须实现）==========

## attribute_set 基类视图。子类返回自己的强类型字段。
## 公共战斗代码（damage action / 快照）经此读 hp / max_hp。
func get_attribute_set() -> Dota2BattleActorAttributeSet:
	push_error("Dota2BattleActor.get_attribute_set must be overridden by subclass: %s" % [type])
	return null


# ========== 生命周期 ==========

## ID 被 add_actor 分配后，同步 ability_set / attribute_set 内引用的 owner id。
func _on_id_assigned() -> void:
	if ability_set != null:
		ability_set.owner_actor_id = get_id()
	var attrs := get_attribute_set()
	if attrs != null:
		attrs.actor_id = get_id()


## 数据驱动死亡判定；返回是否首次进入死亡态。
func check_death() -> bool:
	var attrs := get_attribute_set()
	if attrs == null:
		return false
	if attrs.hp <= 0.0 and not _is_dead:
		_is_dead = true
		return true
	return false


func is_dead() -> bool:
	return _is_dead


## 显式标记死亡（damage action 在伤害结算后调）。
func mark_dead() -> void:
	_is_dead = true


## 死亡 actor 不再响应 PreEvent handler（与 hex 一致）。
func is_pre_event_responsive() -> bool:
	return not _is_dead


# ========== AbilitySet 协议 ==========

## EventProcessor / 探测方走 has_method("get_ability_set")；显式提供。
func get_ability_set() -> AbilitySet:
	return ability_set


# ========== 队伍 ==========

func set_team_id(p_team_id: int) -> void:
	team_id = p_team_id
	set_team(str(p_team_id))


func get_team_id() -> int:
	return team_id


# ========== 录像 / 快照 ==========

## 连续坐标 (x, y) 提升为 Vector3 (x, y, 0)，渲染层按 positionFormats 解释。
func _get_position() -> Vector3:
	return Vector3(position_2d.x, position_2d.y, 0.0)


func _get_team_int() -> int:
	return team_id
