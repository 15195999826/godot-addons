## HexBattleActor - 六边形战斗 Actor 基类 (CharacterActor / EnvironmentActor 共用)。
##
## 死亡锁存 / owner id 同步 / 录像默认订阅由 BattleActor 提供; 这里只加 hex 专属的
## 格子坐标与碰撞数据。
##
## 不持 attribute_set 字段: 子类各自持强类型字段, 经 get_attribute_set() 暴露 hp/max_hp 视图。
## 这样专属代码 (Strike 读 atk) 仍可用 actor.attribute_set.atk 而不被 base shadow。
class_name HexBattleActor
extends BattleActor


# ========== actor kind 常量 ==========
#
# actor.type 的取值域(也是 ALLOWED_TARGET_KINDS metadata / 录像 positionFormats key
# 的取值域)。消费端类型比较 / 默认值一律用这里, 不手写字面量。
# 注: tests 侧保留字面量是有意的 —— 测试以协议黑盒视角验证录像 dict / metadata。

const KIND_CHARACTER := "Character"
const KIND_ENVIRONMENT := "Environment"


# ========== 公共字段 ==========

## AbilitySet — 战斗管线平权: 环境物也可挂 PreEvent / PostEvent / buff
var ability_set: BattleAbilitySet

## 当前格子坐标 (HexCoord.invalid() 表示未放置)
var hex_position: HexCoord = HexCoord.invalid()

## 碰撞 / 被推时的结算数据 — 子类 _init 末尾负责填默认值。
## CharacterActor 默认走 CollisionProfile.default_character();
## EnvironmentActor 通过构造参数传入特定 profile (stone_wall / barrel ...)
var collision_profile: CollisionProfile


# ========== 公共合同 (子类必须实现) ==========

## 获取 attribute_set 的基类视图。子类返回自己的强类型字段。
## 公共代码 (DamageUtils / game_state_utils 等) 通过此接口读 hp / max_hp。
func get_attribute_set() -> HexBattleActorAttributeSet:
	push_error("HexBattleActor.get_attribute_set must be overridden by subclass: %s" % [type])
	return null


func get_ability_set() -> BattleAbilitySet:
	return ability_set


# ========== 事件响应 ==========

## 死者只对两类 post 事件保持响应：自己的 death（亡语在死后触发）与自己作为 target 的 damage
## （致死一击的荆棘照样反伤）。其余 post 事件与全部 pre 事件照 BattleActor 默认，死后不响应。
func is_event_responsive(event_dict: Dictionary, phase: String) -> bool:
	if not is_dead():
		return true
	if phase != EventPhase.PHASE_POST:
		return false
	var kind := str(event_dict.get("kind", ""))
	if kind == BattleEvents.DEATH_EVENT:
		return str(event_dict.get("actor_id", "")) == get_id()
	if kind == BattleEvents.DAMAGE_EVENT:
		return str(event_dict.get("target_actor_id", "")) == get_id()
	return false


# ========== 录像支持 ==========

## 位置覆盖: 用 hex 坐标作为 Vector3 (q, r, 0); 渲染层按 configs.positionFormats 解释。
func _get_position() -> Vector3:
	if not hex_position.is_valid():
		return Vector3.ZERO
	return Vector3(hex_position.q, hex_position.r, 0)


## hex 录像只需要 hp / max_hp 两条 (子类可扩展); 不走 BattleActor 的全属性快照。
func get_attribute_snapshot() -> Dictionary:
	var attrs := get_attribute_set()
	return {
		"hp": attrs.hp,
		"max_hp": attrs.max_hp,
	}


# ========== 序列化 ==========

## 在 BattleActor 公共字段之上补 hex 位置; 子类 super.serialize() 后追加专属字段。
func serialize() -> Dictionary:
	var base := super.serialize()
	base["hex_position"] = hex_position.to_dict() if hex_position.is_valid() else {}
	return base
