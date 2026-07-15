## CancelMoveAction - 移动 execution 异常取消时释放目的地预订。
class_name HexBattleCancelMoveAction
extends Action.PrimitiveAction


var _target_coord: DictResolver


func _init(target_selector: TargetSelector, target_coord: DictResolver) -> void:
	super._init(target_selector)
	type = "cancel_move"
	_target_coord = target_coord


func execute(ctx: ExecutionContext) -> ActionResult:
	var battle := ctx.game_state_provider as HexWorldGameplayInstance
	if battle == null:
		return ActionResult.create_failure_result("HexWorldGameplayInstance is required")
	var target_coord_dict := _target_coord.resolve(ctx)
	if target_coord_dict.is_empty():
		return ActionResult.create_failure_result("cancelled move has no target coord")
	var target_coord := HexCoord.from_dict(target_coord_dict)
	for target_id in get_targets(ctx):
		if battle.grid.get_reservation(target_coord) == target_id:
			battle.grid.cancel_reservation(target_coord)
	return ActionResult.create_success_result([], {"target_coord": target_coord_dict})
