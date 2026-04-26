## ApplyHPDeltaAction - HP 增减动作(瞬时)
##
## 表演层 hp 是 State(visual_hp 每 tick 朝 target_hp 收敛 lerp),不再走声明式
## 动画 Action 路径。本 action 是瞬时指令(duration=0,progress=1 立即完成):
## apply 时把 actor.target_hp 加上 delta(伤害是负,治疗是正),交由 RenderWorld
## 的 hp lerp 收敛把 visual_hp 拉过去。
##
## 多次伤害的连续性由「单一 target_hp + 连续 lerp」天然保证 — 不会出现两个并行
## hp 动画互相覆盖。
##
## 边界依据见 docs/animation/event-vs-state.md「血条迁移到 state」节。
class_name FrontendApplyHPDeltaAction
extends FrontendVisualAction


## hp 变化量(伤害负,治疗正)
var delta: float


func _init(
	p_actor_id: String,
	p_delta: float,
	p_delay: float = 0.0
) -> void:
	super._init(ActionType.APPLY_HP_DELTA, 0.0, p_delay)
	actor_id = p_actor_id
	delta = p_delta
