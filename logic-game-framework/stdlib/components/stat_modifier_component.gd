class_name StatModifierComponent
extends AbilityComponent
## StatModifierComponent 的工作方式是：
## Ability 被赋予角色时 → on_apply() → 添加属性修改器
## Ability 被移除时 → on_remove() → 清除属性修改器
##
## §0.X: scales_by_stacks=true 时, modifier 实际 value = config.value * ability.stacks
## stacks 变化通过 on_stacks_changed 钩子用 RawAttributeSet.update_modifier 原子更新,
## 不走 remove + add (避免 modifier breakdown 闪烁与 dirty 两次)。

var configs: Array[StatModifierConfig.ModifierEntry]
var modifier_prefix: String
var applied_modifiers: Array[AttributeModifier] = []
var current_scale: float = 1.0
## §0.X: stack-scaled 模式标志
var scales_by_stacks: bool = false

func _init(modifier_configs: Array[StatModifierConfig.ModifierEntry], p_scales_by_stacks: bool = false) -> void:
	configs = modifier_configs
	modifier_prefix = IdGenerator.generate_id("statmod")
	scales_by_stacks = p_scales_by_stacks
	type = "StatModifierComponent"

func on_apply(context: AbilityLifecycleContext) -> void:
	# §0.X: scales_by_stacks 时初始 scale = ability.stacks (而非默认 current_scale=1.0)
	if scales_by_stacks and context.ability != null:
		current_scale = float(context.ability.get_stacks())
	applied_modifiers = _create_modifiers_internal(context)
	var raw: RawAttributeSet = context.attribute_set.get_raw()
	for modifier in applied_modifiers:
		raw.add_modifier(modifier)

func _create_modifiers_internal(context: AbilityLifecycleContext) -> Array[AttributeModifier]:
	var result: Array[AttributeModifier] = []
	for i in range(configs.size()):
		var config := configs[i]
		var modifier := AttributeModifier.new(
			"%s_%d" % [modifier_prefix, i],
			config.attribute_name,
			config.modifier_type,
			config.value * current_scale,
			context.ability.id,
		)
		result.append(modifier)
	return result

func on_remove(context: AbilityLifecycleContext) -> void:
	context.attribute_set.get_raw().remove_modifiers_by_source(context.ability.id)
	_clear_modifiers_internal()

## §0.X: 在 Ability stacks 真实变化时，按 new_stacks 重算所有 modifier value，
## 通过 RawAttributeSet.update_modifier 原子更新 (不 remove + add)。
##
## 非 scales_by_stacks 模式 no-op (保留 current_scale 由外部 set_scale 控制)。
func on_stacks_changed(context: AbilityLifecycleContext, _old_stacks: int, new_stacks: int) -> void:
	if not scales_by_stacks:
		return
	if context == null or context.attribute_set == null:
		return
	current_scale = float(new_stacks)
	var raw: RawAttributeSet = context.attribute_set.get_raw()
	for i in range(applied_modifiers.size()):
		var mod := applied_modifiers[i]
		var cfg := configs[i]
		var new_value := cfg.value * current_scale
		raw.update_modifier(mod.id, new_value)

func _clear_modifiers_internal() -> void:
	applied_modifiers.clear()

func get_modifiers() -> Array[AttributeModifier]:
	return applied_modifiers.duplicate()

func get_modifier_ids() -> Array[String]:
	var result: Array[String] = []
	for modifier in applied_modifiers:
		result.append(modifier.id)
	return result

func set_scale(scale: float) -> void:
	current_scale = scale

func scale_by_stacks(stacks: int) -> void:
	set_scale(float(stacks))

func get_configs() -> Array[StatModifierConfig.ModifierEntry]:
	return configs.duplicate()

func serialize() -> Dictionary:
	var serialized_configs: Array[Dictionary] = []
	for config in configs:
		serialized_configs.append({
			"attributeName": config.attribute_name,
			"modifierType": AttributeModifier.Type.keys()[config.modifier_type],
			"value": config.value,
		})
	return {
		"configs": serialized_configs,
		"scale": current_scale,
		"scalesByStacks": scales_by_stacks,
	}

func deserialize(data: Dictionary) -> void:
	current_scale = float(data.get("scale", 1.0))
	scales_by_stacks = bool(data.get("scalesByStacks", false))
