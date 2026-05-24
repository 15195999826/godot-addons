## Phase F · ApplyFacingState - 朝向状态变更 VisualAction
##
## 翻译自 actor_facing_changed 事件 (FrontendActorFacingChangedVisualizer);
## 由 RenderWorld 瞬时 (无 duration / 无 lerp) 应用到 FrontendActorRenderState.facing_direction.
##
## 不引入 turn-speed / facing-lock / 旋转动画 (per spec).
class_name FrontendApplyFacingStateAction
extends FrontendVisualAction


## 目标 actor 的新朝向 (HexFacing.DIR_* 0..5).
var new_direction: int = 0


func _init(p_actor_id: String, p_new_direction: int) -> void:
	super._init(ActionType.APPLY_FACING_STATE, 0.0, 0.0)
	actor_id = p_actor_id
	new_direction = p_new_direction
