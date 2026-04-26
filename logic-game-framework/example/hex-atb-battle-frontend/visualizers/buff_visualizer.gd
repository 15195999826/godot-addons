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


## 一项 = 一个 buff 在 UI 上的显示规则
## primary_source: "stacks" | "shield_remaining" | "none"
##   - stacks: 从 ability.stacks 取 primary;AbilityStacksChanged.newStacks 更新
##   - shield_remaining: 从 ability.components 里的 ShieldComponent.current 取
##                       初值;DamageEvent.consumption_records.remaining 更新
##   - none: primary 始终 0(纯被动如 Thorn / Vitality / Vigor)
const BUFF_REGISTRY := {
	"buff_poison": {
		"short": "P",
		"color": Color(0.6, 0.2, 0.8),    # 紫
		"primary_source": "stacks",
	},
	"buff_ward": {
		"short": "S",
		"color": Color(0.3, 0.5, 1.0),    # 蓝
		"primary_source": "shield_remaining",
	},
	"passive_thorn": {
		"short": "T",
		"color": Color(1.0, 0.5, 0.2),    # 橙
		"primary_source": "none",
	},
	"passive_vitality": {
		"short": "V",
		"color": Color(0.3, 0.9, 0.4),    # 绿
		"primary_source": "none",
	},
	"passive_vigor": {
		"short": "G",
		"color": Color(0.95, 0.85, 0.3),  # 黄
		"primary_source": "none",
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
	var kind := get_event_kind(event)
	match kind:
		GameEvent.ABILITY_GRANTED_EVENT:
			_handle_granted(event, actions)
		GameEvent.ABILITY_STACKS_CHANGED_EVENT:
			_handle_stacks_changed(event, actions)
		GameEvent.ABILITY_REMOVED_EVENT:
			_handle_removed(event, actions)
		"damage":
			_handle_damage(event, actions)
	return actions


# ========== 内部:事件处理 ==========

func _handle_granted(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	var actor_id := event.get("actorId", "") as String
	var payload: Dictionary = event.get("ability", {})
	var config_id := payload.get("configId", "") as String
	if not BUFF_REGISTRY.has(config_id):
		return
	var rule: Dictionary = BUFF_REGISTRY[config_id]
	var ability_id := payload.get("instanceId", payload.get("id", "")) as String
	if ability_id.is_empty() or actor_id.is_empty():
		return

	var summary := FrontendBuffSummary.new()
	summary.id = ability_id
	summary.config_id = config_id
	summary.display_name = payload.get("displayName", "") as String
	summary.short = rule["short"]
	summary.color = rule["color"]
	summary.primary = _resolve_initial_primary(payload, rule["primary_source"])

	actions.append(FrontendApplyBuffStateAction.new(
		actor_id, FrontendApplyBuffStateAction.Op.ADD, ability_id, summary
	))


func _handle_stacks_changed(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	var config_id := event.get("abilityConfigId", "") as String
	if not BUFF_REGISTRY.has(config_id):
		return
	var rule: Dictionary = BUFF_REGISTRY[config_id]
	if rule["primary_source"] != "stacks":
		return  # 只有 stacks 类 buff 关心 stacks 变化

	var actor_id := event.get("actorId", "") as String
	var ability_id := event.get("abilityInstanceId", "") as String
	var new_stacks := event.get("newStacks", 0) as int
	if actor_id.is_empty() or ability_id.is_empty():
		return

	var summary := FrontendBuffSummary.new()
	summary.id = ability_id
	summary.config_id = config_id
	summary.short = rule["short"]
	summary.color = rule["color"]
	summary.primary = float(new_stacks)

	actions.append(FrontendApplyBuffStateAction.new(
		actor_id, FrontendApplyBuffStateAction.Op.UPDATE, ability_id, summary
	))


func _handle_removed(event: Dictionary, actions: Array[FrontendVisualAction]) -> void:
	# REMOVE 不查白名单:即便登记被去掉也保证清理一致。RenderWorld 端
	# 找不到对应 BuffSummary 会自然 noop。
	var actor_id := event.get("actorId", "") as String
	var ability_id := event.get("abilityInstanceId", "") as String
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
		if not BUFF_REGISTRY.has(config_id):
			continue
		var rule: Dictionary = BUFF_REGISTRY[config_id]
		if rule["primary_source"] != "shield_remaining":
			continue
		var actor_id := record.get("owner_actor_id", "") as String
		var ability_id := record.get("shield_ability_id", "") as String
		if actor_id.is_empty() or ability_id.is_empty():
			continue
		# broken=true 时 remaining=0:不在这里删 BuffSummary,等 AbilityRemoved
		# 事件来兜底(逻辑层 on_break 后会 expire ability,触发 AbilityRemoved)。
		var remaining := record.get("remaining", 0.0) as float
		var summary := FrontendBuffSummary.new()
		summary.id = ability_id
		summary.config_id = config_id
		summary.short = rule["short"]
		summary.color = rule["color"]
		summary.primary = remaining
		actions.append(FrontendApplyBuffStateAction.new(
			actor_id, FrontendApplyBuffStateAction.Op.UPDATE, ability_id, summary
		))


# ========== 内部:工具 ==========

## 从 ability.serialize() 的 payload 推断初始 primary。
## stacks 直接读 payload.stacks;shield_remaining 扫 payload.components 找 ShieldComponent.current。
func _resolve_initial_primary(payload: Dictionary, primary_source: String) -> float:
	match primary_source:
		"stacks":
			return float(payload.get("stacks", 0))
		"shield_remaining":
			var components: Array = payload.get("components", [])
			for comp_variant in components:
				var comp: Dictionary = comp_variant
				if comp.get("type", "") == "ShieldComponent":
					var data: Dictionary = comp.get("data", {})
					return data.get("current", 0.0) as float
			return 0.0
		_:
			return 0.0
