class_name StringResolver
extends RefCounted
## StringResolver - 返回 String 的参数解析器
##
## 用于 Action 参数的延迟求值，支持固定值或动态计算。
## 通过 Resolvers.str_val() 和 Resolvers.str_fn() 创建。
##
## @example
##   # 固定值
##   var cue_id := Resolvers.str_val("attack_slash")
##   
##   # 动态值
##   var cue_id := Resolvers.str_fn(func(ctx): return ctx.get_current_event().cue_id)
##   
##   # 在 Action 中使用
##   var value := cue_id.resolve(ctx)

var _resolver: Callable

## 固定值元数据: 构造时一次绑定(Resolvers.str_val 传入), 与 _resolver 不可脱钩 ——
## 工装(如 manifest lint 的 cue 存在性断言)经 try_get_fixed_value() 无 ctx 静态读值。
## str_fn 动态解析器无元数据。字段私有: 事后改写会造成"lint 查 A、运行时 resolve B"假绿。
var _is_fixed: bool = false
var _fixed_value: String = ""

func _init(resolver: Callable, p_is_fixed: bool = false, p_fixed_value: String = "") -> void:
	_resolver = resolver
	_is_fixed = p_is_fixed
	_fixed_value = p_fixed_value

## 解析值
func resolve(ctx: ExecutionContext) -> String:
	return _resolver.call(ctx) as String

## 静态读固定值: 固定解析器返回构造时绑定的值, 动态解析器返回 ""。
func try_get_fixed_value() -> String:
	return _fixed_value if _is_fixed else ""
