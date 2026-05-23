## BuffVisualizer - buff 状态变化的事件翻译器
##
## 订阅 4 类事件,翻译为 ApplyBuffStateAction:
##   - AbilityGranted          → ADD     (从 payload 取 stacks / 决定 primary)
##   - AbilityStacksChanged    → UPDATE  (primary = newStacks)
##   - AbilityRemoved          → REMOVE
##   - DamageEvent (consumption_records[]) → 每条 record 一次 UPDATE
##                              (primary = remaining,定位用 shield_ability_id)
##
## 白名单过滤:只有 BUFF_REGISTRY 里登记的 config_id 才会产生 BuffSummary。
## 未登记的 buff(包括逻辑层将来新增的)默认不显示,避免 UI 上乱出。
## REMOVE op 始终执行(不查白名单),确保即便登记被人为去掉也不会有遗留 BuffSummary。
##
## 加新可视化 buff = BUFF_REGISTRY 加一行 + 同步 hex-atb-battle 那边的 ABILITY 已注册。
class_name FrontendBuffVisualizer
extends FrontendBaseVisualizer


## primary 取值策略:
##   STACKS           - 从 ability.stacks(grant)/ AbilityStacksChanged.newStacks 取
##   SHIELD_REMAINING - 从 ShieldComponent.current(grant)/ DamageEvent record.remaining 取
##   NONE             - 始终 0(纯被动)
enum PrimarySource { STACKS, SHIELD_REMAINING, NONE }


## buff_id 用 ability 自身 CONFIG_ID 常量,避免字符串漂移。
const BUFF_REGISTRY := {
	HexBattlePoisonBuff.CONFIG_ID: {
		"short": "P",
		"color": Color(0.6, 0.2, 0.8),
		"primary_source": PrimarySource.STACKS,
	},
	HexBattleExposeBuff.CONFIG_ID: {
		"short": "E",
		"color": Color(0.9, 0.4, 0.2),  # 橙红, 区分 Poison 紫色
		"primary_source": PrimarySource.NONE,  # 无 stacks, 仅 duration
	},
	HexBattleWardBuff.CONFIG_ID: {
		"short": "S",
		"color": Color(0.3, 0.5, 1.0),
		"primary_source": PrimarySource.SHIELD_REMAINING,
	},
	HexBattleSurgeBuff.CONFIG_ID: {
		"short": "U",
		"color": Color(0.95, 0.6, 0.2),
		"primary_source": PrimarySource.STACKS,
	},
	HexBattleThorn.CONFIG_ID: {
		"short": "T",
		"color": Color(1.0, 0.5, 0.2),
		"primary_source": PrimarySource.NONE,
	},
	HexBattleVitality.CONFIG_ID: {
		"short": "V",
		"color": Color(0.3, 0.9, 0.4),
		"primary_source": PrimarySource.NONE,
	},
	HexBattleVigor.CONFIG_ID: {
		"short": "G",
		"color": Color(0.95, 0.85, 0.3),
		"primary_source": PrimarySource.NONE,
	},
	HexBattleStunBuff.CONFIG_ID: {
		"short": "★",
		"color": Color(0.95, 0.85, 0.2),  # 金黄 - 头顶星星即视感
		"primary_source": PrimarySource.NONE,  # 多实例独立挂, 单条 entry 表达"被眩晕"即可
	},
}


func _init() -> void:
	visualizer_name = "BuffVisualizer"


func can_handle(event: Dictionary) -> bool:
	var kind := get_event_kind(event)
	return (
		kind == GameEvent.ABILITY_GRANTED_EVENT
		or kind == GameEvent.ABILITY_STACKS_CHANGED_EVENT
		or kind == GameEvent.ABILITY_REMOVED_EVENT
		or kind == "damage"
	)


