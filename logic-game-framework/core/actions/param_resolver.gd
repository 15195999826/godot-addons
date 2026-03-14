class_name ParamResolver
## 纯静态工具类：参数解析辅助函数

static func resolve_param(resolver: Variant, ctx: ExecutionContext) -> Variant:
	if resolver is Callable:
		return resolver.call(ctx)
	return resolver

static func resolve_optional_param(resolver: Variant, default_value: Variant, ctx: ExecutionContext) -> Variant:
	if resolver == null:
		return default_value
	return resolve_param(resolver, ctx)
