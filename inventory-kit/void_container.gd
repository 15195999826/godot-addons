class_name IKVoidContainer extends IKBaseContainer
## Void container — accepts everything, acts as item trash/sink.
## Automatically created by ItemSystem on init.

func _init() -> void:
	super(IKTypes.SpaceConfig.unordered(-1))


func can_add_item(_item: IKTypes.ItemInstance, _slot_index: int) -> bool:
	return true


func can_move_item(_item: IKTypes.ItemInstance, _slot_index: int) -> bool:
	return true
