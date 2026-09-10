## Dota2BattleActor - dota2-auto-battle 战斗 Actor 基类
##
## 死亡锁存 / owner id 同步 / 录像默认订阅由 BattleActor 提供; 这里只加 dota2 专属的
## 连续坐标与碰撞半径。
##
## README.md（Actor 与属性 节）：基类**不**持具体 attribute_set 字段；子类各持强类型字段，
## 经 get_attribute_set() 暴露 hp/max_hp 公共视图。这样专属代码（攻击读 attack_damage）
## 仍可走 unit.attribute_set.attack_damage 而不被基类 shadow。
##
## 基类返回 Dota2BattleActorAttributeSet（非 Unit）是为了不阻塞将来的
## Dota2TowerActor / Dota2BuildingActor —— 它们也 take damage、共享 hp/max_hp 视图。
## 与 hex HexBattleActor 同构。
class_name Dota2BattleActor
extends BattleActor


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

## 可选 debug 镜像：当前攻击目标 id。**非**权威 —— 权威在 controller 的
## AttackTargetIntent.payload.target_id；此字段仅供 snapshot / debug 面板，
## 由 procedure 每 tick 从 current_intent 同步，execution/decision 不读它。
var debug_current_target_id: String = ""


# ========== 公共合同（子类必须实现）==========

## attribute_set 基类视图。子类返回自己的强类型字段。
## 公共战斗代码（damage action / 快照）经此读 hp / max_hp。
func get_attribute_set() -> Dota2BattleActorAttributeSet:
	push_error("Dota2BattleActor.get_attribute_set must be overridden by subclass: %s" % [type])
	return null


func get_ability_set() -> AbilitySet:
	return ability_set


# ========== 录像 / 快照 ==========

## 连续坐标 (x, y) 提升为 Vector3 (x, y, 0)，渲染层按 positionFormats 解释。
func _get_position() -> Vector3:
	return Vector3(position_2d.x, position_2d.y, 0.0)

