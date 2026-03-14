class_name IntResolver
extends RefCounted
## IntResolver - 返回 int 的参数解析器
##
## 用于 Action 参数的延迟求值，支持固定值或动态计算。
## 通过 Resolvers.int_val() 和 Resolvers.int_fn() 创建。
##
## @example
##   # 固定值
##   var stacks := Resolvers.int_val(3)
##   
##   # 动态值
##   var stacks := Resolvers.int_fn(func(ctx): return ctx.get_current_event().stacks)
##   
##   # 在 Action 中使用
##   var value := stacks.resolve(ctx)

var _resolver: Callable

func _init(resolver: Callable) -> void:
	_resolver = resolver

## 解析值
func resolve(ctx: ExecutionContext) -> int:
	return _resolver.call(ctx) as int
