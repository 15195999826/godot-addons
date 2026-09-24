## VisualHpDeltaAction - HP 增减卡片(瞬时)
##
## 表演层 hp 是 State(visual_hp 每 tick 朝 target_hp 收敛 lerp),不走声明式动画路径。
## 本卡片是瞬时指令(duration=0,progress=1 立即完成):apply 时把 actor.target_hp 加上
## delta(伤害是负,治疗是正),交由 VisualUpdater.tick_time 的 hp lerp 把 visual_hp 拉过去。
##
## 多次伤害的连续性由「单一 target_hp + 连续 lerp」天然保证 — 不会出现两个并行
## hp 动画互相覆盖。
class_name VisualHpDeltaAction
extends VisualAction


## hp 变化量(伤害负,治疗正)
var delta: float


func _init(
	p_actor_id: String,
	p_delta: float,
	p_delay: float = 0.0
) -> void:
	super._init(KIND_HP_DELTA, 0.0, p_delay)
	actor_id = p_actor_id
	delta = p_delta
