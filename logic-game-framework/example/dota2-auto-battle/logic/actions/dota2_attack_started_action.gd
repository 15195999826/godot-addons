## Dota2AttackStartedAction - 基础攻击 Timeline 起手同步 cue
##
## 接在 Dota2BasicAttackAbility 的 on_timeline_start：每轮攻击 timeline 一开始就 push
## attack_started 事件（source = ability owner，target = 激活事件携带的 intent 目标）。
## 与 hex StageCueAction 同位（同步执行，在 activate 调用链里立即跑）。
class_name Dota2AttackStartedAction
extends Action.BaseAction


var _config_id: String = ""


func _init(target_selector: TargetSelector, p_config_id: String) -> void:
	super._init(target_selector)
	type = "dota2_attack_started"
	_config_id = p_config_id


func execute(ctx: ExecutionContext) -> ActionResult:
	var source_id: String = ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var targets := get_targets(ctx)
	var target_id := targets[0] if not targets.is_empty() else ""
	var evt := Dota2BattleEvents.make_attack_started(source_id, target_id, _config_id)
	ctx.event_collector.push(evt)
	return ActionResult.create_success_result([evt])
