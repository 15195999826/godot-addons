## ShieldComponent - 护盾本体
##
## 挂在带 ShieldComponentConfig 的 Ability 上，承载单个护盾实例的可变状态。
##
## 职责：
##   1. 持有护盾运行时状态（current / capacity / 类型过滤 / 优先级）。
##   2. consume(amount, damage_type) 提交容量变更，返回 (absorbed, broken)。
##   3. on_remove 钩子：仅当 ability 因 duration 到期退出（且未在伤害中破裂）时调 on_expire。
##
## 不职责：
##   - 不注册 PreEventConfig（护盾不参与 SET/ADD/MULTIPLY 数值修正）。
##   - 不 push 事件、不扣 hp。这些副作用由 ShieldResolver 调用方（apply_damage）触发。
##   - 不决定叠加策略。叠加由 ApplyShieldAction 在授予前处理（V1 强制 independent）。
class_name HexBattleShieldComponent
extends AbilityComponent


const TYPE := "ShieldComponent"
const EXPIRE_REASON_BROKEN := "shield_broken"


# ========== 配置（构造时拷贝，不可变） ==========

var capacity: float = 0.0
var damage_types: Array[String] = ["all"]
var priority: int = 0
var stacking_policy: String = "independent"
var on_break: Callable = Callable()
var on_expire: Callable = Callable()


# ========== 运行时状态 ==========

## 剩余容量
var current: float = 0.0

## 是否已通过伤害打破（防止 on_remove 在已 break 的情况下重复调 on_expire）
var _already_broken: bool = false


func _init(config: HexBattleShieldComponentConfig) -> void:
	type = TYPE
	capacity = config.capacity
	damage_types = config.damage_types.duplicate()
	priority = config.priority
	stacking_policy = config.stacking_policy
	on_break = config.on_break
	on_expire = config.on_expire
	current = capacity


## 该护盾能否吸收指定类型伤害
func can_absorb(damage_type: String) -> bool:
	if damage_types.is_empty():
		return true
	if damage_types.has("all"):
		return true
	return damage_types.has(damage_type)


## 提交一次消耗。返回 { "absorbed": float, "broken": bool }。
##
## 调用方应先用 can_absorb 过滤；这里再次校验仅作防御。
func consume(amount: float, damage_type: String) -> Dictionary:
	if amount <= 0.0 or current <= 0.0:
		return { "absorbed": 0.0, "broken": false }
	if not can_absorb(damage_type):
		return { "absorbed": 0.0, "broken": false }
	var absorbed := minf(current, amount)
	current -= absorbed
	var broken := current <= 0.0
	if broken:
		_already_broken = true
	return { "absorbed": absorbed, "broken": broken }


## 是否已被打破（current = 0 且由消耗导致）
func is_already_broken() -> bool:
	return _already_broken


## 生成消耗记录的快照（resolver 用，apply_damage 把 absorbed/broken/damage_type 补上后入 event）
func get_state_snapshot() -> Dictionary:
	var ability := get_ability()
	return {
		"shield_ability_id": ability.id if ability != null else "",
		"shield_config_id": ability.config_id if ability != null else "",
		"owner_actor_id": ability.owner_actor_id if ability != null else "",
		"source_actor_id": ability.source_actor_id if ability != null else "",
		"capacity": capacity,
		"remaining": current,
		"priority": priority,
	}


func on_remove(context: AbilityLifecycleContext) -> void:
	if _already_broken:
		return
	if not on_expire.is_valid():
		return
	var ability := get_ability()
	if ability == null:
		return
	if ability.get_expire_reason() != TimeDurationComponent.EXPIRE_REASON_TIME_DURATION:
		return
	var record := get_state_snapshot()
	on_expire.call(record, context)


func serialize() -> Dictionary:
	return {
		"current": current,
		"capacity": capacity,
		"damageTypes": damage_types,
		"priority": priority,
		"stackingPolicy": stacking_policy,
	}
