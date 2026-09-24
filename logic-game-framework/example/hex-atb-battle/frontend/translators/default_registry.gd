## FrontendDefaultRegistry - hex 默认翻译员注册表工厂
##
## 纯静态工具类，用于创建预配置的 TranslatorRegistry
class_name FrontendDefaultRegistry


## 创建默认注册表
static func create() -> TranslatorRegistry:
	var registry := TranslatorRegistry.new()

	# 注册所有默认翻译员
	registry.register(FrontendMoveTranslator.new())
	registry.register(FrontendDisplacementTranslator.new())
	registry.register(FrontendPushBlockedTranslator.new())
	registry.register(FrontendDamageTranslator.new())
	registry.register(FrontendHealTranslator.new())
	registry.register(FrontendRegenerationTranslator.new())
	registry.register(FrontendDeathTranslator.new())
	registry.register(FrontendProjectileTranslator.new())
	registry.register(FrontendStageCueTranslator.new())
	registry.register(FrontendBuffTranslator.new())
	registry.register(FrontendShieldBarTranslator.new())
	registry.register(FrontendActorFacingChangedTranslator.new())

	return registry
