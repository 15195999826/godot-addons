## Intent - 事件处理意图
##
## 表示 Pre 阶段处理器对事件的处理意图。
## 处理器通过返回 Intent 来表达：通过、取消、或修改事件。
##
## ========== 意图类型 ==========
##
## - PASS: 不做任何处理，让事件继续
## - CANCEL: 取消事件，阻止其生效
## - MODIFY: 修改事件的数值字段
##
## ========== 使用示例 ==========
##
## @example 在处理器中返回意图
## ```gdscript
## func _handle_pre_damage(mutable: MutableEvent, ctx: HandlerContext) -> Intent:
##     # 免疫：取消事件
##     if _is_immune(ctx):
##         return Intent.cancel(ctx.ability_id, "immune")
##
##     # 减伤：修改伤害值
##     if _has_armor(ctx):
##         return Intent.modify(ctx.ability_id, [
##             Modification.multiply("damage", 0.7),
##         ])
##
##     # 不处理
##     return Intent.pass_through()
## ```
class_name Intent
extends RefCounted


## 意图类型枚举
enum Type {
	PASS,    ## 通过，不做处理
	CANCEL,  ## 取消事件
	MODIFY,  ## 修改事件
}


## 意图类型
var type: Type

## 处理器 ID（用于追踪）
var handler_id: String

## 取消原因（仅 CANCEL 类型使用）
var reason: String

## 修改列表（仅 MODIFY 类型使用）
var modifications: Array[Modification]


func _init(
	p_type: Type,
	p_handler_id: String = "",
	p_reason: String = "",
	p_modifications: Array[Modification] = []
) -> void:
	type = p_type
	handler_id = p_handler_id
	reason = p_reason
	modifications = p_modifications


# ========== 静态工厂方法 ==========


## 创建 PASS 意图（不做处理）
static func pass_through() -> Intent:
	return Intent.new(Type.PASS)


## 创建 CANCEL 意图（取消事件）
static func cancel(p_handler_id: String, p_reason: String) -> Intent:
	return Intent.new(Type.CANCEL, p_handler_id, p_reason)


## 创建 MODIFY 意图（修改事件）
static func modify(p_handler_id: String, p_modifications: Array[Modification]) -> Intent:
	return Intent.new(Type.MODIFY, p_handler_id, "", p_modifications)


# ========== 类型检查 ==========


## 是否为 PASS 意图
func is_pass() -> bool:
	return type == Type.PASS


## 是否为 CANCEL 意图
func is_cancel() -> bool:
	return type == Type.CANCEL


## 是否为 MODIFY 意图
func is_modify() -> bool:
	return type == Type.MODIFY


# ========== 序列化 ==========


## 转换为 Dictionary（用于日志/调试）
func to_dict() -> Dictionary:
	var d := {
		"type": _type_to_string(type),
	}
	if handler_id != "":
		d["handlerId"] = handler_id
	if type == Type.CANCEL and reason != "":
		d["reason"] = reason
	if type == Type.MODIFY and not modifications.is_empty():
		var mods: Array[Dictionary] = []
		for mod in modifications:
			mods.append(mod.to_dict())
		d["modifications"] = mods
	return d


# ========== 内部方法 ==========


static func _type_to_string(t: Type) -> String:
	match t:
		Type.PASS:
			return "pass"
		Type.CANCEL:
			return "cancel"
		Type.MODIFY:
			return "modify"
		_:
			return "unknown"
