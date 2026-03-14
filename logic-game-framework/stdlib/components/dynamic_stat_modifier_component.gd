class_name DynamicStatModifierComponent
extends AbilityComponent
## DynamicStatModifierComponent - 动态属性修改器组件
##
## 与 StatModifierComponent 不同，此组件的 modifier 值会随源属性变化而动态更新。
## 用于实现"属性 A 越高，属性 B 越高"这类动态依赖效果。
##
## 【声明式动态依赖】
##
## 本组件通过 RawAttributeSet.register_dynamic_dep() 声明式注册动态依赖关系，
## 而非 Listener 回调。RawAttributeSet 在每个入口方法内部自动执行两轮快照求解，
## 保证精确可逆（add 再 remove 同一个 modifier = 原状态）和路径无关。
##
## 【使用示例】
##
##   var config := DynamicStatModifierConfig.new(
##       "max_hp",                           # 源属性
##       "atk",                              # 目标属性
##       AttributeModifier.Type.ADD_BASE,   # 修改器类型
##       0.01                                # 系数：atk += max_hp * 0.01
##   )
##   var component := DynamicStatModifierComponent.new(config)


## 配置
var config: DynamicStatModifierConfig

## 当前 modifier 的 ID
var _modifier_id: String = ""

## 生命周期上下文（用于 on_remove）
var _context: AbilityLifecycleContext = null


func _init(p_config: DynamicStatModifierConfig) -> void:
	config = p_config
	type = "DynamicStatModifierComponent"


func on_apply(context: AbilityLifecycleContext) -> void:
	_context = context
	_modifier_id = IdGenerator.generate_id("dynmod")

	var raw := context.attribute_set.get_raw()

	# 添加值为 0 的 modifier（求解器会自动计算正确值）
	var modifier := AttributeModifier.new(
		_modifier_id,
		config.target_attribute,
		config.modifier_type,
		0.0,
		context.ability.id,
	)
	raw.add_modifier(modifier)

	# 声明式注册动态依赖
	raw.register_dynamic_dep(
		_modifier_id,
		config.source_attribute,
		config.target_attribute,
		config.modifier_type,
		config.coefficient,
	)


func on_remove(context: AbilityLifecycleContext) -> void:
	var raw := context.attribute_set.get_raw()

	# 先取消动态依赖注册，再移除 modifier
	raw.unregister_dynamic_dep(_modifier_id)
	raw.remove_modifier(_modifier_id)
	_context = null
