class_name StageCueAction
extends Action.BaseAction

const TYPE = "stageCue"

var _cue_id: StringResolver
var _cue_params: DictResolver

## 构造函数
## @param target_selector: 目标选择器
## @param cue_id: 舞台提示 ID 解析器
## @param cue_params: 舞台提示参数解析器，可选
func _init(
	target_selector: TargetSelector,
	cue_id: StringResolver,
	cue_params: DictResolver = Resolvers.dict_val({})
) -> void:
	super._init(target_selector)
	type = TYPE
	_cue_id = cue_id
	_cue_params = cue_params

## 只读探查口: cue 为固定值(Resolvers.str_val)时返回该值, 动态 resolver 返回 ""。
## 供 manifest lint 在不构造 ExecutionContext 的情况下收集全部静态 cue 做存在性断言。
func get_fixed_cue() -> String:
	return _cue_id.try_get_fixed_value()


func execute(ctx: ExecutionContext) -> ActionResult:
	if ctx.ability_ref == null:
		push_error("[StageCueAction] ctx.ability_ref is required")
		return ActionResult.create_failure_result("ctx.ability_ref is required")

	var source_actor_id := ctx.ability_ref.source_actor_id

	var targets := get_targets(ctx)
	var target_actor_ids: Array[String] = []
	for target_id in targets:
		target_actor_ids.append(target_id)

	var cue_id_value := _cue_id.resolve(ctx)
	var params_value := _cue_params.resolve(ctx)

	var event := GameEvent.StageCue.create(
		source_actor_id,
		target_actor_ids,
		cue_id_value,
		params_value
	)

	ctx.event_collector.push(event.to_dict())

	return ActionResult.create_success_result([event.to_dict()])
