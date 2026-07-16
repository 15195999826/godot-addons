class_name AbilityActivationQuery
## Ability 激活门查询结果的键常量与构造器。
##
## `AbilitySet.can_activate` / `Ability.can_activate` / `ActiveUseComponent.can_activate`
## 三级查询共用这一份结果形状，下游（UI / AI / tooltip 的合法性 Query）按同一组
## 键消费，避免各游戏自造 {allowed, reason} 变体后彼此漂移。
##
## 结果是进程内 Dictionary（非序列化边界），键用 snake_case；
## failed_component_type 与 GameEvent.AbilityActivateFailed 同词汇
## （"condition" / "cost"），查询与真实激活路径对同一种失败给同一种归因。

const KEY_ALLOWED := "allowed"
const KEY_REASON := "reason"
const KEY_FAILED_COMPONENT_TYPE := "failed_component_type"

## failed_component_type 取值：Ability 级短路（未 granted / disabled）
const FAILED_ABILITY := "ability"
## failed_component_type 取值：timeline 未注册（激活路径会 error 拒绝，查询同判）
const FAILED_TIMELINE := "timeline"
## failed_component_type 取值：Condition.check 未通过
const FAILED_CONDITION := "condition"
## failed_component_type 取值：Cost.can_pay 未通过
const FAILED_COST := "cost"


static func allowed() -> Dictionary:
	return {
		KEY_ALLOWED: true,
		KEY_REASON: "",
		KEY_FAILED_COMPONENT_TYPE: "",
	}


static func denied(reason: String, failed_component_type: String) -> Dictionary:
	return {
		KEY_ALLOWED: false,
		KEY_REASON: reason,
		KEY_FAILED_COMPONENT_TYPE: failed_component_type,
	}


static func is_allowed(result: Dictionary) -> bool:
	return result.get(KEY_ALLOWED, false) as bool
