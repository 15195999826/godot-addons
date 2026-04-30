## HexBattleActor - 六边形战斗 Actor 基类 (CharacterActor / EnvironmentActor 共用)。
##
## 不持 attribute_set 字段: 子类各自持强类型字段, 经 get_attribute_set() 暴露 hp/max_hp 视图。
## 这样专属代码 (Strike 读 atk) 仍可用 actor.attribute_set.atk 而不被 base shadow。
class_name HexBattleActor
extends Actor


# ========== 公共字段 ==========

## AbilitySet — 战斗管线平权: 环境物也可挂 PreEvent / PostEvent / buff
var ability_set: BattleAbilitySet

## 当前格子坐标 (HexCoord.invalid() 表示未放置)
var hex_position: HexCoord = HexCoord.invalid()

## 碰撞 / 被推时的结算数据 — 子类 _init 末尾负责填默认值。
## CharacterActor 默认走 CollisionProfile.default_character();
## EnvironmentActor 通过构造参数传入特定 profile (stone_wall / barrel ...)
var collision_profile: CollisionProfile

## 死亡标志 (走数据驱动: hp <= 0 时 check_death 设置)
var _is_dead: bool = false


# ========== 公共合同 (子类必须实现) ==========

## 获取 attribute_set 的基类视图。子类返回自己的强类型字段。
## 公共代码 (DamageUtils / game_state_utils 等) 通过此接口读 hp / max_hp。
func get_attribute_set() -> HexBattleActorAttributeSet:
	push_error("HexBattleActor.get_attribute_set must be overridden by subclass: %s" % [type])
	return null


# ========== 生命周期 ==========

## ID 被 add_actor 分配后, 同步 ability_set / attribute_set 内引用的 owner_id。
func _on_id_assigned() -> void:
	ability_set.owner_actor_id = get_id()
	get_attribute_set().actor_id = get_id()


## 检查是否死亡; 返回是否首次进入死亡态。
func check_death() -> bool:
	if get_attribute_set().hp <= 0 and not _is_dead:
		_is_dead = true
		return true
	return false


func is_dead() -> bool:
	return _is_dead


## 死亡的 actor 不再响应 PreEvent handler (反伤 / 护盾等被动死后失效)。
func is_pre_event_responsive() -> bool:
	return not _is_dead


# ========== AbilitySet 协议 ==========

## 实现 IAbilitySetOwner 协议 (与 ability_set 字段同步, 子类不必重写)
func get_ability_set() -> BattleAbilitySet:
	return ability_set


# ========== 录像支持 ==========

## 位置覆盖: 用 hex 坐标作为 Vector3 (q, r, 0); 渲染层按 configs.positionFormats 解释。
func _get_position() -> Vector3:
	if not hex_position.is_valid():
		return Vector3.ZERO
	return Vector3(hex_position.q, hex_position.r, 0)


## 默认 attribute snapshot: 公共属性 (子类可扩展)
func get_attribute_snapshot() -> Dictionary:
	var attrs := get_attribute_set()
	return {
		"hp": attrs.hp,
		"max_hp": attrs.max_hp,
	}


## 默认 ability snapshot
func get_ability_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ability in ability_set.get_abilities():
		result.append({
			"instance_id": ability.id,
			"config_id": ability.config_id,
		})
	return result


## 默认 tag snapshot
func get_tag_snapshot() -> Dictionary:
	return ability_set.get_all_tags()


## 默认录像回调 (子类可追加自定义订阅)
func setup_recording(ctx: RecordingContext) -> Array[Callable]:
	var unsubscribes: Array[Callable] = []
	unsubscribes.append_array(RecordingUtils.record_attribute_changes(get_attribute_set(), ctx))
	unsubscribes.append_array(RecordingUtils.record_ability_set_changes(ability_set, ctx))
	unsubscribes.append_array(RecordingUtils.record_actor_lifecycle(self, ctx))
	return unsubscribes


# ========== 序列化 ==========

## 公共序列化字段 (id / type / hex_position / attribute_set raw); 子类 super.serialize() 后追加专属字段。
func serialize() -> Dictionary:
	var base := serialize_base()
	base["hex_position"] = hex_position.to_dict() if hex_position.is_valid() else {}
	base["attribute_set"] = get_attribute_set()._raw.serialize()
	return base
