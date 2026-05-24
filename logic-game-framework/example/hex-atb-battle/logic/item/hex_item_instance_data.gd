## HexItemInstanceData - Hex 项目层 item instance data
##
## V1 只保留 config_id / count (继承自 base);不引入 charge / runtime_attributes /
## affixes / granted_ability_ids 等 Plan 标注的预留字段。
class_name HexItemInstanceData
extends ItemInstanceData


func _init(p_config_id: StringName = &"", p_count: int = 1) -> void:
	super(p_config_id, p_count)
