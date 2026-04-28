## EnvironmentActor - 环境物 Actor
##
## HexBattleActor 的子类, 表示地图上的非角色实体 (墙 / 木桶 / 巨石 / 草丛 ...)。
##
## 隔离边界:
##   - AI / 默认 enemy selector / heal / buff / shield 默认不作用于环境物 (character-only)
##   - 战斗管线 (DamageEvent / DeathEvent / PreEvent / PostEvent) 对环境物平权
##
## 不同形态由 environment_kind 字符串区分 (用于 replay 视觉) + CollisionProfile 数据驱动。
## indestructible 用 hp = INF 数据表达, 不在代码里加早退分支。
class_name EnvironmentActor
extends HexBattleActor


# ========== 字段 ==========

## 环境物种类标识符 (供 replay / frontend 区分视觉, 如 "stone_wall" / "barrel" / "boulder")
var environment_kind: String = ""

## 强类型 attribute_set: 当前只继承公共 hp / max_hp; 未来可扩展 mass / hardness 等专属属性。
var attribute_set: HexBattleEnvironmentAttributeSet

## 碰撞物理参数 (普通字段, 不进 attribute_set)
var collision_profile: CollisionProfile


# ========== 初始化 ==========

func _init(p_environment_kind: String, p_collision_profile: CollisionProfile) -> void:
	environment_kind = p_environment_kind
	type = "Environment"
	_display_name = p_environment_kind

	attribute_set = HexBattleEnvironmentAttributeSet.new(get_id())
	collision_profile = p_collision_profile if p_collision_profile != null else CollisionProfile.new()
	ability_set = BattleAbilitySet.create_battle_ability_set(get_id(), attribute_set)


## ID 被 add_actor 分配后, 同步 ability_set 和 attribute_set 的 owner 引用
func _on_id_assigned() -> void:
	if ability_set != null:
		ability_set.owner_actor_id = get_id()
	if attribute_set != null:
		attribute_set.actor_id = get_id()


# ========== HexBattleActor 合同实现 ==========

func get_attribute_set() -> HexBattleActorAttributeSet:
	return attribute_set


# ========== 录像支持 (覆盖基类) ==========

## 配置 ID 用环境物种类, 让 replay 区分 stone_wall / barrel 等视觉。
func _get_config_id() -> String:
	return environment_kind


# ========== 序列化 ==========

func serialize() -> Dictionary:
	var base := serialize_base()
	base["environment_kind"] = environment_kind
	base["hex_position"] = hex_position.to_dict() if hex_position.is_valid() else {}
	base["attribute_set"] = attribute_set._raw.serialize()
	return base
