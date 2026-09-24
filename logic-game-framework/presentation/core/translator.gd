## Translator - 翻译员抽象基类
##
## 翻译员把逻辑层的一条事件（dict）翻成表演层的卡片（VisualAction）。
## 每个翻译员处理特定种类的事件；事件方言（kind 名 / 字段）由项目定，框架不认识任何一种。
##
## 设计原则：
## - 纯函数，无副作用
## - 只读 VisualStateQuery，不修改账本
## - 返回声明式的 VisualAction 数组（位置一律逻辑平面 Vector2）
class_name Translator
extends RefCounted

# ========== 属性 ==========

## 翻译员名称（用于调试 / 覆盖分析）
var translator_name: String = "Translator"


# ========== 抽象方法 ==========

## 检查是否能处理该事件
## 子类必须覆盖此方法
func can_handle(_event: Dictionary) -> bool:
	push_error("[%s] can_handle() not implemented" % translator_name)
	return false


## 将事件翻译为卡片
## 子类必须覆盖此方法
func translate(_event: Dictionary, _query: VisualStateQuery) -> Array[VisualAction]:
	push_error("[%s] translate() not implemented" % translator_name)
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