func translate(event: Dictionary, _context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var actions: Array[FrontendVisualAction] = []
	match get_event_kind(event):
		GameEvent.ABILITY_GRANTED_EVENT:
			_handle_granted(event, actions)
		GameEvent.ABILITY_STACKS_CHANGED_EVENT:
			_handle_stacks_changed(event, actions)
		GameEvent.ABILITY_REMOVED_EVENT:
			_handle_removed(event, actions)
		"damage":
			_handle_damage(event, actions)
	return actions


func _handle_granted(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	var actor_id := get_string_field(event, "actorId")
	var payload: Dictionary = event.get("ability", {})
	var config_id := payload.get("configId", "") as String
	var rule = BUFF_REGISTRY.get(config_id)
	if rule == null:
		return
	var ability_id := payload.get("instanceId", payload.get("id", "")) as String
	if ability_id.is_empty() or actor_id.is_empty():
		return

	var summary := _build_summary(
		ability_id, config_id, rule,
		_resolve_initial_primary(payload, rule["primary_source"])
	)
	summary.display_name = payload.get("displayName", "") as String

	actions.append(FrontendApplyBuffStateAction.new(
		actor_id, FrontendApplyBuffStateAction.Op.ADD, ability_id, summary
	))


func _handle_stacks_changed(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	var config_id := get_string_field(event, "abilityConfigId")
	var rule = BUFF_REGISTRY.get(config_id)
	if rule == null or rule["primary_source"] != PrimarySource.STACKS:
		return
	var actor_id := get_string_field(event, "actorId")
	var ability_id := get_string_field(event, "abilityInstanceId")
	if actor_id.is_empty() or ability_id.is_empty():
		return
	var summary := _build_summary(
		ability_id, config_id, rule, float(event.get("newStacks", 0))
	)
	actions.append(FrontendApplyBuffStateAction.new(
		actor_id, FrontendApplyBuffStateAction.Op.UPDATE, ability_id, summary
	))


func _handle_removed(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	# REMOVE 不查白名单,确保即便登记被去掉也保证清理一致。
	var actor_id := get_string_field(event, "actorId")
	var ability_id := get_string_field(event, "abilityInstanceId")
	if actor_id.is_empty() or ability_id.is_empty():
		return
	actions.append(FrontendApplyBuffStateAction.new(
		actor_id, FrontendApplyBuffStateAction.Op.REMOVE, ability_id, null
	))


func _handle_damage(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	var consumption: Array = event.get("consumption_records", [])
	if consumption.is_empty():
		return
	for record_variant in consumption:
		var record: Dictionary = record_variant
		var config_id := record.get("shield_config_id", "") as String
		var rule = BUFF_REGISTRY.get(config_id)
		if rule == null or rule["primary_source"] != PrimarySource.SHIELD_REMAINING:
			continue
		var actor_id := record.get("owner_actor_id", "") as String
		var ability_id := record.get("shield_ability_id", "") as String
		if actor_id.is_empty() or ability_id.is_empty():
			continue
		# broken=true 时 remaining=0,不在这里删 BuffSummary,等 AbilityRemoved
		# 兜底(逻辑层 on_break 后会 expire ability,触发 AbilityRemoved)。
		var summary := _build_summary(
			ability_id, config_id, rule, record.get("remaining", 0.0) as float
		)
		actions.append(FrontendApplyBuffStateAction.new(
			actor_id, FrontendApplyBuffStateAction.Op.UPDATE, ability_id, summary
		))


func _build_summary(
	ability_id: String, config_id: String, rule: Dictionary, primary: float
) -> FrontendBuffSummary:
	var summary := FrontendBuffSummary.new()
	summary.id = ability_id
	summary.config_id = config_id
	summary.short = rule["short"]
	summary.color = rule["color"]
	summary.primary = primary
	return summary


## 从 ability.serialize() 的 payload 推断初始 primary。
func _resolve_initial_primary(payload: Dictionary, primary_source: PrimarySource) -> float:
	match primary_source:
		PrimarySource.STACKS:
			return float(payload.get("stacks", 0))
		PrimarySource.SHIELD_REMAINING:
			var data := FrontendShieldSummary.find_shield_component_data(payload)
			return data.get("current", 0.0) as float
		_:
			return 0.0
