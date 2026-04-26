## SurgeTickAction - Surge buff 的每周期 tick
##
## 极简:每 tick 减 1 stack + emit AbilityStacksChanged。无副作用 damage / heal,
## buff 本身的存在就是"涌动计时器"(stacks 显示在 UI)。
##
## 触发用 on_timeline_start(挂上立即生效) — 这是 Surge 的 game design 选择
## (跟 Poison 改用 on_timeline_end 不同)。挂上瞬间 fire 第一次 tick(stacks 3→2),
## 跟 grant 进同一个 collector frame,正好用来验证 frontend BuffVisualizer
## 在同帧 ADD+UPDATE 场景下能否正确显示 stacks 序列。
class_name HexBattleSurgeTickAction
extends Action.BaseAction


func _init() -> void:
	super._init(HexBattleTargetSelectors.ability_owner())
	type = "surge_tick"


func execute(ctx: ExecutionContext) -> ActionResult:
	if ctx.ability_ref == null:
		return ActionResult.create_success_result([], {})

	var ability := ctx.ability_ref.resolve()
	if ability == null or ability.is_expired():
		return ActionResult.create_success_result([], {})

	var owner_id := ability.owner_actor_id
	var stacks_before := ability.get_stacks()
	if stacks_before <= 0:
		ability.expire("surge_exhausted")
		return ActionResult.create_success_result([], {})

	ability.remove_stacks(1)
	var stacks_after := ability.get_stacks()

	ctx.event_collector.push(
		GameEvent.AbilityStacksChanged.create(
			owner_id, ability.id, ability.config_id, stacks_before, stacks_after
		).to_dict()
	)

	if stacks_after <= 0:
		ability.expire("surge_exhausted")

	return ActionResult.create_success_result([], { "surge_stacks": stacks_before })
