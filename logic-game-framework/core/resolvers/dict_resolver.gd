class_name DictResolver
extends RefCounted
## DictResolver - 返回 Dictionary 的参数解析器
##
## 用于 Action 参数的延迟求值，支持固定值或动态计算。
## 通过 Resolvers.dict_val() 和 Resolvers.dict_fn() 创建。
##
## @example
##   # 固定值
##   var params := Resolvers.dict_val({ "intensity": 1.5 })
##   
##   # 动态值
##   var params := Resolvers.dict_fn(func(ctx): return ctx.get_current_event().params)
##   
##   # 在 Action 中使用
##   var value := params.resolve(ctx)

var _resolver: Callable

func _init(resolver: Callable) -> void:
	_resolver = resolver

## 解析值
func resolve(ctx: ExecutionContext) -> Dictionary:
	return _resolver.call(ctx) as Dictionary
