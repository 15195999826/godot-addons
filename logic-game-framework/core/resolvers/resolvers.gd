## Resolvers - 参数解析器工厂
##
## 提供类型安全的延迟求值参数创建方法。
## 用于替代 Variant 类型的 Action 参数，提供更好的类型提示和可读性。
##
## @example
##   # 固定值
##   DamageAction.new(selector, Resolvers.float_val(40.0))
##   StageCueAction.new(selector, Resolvers.str_val("attack_slash"))
##   
##   # 动态值
##   DamageAction.new(selector, Resolvers.float_fn(
##       func(ctx): return ctx.get_current_event().power
##   ))
##   
##   # 作为默认参数
##   func _init(duration: FloatResolver = Resolvers.float_val(-1.0)) -> void:
class_name Resolvers


# ============================================================
# Float 解析器
# ============================================================

## 创建固定 float 值的解析器
static func float_val(v: float) -> FloatResolver:
	return FloatResolver.new(func(_ctx): return v)

## 创建动态 float 值的解析器
static func float_fn(callable: Callable) -> FloatResolver:
	return FloatResolver.new(callable)


# ============================================================
# Int 解析器
# ============================================================

## 创建固定 int 值的解析器
static func int_val(v: int) -> IntResolver:
	return IntResolver.new(func(_ctx): return v)

## 创建动态 int 值的解析器
static func int_fn(callable: Callable) -> IntResolver:
	return IntResolver.new(callable)


# ============================================================
# String 解析器
# ============================================================

## 创建固定 String 值的解析器
static func str_val(v: String) -> StringResolver:
	return StringResolver.new(func(_ctx): return v)

## 创建动态 String 值的解析器
static func str_fn(callable: Callable) -> StringResolver:
	return StringResolver.new(callable)


# ============================================================
# Dictionary 解析器
# ============================================================

## 创建固定 Dictionary 值的解析器
static func dict_val(v: Dictionary) -> DictResolver:
	return DictResolver.new(func(_ctx): return v)

## 创建动态 Dictionary 值的解析器
static func dict_fn(callable: Callable) -> DictResolver:
	return DictResolver.new(callable)


# ============================================================
# Vector3 解析器
# ============================================================

## 创建固定 Vector3 值的解析器
static func vec3_val(v: Vector3) -> Vector3Resolver:
	return Vector3Resolver.new(func(_ctx): return v)

## 创建动态 Vector3 值的解析器
static func vec3_fn(callable: Callable) -> Vector3Resolver:
	return Vector3Resolver.new(callable)
