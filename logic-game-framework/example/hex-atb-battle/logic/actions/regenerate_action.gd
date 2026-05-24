## HexBattleRegenerateAction · Resource 自然恢复 (Phase C: hp).
##
## 与 HexBattleHealAction 严格区分:
##   - 不走 heal pipeline (无 pre-heal cancel / on_heal callback / heal amp / heal received modifier).
##   - 不产生 HealEvent. 产生 RegenerationEvent (kind=regeneration).
##   - 不触发 heal-related passive (post broadcast 推 regeneration event, 而非 heal event,
##     所以监听 'heal' 的 passive 收不到; 监听 'regeneration' 的将来 passive 可以).
##
## V1 contract:
##   - 单 target (selector 通常 = ability_owner).
##   - amount_per_period = resource_per_sec_resolver(ctx) * period_seconds.
##   - actual_amount clamp 到 max - current; 满血时 actual=0 仍 push 事件 (consumer 自查).
##   - target 死亡 / 不存在 -> skip 无事件.
class_name HexBattleRegenerateAction
extends Action.PrimitiveAction


## resource: "hp" (Phase C). 未来 "mp" 时这一个 Action 继续复用,
## 把字段从 hp/max_hp 切到 mp/max_mp.
var _resource: String

## 每秒恢复量 resolver; execute 时按 _period_seconds 缩放成 per-period 恢复.
var _per_sec_resolver: FloatResolver

## 一个 timeline tick 间隔 (秒). period=1.0 时 amount = per_sec; period=0.5 时 amount = per_sec*0.5.
var _period_seconds: float

## source 字符串, 记录到 RegenerationEvent.source 字段, 供 replay/分析归因.
var _source: String


func _init(
	target_selector: TargetSelector,
	resource: String,
	per_sec_resolver: FloatResolver,
	period_seconds: float,
	source: String = "general_passive",
) -> void:
	super._init(target_selector)
	type = "regenerate"
	_resource = resource
	_per_sec_resolver = per_sec_resolver
	_period_seconds = period_seconds
	_source = source


func execute(ctx: ExecutionContext) -> ActionResult:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	if battle == null:
		return ActionResult.create_success_result([], { "regen_skipped": "no_game_state" })
	var per_sec := _per_sec_resolver.resolve(ctx)
	if per_sec <= 0.0:
		return ActionResult.create_success_result([], { "regen_skipped": "zero_per_sec" })
	var amount := per_sec * _period_seconds
	if amount <= 0.0:
		return ActionResult.create_success_result([], { "regen_skipped": "zero_amount" })

	var targets := get_targets(ctx)
	var events: Array[Dictionary] = []
	for target_id in targets:
		var actor := battle.get_character_actor(target_id)
		if actor == null or actor.is_dead():
			continue
		# Phase C V1 只支持 hp; 未来 _resource == "mp" 走另条 attribute_set 字段.
		Log.assert_crash(_resource == "hp",
			"HexBattleRegenerateAction",
			"V1 仅支持 resource='hp', got '%s'" % _resource)
		var old_hp: float = actor.attribute_set.hp
		var max_hp: float = actor.attribute_set.max_hp
		var new_hp := minf(old_hp + amount, max_hp)
		var actual_amount := new_hp - old_hp
		actor.attribute_set.set_hp_base(new_hp)
		var event := BattleEvents.RegenerationEvent.create(
			target_id, _resource, amount, actual_amount, _source,
		)
		var event_dict: Dictionary = ctx.event_collector.push(event.to_dict())
		events.append(event_dict)
	if events.size() > 0:
		var alive_actor_ids := battle.get_alive_actor_ids()
		if alive_actor_ids.size() > 0:
			# 广播给存活 actor; heal-listening passive (kind="heal") 不会匹配, regeneration-listening
			# (kind="regeneration", 未来如需) 会匹配. 见 RegenerationEvent header.
			for ev in events:
				GameWorld.event_processor.process_post_event(ev, alive_actor_ids, battle)
	return ActionResult.create_success_result(events, { "regen_amount_per_target": amount })
