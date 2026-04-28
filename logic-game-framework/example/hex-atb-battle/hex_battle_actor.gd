## HexBattleActor - 六边形战斗 Actor 基类
##
## 任何能占格、能受伤、能死亡的 hex 战斗实体的公共基类。
## 子类:
##   - CharacterActor (角色: ATB / AI / 职业技能)
##   - EnvironmentActor (环境: 石墙 / 木桶 / 巨石 ...)
##
## 公共合同:
##   - hex_position: 占格坐标
##   - ability_set: 用于挂 ability/buff/passive (战斗管线平权)
##   - get_attribute_set(): 子类返回自己的强类型 attribute_set; 公共代码读 hp / max_hp
##   - is_dead / check_death: 死亡检测
##
## 设计决策:
##   - 不持 attribute_set 字段, 由子类各自持强类型字段, 经 get_attribute_set() 暴露公共合同。
##     这避免 GDScript 子类重声明同名 var 的 shadow 陷阱, 让专属代码 (Strike 读 atk)
##     仍可用 actor.attribute_set.atk, 公共代码 (DamageUtils 读 hp) 走 actor.get_attribute_set().hp。
class_name HexBattleActor
extends Actor


# ========== 公共字段 ==========

## AbilitySet — 战斗管线平权: 环境物也可挂 PreEvent / PostEvent / buff
var ability_set: BattleAbilitySet

## 当前格子坐标 (HexCoord.invalid() 表示未放置)
var hex_position: HexCoord = HexCoord.invalid()

## 死亡标志 (走数据驱动: hp <= 0 时 check_death 设置)
var _is_dead: bool = false


# ========== 公共合同 (子类必须实现) ==========

## 获取 attribute_set 的基类视图。子类返回自己的强类型字段。
## 公共代码 (DamageUtils / game_state_utils 等) 通过此接口读 hp / max_hp。
func get_attribute_set() -> HexBattleActorAttributeSet:
	push_error("HexBattleActor.get_attribute_set must be overridden by subclass: %s" % [type])
	return null


# ========== 生命周期 ==========

## 检查是否死亡; 返回是否首次进入死亡态。
func check_death() -> bool:
	var attrs := get_attribute_set()
	if attrs == null:
		return false
	if attrs.hp <= 0 and not _is_dead:
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
	if attrs == null:
		return {}
	return {
		"hp": attrs.hp,
		"max_hp": attrs.max_hp,
	}


## 默认 ability snapshot
func get_ability_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if ability_set == null:
		return result
	for ability in ability_set.get_abilities():
		result.append({
			"instance_id": ability.id,
			"config_id": ability.config_id,
		})
	return result


## 默认 tag snapshot
func get_tag_snapshot() -> Dictionary:
	if ability_set == null:
		return {}
	return ability_set.get_all_tags()


## 默认录像回调 (子类可追加自定义订阅)
func setup_recording(ctx: RecordingContext) -> Array[Callable]:
	var unsubscribes: Array[Callable] = []
	var attrs := get_attribute_set()
	if attrs != null:
		unsubscribes.append_array(RecordingUtils.record_attribute_changes(attrs, ctx))
	if ability_set != null:
		unsubscribes.append_array(RecordingUtils.record_ability_set_changes(ability_set, ctx))
	unsubscribes.append_array(RecordingUtils.record_actor_lifecycle(self, ctx))
	return unsubscribes
