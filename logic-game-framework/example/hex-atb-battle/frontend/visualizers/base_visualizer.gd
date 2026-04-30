## BaseVisualizer - Visualizer 抽象基类
##
## Visualizer 负责将逻辑层的 GameEvent 翻译为表现层的 VisualAction。
## 每个 Visualizer 处理特定类型的事件。
##
## 设计原则：
## - 纯函数，无副作用
## - 只读取 context，不修改状态
## - 返回声明式的 VisualAction 数组
class_name FrontendBaseVisualizer
extends RefCounted

# ========== 属性 ==========

## Visualizer 名称（用于调试）
var visualizer_name: String = "BaseVisualizer"


# ========== 抽象方法 ==========

## 检查是否能处理该事件
## 子类必须覆盖此方法
func can_handle(event: Dictionary) -> bool:
	push_error("[%s] can_handle() not implemented" % visualizer_name)
	return false


## 将事件翻译为视觉动作
## 子类必须覆盖此方法
func translate(_event: Dictionary, _context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	push_error("[%s] translate() not implemented" % visualizer_name)
	return []


# ========== 辅助方法 ==========

## 获取事件类型
static func get_event_kind(event: Dictionary) -> String:
	return event.get("kind", "") as String


## 安全获取字符串字段
static func get_string_field(event: Dictionary, field: String, default_value: String = "") -> String:
	return event.get(field, default_value) as String


## 安全获取浮点数字段
static func get_float_field(event: Dictionary, field: String, default_value: float = 0.0) -> float:
	return event.get(field, default_value) as float


## 安全获取布尔字段
static func get_bool_field(event: Dictionary, field: String, default_value: bool = false) -> bool:
	return event.get(field, default_value) as bool


## 安全获取六边形坐标字段 -> HexCoord
## 从事件的 Dictionary {"q": int, "r": int} 格式解析
static func get_hex_field(event: Dictionary, field: String) -> HexCoord:
	var hex_dict: Dictionary = event.get(field, {})
	if hex_dict.is_empty():
		push_warning("[BaseVisualizer] Missing hex field: %s" % field)
	return HexCoord.from_dict(hex_dict)
