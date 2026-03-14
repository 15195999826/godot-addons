class_name Vector3Resolver
extends RefCounted
## Vector3Resolver - 返回 Vector3 的参数解析器
##
## 用于 Action 参数的延迟求值，支持固定值或动态计算。
## 通过 Resolvers.vec3_val() 和 Resolvers.vec3_fn() 创建。
##
## @example
##   # 固定值
##   var position := Resolvers.vec3_val(Vector3(100, 200, 0))
##   
##   # 动态值
##   var position := Resolvers.vec3_fn(func(ctx): return ctx.source.position)
##   
##   # 在 Action 中使用
##   var value := position.resolve(ctx)

var _resolver: Callable

func _init(resolver: Callable) -> void:
	_resolver = resolver

## 解析值
func resolve(ctx: ExecutionContext) -> Vector3:
	return _resolver.call(ctx) as Vector3
