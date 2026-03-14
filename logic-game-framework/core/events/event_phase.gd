class_name EventPhase
## 纯静态工具类：事件阶段常量和工厂函数

const PHASE_PRE := "pre"
const PHASE_POST := "post"

# 保留字符串常量用于兼容（Trace 等仍使用字符串）
const INTENT_PASS := "pass"
const INTENT_CANCEL := "cancel"
const INTENT_MODIFY := "modify"


# ========== Intent 工厂方法（推荐使用） ==========


## 创建 PASS 意图（不做处理）
static func pass_intent() -> Intent:
	return Intent.pass_through()


## 创建 CANCEL 意图（取消事件）
static func cancel_intent(handler_id: String, reason: String) -> Intent:
	return Intent.cancel(handler_id, reason)


## 创建 MODIFY 意图（修改事件）
## @param handler_id: 处理器 ID
## @param modifications: Modification 数组
static func modify_intent(handler_id: String, modifications: Array[Modification]) -> Intent:
	return Intent.modify(handler_id, modifications)


# ========== 工具方法 ==========


static func create_trace_id() -> String:
	return "t-%s-%s" % [String.num_int64(Time.get_ticks_msec(), 36), _random_suffix()]


static func _random_suffix() -> String:
	var value := randi()
	return String.num_int64(value, 36).right(4)
