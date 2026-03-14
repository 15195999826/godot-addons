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

func _init(resolver: Callable) -> void:
	_resolver = resolver

## 解析值
func resolve(ctx: ExecutionContext) -> String:
	return _resolver.call(ctx) as String
