class_name FloatResolver
extends RefCounted
## FloatResolver - 返回 float 的参数解析器
##
## 用于 Action 参数的延迟求值，支持固定值或动态计算。
## 通过 Resolvers.float_val() 和 Resolvers.float_fn() 创建。
##
## @example
##   # 固定值
##   var damage := Resolvers.float_val(40.0)
##   
##   # 动态值
##   var damage := Resolvers.float_fn(func(ctx): return ctx.get_current_event().power)
##   
##   # 在 Action 中使用
##   var value := damage.resolve(ctx)

var _resolver: Callable

func _init(resolver: Callable) -> void:
	_resolver = resolver

## 解析值
func resolve(ctx: ExecutionContext) -> float:
	return _resolver.call(ctx) as float
