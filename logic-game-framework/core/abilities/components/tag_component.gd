class_name TagComponent
extends AbilityComponent

const TYPE := "TagComponent"

var _tags: Dictionary = {}

func _init(config: Dictionary):
	type = TYPE
	_tags = config.get("tags", {}).duplicate(true)

func on_apply(context: AbilityLifecycleContext) -> void:
	var aset := context.ability_set
	if aset == null:
		return
	aset._add_component_tags(context.ability.id, _tags)

func on_remove(context: AbilityLifecycleContext) -> void:
	var aset := context.ability_set
	if aset == null:
		return
	aset._remove_component_tags(context.ability.id)

func serialize() -> Dictionary:
	return {
		"type": type,
		"tags": _tags,
	}
