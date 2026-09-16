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


func _init(p_config: DynamicStatModifierConfig) -> void:
	config = p_config
	type = "DynamicStatModifierComponent"


func on_apply(context: AbilityLifecycleContext) -> void:
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


## 内部记录只有 _modifier_id：它留给 on_passive_enabled 重用、下一次 on_apply 重新生成，这里不清。
func on_remove(context: AbilityLifecycleContext) -> void:
	var raw := _raw_attribute_set_or_assert(context, "on_remove")
	if raw == null:
		return
	# 先取消动态依赖注册，再移除 modifier
	raw.unregister_dynamic_dep(_modifier_id)
	raw.remove_modifier(_modifier_id)


## Phase B2 (Break): 进入 disabled 状态时撤销动态依赖 + modifier。
## _modifier_id 保留以便 on_passive_enabled 用同 id 重新注册 (避免依赖图重新生成 noise)。
func on_passive_disabled(context: AbilityLifecycleContext) -> void:
	var raw := _raw_attribute_set_or_assert(context, "on_passive_disabled")
	if raw == null:
		return
	raw.unregister_dynamic_dep(_modifier_id)
	raw.remove_modifier(_modifier_id)


## Phase B2 (Break): 最后一个 disabled source 移除时, 按 Ability 当前状态重建动态依赖。
## 重用同一个 _modifier_id (与 on_apply 生成的一致); RawAttributeSet 求解器立即按当前
## source attribute 值算出正确 modifier value。
func on_passive_enabled(context: AbilityLifecycleContext) -> void:
	var raw := _raw_attribute_set_or_assert(context, "on_passive_enabled")
	if raw == null:
		return
	var modifier := AttributeModifier.new(
		_modifier_id,
		config.target_attribute,
		config.modifier_type,
		0.0,
		context.ability.id,
	)
	raw.add_modifier(modifier)
	raw.register_dynamic_dep(
		_modifier_id,
		config.source_attribute,
		config.target_attribute,
		config.modifier_type,
		config.coefficient,
	)


## 清理 / 重建钩子共用的守卫。属性集为 null 只在「owner 已不在 instance / instance 已销毁后仍 revoke 或 Break」时出现
## （context 按 owner 反查、拿不到 actor）——那是合同违反：modifier 与动态依赖留在别处的属性集上、本组件清不到，所以
## 响亮断言（debug 只中止本帧、release 停机，与 grant 断言同口径）而不静默返回；调用方直接返回。
func _raw_attribute_set_or_assert(context: AbilityLifecycleContext, hook: String) -> RawAttributeSet:
	if context != null and context.attribute_set != null:
		return context.attribute_set.get_raw()
	Log.assert_crash(false, "DynamicStatModifierComponent",
		"%s: owner 已不在 instance / instance 已销毁，modifier 无法清理" % hook)
	return null
