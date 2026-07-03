## ShieldBarVisualizer - 护盾状态变化的事件翻译器
##
## 与 BuffVisualizer 平行的视觉管线,专门维护 actor.shields 数组(血条上方
## 独立护盾条的数据来源)。
##
## 订阅 3 类事件,翻译为 ApplyShieldStateAction:
##   - AbilityGranted (有 ShieldComponent) → ADD   (从 payload 取 current/capacity)
##   - AbilityRemoved                       → REMOVE
##   - DamageEvent (consumption_records[]) → 每条 record 一次 UPDATE
##                                            (current = remaining,定位用 shield_ability_id)
##
## 白名单过滤:只有 SHIELD_REGISTRY 里登记的 config_id 才会产生 ShieldSummary。
## 未登记的护盾(包括逻辑层将来新增的)默认不显示,避免 UI 上乱出。
## REMOVE op 始终执行(不查白名单),确保即便登记被人为去掉也不会有遗留。
##
## 加新可视化护盾 = SHIELD_REGISTRY 加一行 + 同步 hex-atb-battle 那边
## ABILITY 已注册并带 ShieldComponent。
class_name FrontendShieldBarVisualizer
extends FrontendBaseVisualizer


## 颜色按 config_id 分桶,允许将来 aphotic_ward / barrier 等不同来源分色显示。
## V1 全部统一蓝色,留扩展点给视觉迭代。
const SHIELD_REGISTRY := {
	HexBattleWardBuff.CONFIG_ID: {
		"color": Color(0.3, 0.5, 1.0),
	},
	HexBattleShieldBuffs.PHYSICAL_CONFIG_ID: {
		"color": Color(0.95, 0.62, 0.28),
	},
	HexBattleShieldBuffs.MAGICAL_CONFIG_ID: {
		"color": Color(0.25, 0.85, 1.0),
	},
}


func _init() -> void:
	visualizer_name = "ShieldBarVisualizer"


func can_handle(event: Dictionary) -> bool:
	var kind := get_event_kind(event)
	return (
		kind == GameEvent.ABILITY_GRANTED_EVENT
		or kind == GameEvent.ABILITY_REMOVED_EVENT
		or kind == BattleEvents.DAMAGE_EVENT
	)


func translate(event: Dictionary, _context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var actions: Array[FrontendVisualAction] = []
	match get_event_kind(event):
		GameEvent.ABILITY_GRANTED_EVENT:
			_handle_granted(event, actions)
		GameEvent.ABILITY_REMOVED_EVENT:
			_handle_removed(event, actions)
		BattleEvents.DAMAGE_EVENT:
			_handle_damage(event, actions)
	return actions


func _handle_granted(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	var actor_id := get_string_field(event, "actorId")
	var payload: Dictionary = event.get("ability", {})
	var config_id := payload.get("configId", "") as String
	var rule = SHIELD_REGISTRY.get(config_id)
	if rule == null:
		return
	# 没有 ShieldComponent 的不挂 shield bar(白名单已过滤,但防御一下)
	var data := FrontendShieldSummary.find_shield_component_data(payload)
	if data.is_empty():
		return
	var ability_id := payload.get("instanceId", payload.get("id", "")) as String
	if ability_id.is_empty() or actor_id.is_empty():
		return

	var summary := FrontendShieldSummary.new()
	summary.id = ability_id
	summary.config_id = config_id
	summary.current = data.get("current", 0.0) as float
	summary.capacity = data.get("capacity", summary.current) as float
	summary.color = rule["color"]
	summary.priority = data.get("priority", 0) as int

	actions.append(FrontendApplyShieldStateAction.new(
		actor_id, FrontendApplyShieldStateAction.Op.ADD, ability_id, summary
	))


func _handle_removed(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	# REMOVE 不查白名单,确保即便登记被去掉也保证清理一致。
	var actor_id := get_string_field(event, "actorId")
	var ability_id := get_string_field(event, "abilityInstanceId")
	if actor_id.is_empty() or ability_id.is_empty():
		return
	actions.append(FrontendApplyShieldStateAction.new(
		actor_id, FrontendApplyShieldStateAction.Op.REMOVE, ability_id, null
	))


func _handle_damage(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	var consumption: Array = event.get("consumption_records", [])
	if consumption.is_empty():
		return
	for record_variant in consumption:
		var record: Dictionary = record_variant
		var config_id := record.get("shield_config_id", "") as String
		var rule = SHIELD_REGISTRY.get(config_id)
		if rule == null:
			continue
		var actor_id := record.get("owner_actor_id", "") as String
		var ability_id := record.get("shield_ability_id", "") as String
		if actor_id.is_empty() or ability_id.is_empty():
			continue
		# broken=true 时 remaining=0,这里只 UPDATE 不删除;ability 自然 expire
		# 后由 AbilityRemoved 触发 REMOVE,语义和 BuffVisualizer 对齐。
		var summary := FrontendShieldSummary.new()
		summary.id = ability_id
		summary.config_id = config_id
		summary.current = record.get("remaining", 0.0) as float
		summary.capacity = record.get("capacity", summary.current) as float
		summary.color = rule["color"]
		summary.priority = record.get("priority", 0) as int
		actions.append(FrontendApplyShieldStateAction.new(
			actor_id, FrontendApplyShieldStateAction.Op.UPDATE, ability_id, summary
		))
