class_name StatModifierComponent
extends AbilityComponent
## StatModifierComponent 的工作方式是：
## Ability 被赋予角色时 → on_apply() → 添加属性修改器
## Ability 被移除时 → on_remove() → 清除属性修改器

var configs: Array[StatModifierConfig.ModifierEntry]
var modifier_prefix: String
var applied_modifiers: Array[AttributeModifier] = []
var current_scale: float = 1.0

func _init(modifier_configs: Array[StatModifierConfig.ModifierEntry]) -> void:
	configs = modifier_configs
	modifier_prefix = IdGenerator.generate_id("statmod")
	type = "StatModifierComponent"

func on_apply(context: AbilityLifecycleContext) -> void:
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
	}

func deserialize(data: Dictionary) -> void:
	current_scale = float(data.get("scale", 1.0))
