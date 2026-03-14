## EventProcessor - 事件处理器
##
## 统一处理 Pre/Post 双阶段事件，支持深度优先递归和追踪。
##
## 伪单例"模式 —— EventProcessor 实例存放在 GameWorld (Autoload) 中，通过 GameWorld.event_processor 全局访问
## EventProcessor 有状态（_current_depth, _traces, _pre_handlers），这些状态应该跟随 GameWorld 的生命周期，而不是独立存在
## GameWorld.init(EventProcessorConfig.new(20, 3))  # 可以重置
##
## ========== 核心职责 ==========
##
## 1. **Pre 阶段处理**：收集所有处理器的意图，应用修改，判断是否取消
## 2. **Post 阶段处理**：广播事件到所有监听者，深度优先处理被动产生的新事件
## 3. **追踪记录**：根据 trace_level 记录处理过程
## 4. **递归保护**：限制最大递归深度（默认 10）
##
## ========== 双阶段设计 ==========
##
## Pre 阶段（process_pre_event）：
## - 在效果应用**之前**调用
## - 允许被动技能修改或取消即将发生的效果
## - 返回 MutableEvent，包含修改后的值和取消状态
##
## Post 阶段（process_post_event）：
## - 在效果应用**之后**调用
## - 通过 GameWorld.get_actor() + IAbilitySetOwner 广播事件到所有存活角色
## - 可能触发被动技能（如反伤、吸血）产生新事件
##
## ========== 使用示例 ==========
##
## @example 在 Action 中使用双阶段处理
## ```gdscript
## var event_processor: EventProcessor = GameWorld.event_processor
## 
## # Pre 阶段：允许减伤/免疫
## var mutable: MutableEvent = event_processor.process_pre_event(pre_event, game_state_provider)
## 
## if not mutable.cancelled:
##     # 获取修改后的伤害值
##     var final_damage: float = mutable.get_current_value("damage")
##     
##     # 应用效果（原子操作）
##     ctx.event_collector.push(damage_event)
##     target.modify_hp(-final_damage)
##     
##     # Post 阶段：触发反伤/吸血等被动
##     var alive_actor_ids := game_state_provider.get_alive_actor_ids()
##     event_processor.process_post_event(damage_event, alive_actor_ids, game_state_provider)
## ```
##
## @example 查看追踪日志
## ```gdscript
## print(event_processor.export_trace_log())
## ```

class_name EventProcessor
extends RefCounted

var _config: EventProcessorConfig
var _current_depth := 0
var _traces: Array[Dictionary] = []
var _current_trace_id := ""
## 存储格式: { event_kind: Array[PreHandlerRegistration] }
var _pre_handlers: Dictionary = {}


## 初始化事件处理器
func _init(config: EventProcessorConfig = null):
	_config = config if config != null else EventProcessorConfig.new()


## 注册 Pre 阶段处理器
## @return 取消注册的 Callable
func register_pre_handler(registration: PreHandlerRegistration) -> Callable:
	var event_kind: String = registration.event_kind
	if not _pre_handlers.has(event_kind):
		_pre_handlers[event_kind] = [] as Array[PreHandlerRegistration]
	(_pre_handlers[event_kind] as Array[PreHandlerRegistration]).append(registration)

	return func() -> void:
		if not _pre_handlers.has(event_kind):
			return
		var handlers: Array[PreHandlerRegistration] = _pre_handlers[event_kind]
		for i in range(handlers.size()):
			if handlers[i].id == registration.id:
				handlers.remove_at(i)
				break


func remove_handlers_by_ability_id(ability_id: String) -> void:
	_remove_handlers_where(func(h: PreHandlerRegistration) -> bool: return h.ability_id == ability_id)


func remove_handlers_by_owner_id(owner_id: String) -> void:
	_remove_handlers_where(func(h: PreHandlerRegistration) -> bool: return h.owner_id == owner_id)


func _remove_handlers_where(should_remove: Callable) -> void:
	for event_kind in _pre_handlers.keys():
		var handlers: Array[PreHandlerRegistration] = _pre_handlers[event_kind] as Array[PreHandlerRegistration]
		var filtered: Array[PreHandlerRegistration] = []
		for handler in handlers:
			if not should_remove.call(handler):
				filtered.append(handler)
		_pre_handlers[event_kind] = filtered

## Pre 阶段处理：收集所有处理器的意图（修改/取消/放行），返回 MutableEvent。
##
## Handler 注册链路：
##   PreEventConfig → PreEventComponent.on_apply() → register_pre_handler() → _pre_handlers
##   PreEventComponent 在技能激活时将 handler 注册到 EventProcessor，
##   在技能移除时通过返回的 Callable 自动取消注册。
##   registration.call_handler(mutable, handler_context) 调用具体的 handler。
##
## 流程：
## 1. 创建 MutableEvent 包装原始事件数据
## 2. 按 event_kind 查找已注册的 PreHandlerRegistration 列表
## 3. 依次调用每个处理器，获取 Intent（意图）：
##    - pass_through → 跳过，继续下一个处理器
##    - cancel       → 标记事件取消，立即停止遍历
##    - modify       → 将修改（Modification）追加到 MutableEvent
## 4. 返回 MutableEvent，调用方通过 mutable.cancelled / mutable.get_current_value() 读取结果
func process_pre_event(event_dict: Dictionary, game_state_provider: Variant) -> MutableEvent:
	Log.assert_crash(game_state_provider != null, "EventProcessor", "game_state_provider is required")
	var mutable := MutableEvent.new(event_dict, EventPhase.PHASE_PRE)

	# ── 递归保护 ──
	if _current_depth >= _config.max_depth:
		var error_msg := "Event recursion depth exceeded: %s\nCurrent event: %s\nEvent call chain:\n%s" % [
			_current_depth,
			event_dict.get("kind", "unknown"),
			_get_event_chain_summary()
		]
		Log.error("EventProcessor", error_msg)
		return mutable

	# ── 追踪上下文：保存父级 trace_id，进入新的深度层 ──
	var trace := _create_trace(event_dict, EventPhase.PHASE_PRE)
	var parent_trace_id := _current_trace_id
	_current_depth += 1
	_current_trace_id = trace.get("traceId", "")

	# ── 查找处理器：按 event_kind 匹配已注册的 handler ──
	var event_kind: String = event_dict.get("kind", "")
	if not _pre_handlers.has(event_kind):
		_current_depth -= 1
		_current_trace_id = parent_trace_id
		_finalize_trace(trace)
		return mutable

	# ── 遍历处理器：依次调用，收集意图 ──
	var handlers: Array[PreHandlerRegistration] = _pre_handlers[event_kind]
	for registration in handlers:
		# 过滤：handler 可指定只处理特定条件的事件（如只处理对自己的伤害）
		if not registration.passes_filter(event_dict):
			continue

		var handler_context := HandlerContext.new(
			registration.owner_id,
			registration.ability_id,
			registration.config_id,
			game_state_provider
		)

		var start_time := Time.get_ticks_msec()

		# 调用处理器，返回 Intent（pass_through / cancel / modify）
		var intent := registration.call_handler(mutable, handler_context)

		var execution_time := Time.get_ticks_msec() - start_time
		
		if _config.trace_level >= 2:
			trace["intents"].append({
				"handlerId": registration.id,
				"handlerName": registration.get_display_name(),
				"intent": intent.to_dict(),
				"executionTime": execution_time,
			})

		# ── 处理意图 ──
		if intent.is_cancel():
			# cancel：标记事件取消，停止后续处理器
			mutable.cancel(intent.handler_id, intent.reason)
			trace["cancelled"] = true
			trace["cancelReason"] = intent.reason
			trace["cancelledBy"] = intent.handler_id
			break
		elif intent.is_modify():
			# modify：将修改追加到 MutableEvent，继续下一个处理器
			# 补充来源信息（source_id / source_name），方便追踪修改来源
			var modifications_with_source: Array[Modification] = []
			for mod in intent.modifications:
				if mod.source_id != "" and mod.source_name != "":
					modifications_with_source.append(mod)
				else:
					modifications_with_source.append(Modification.new(
						mod.field,
						mod.operation,
						mod.value,
						mod.source_id if mod.source_id != "" else intent.handler_id,
						mod.source_name if mod.source_name != "" else registration.get_display_name()
					))
			mutable.add_modifications(modifications_with_source)

	# ── 记录修改前后的值（用于 trace 日志）──
	if _config.trace_level >= 1:
		trace["originalValues"] = mutable.get_original_values()
		trace["finalValues"] = mutable.get_final_values()

	# ── 恢复追踪上下文 ──
	_current_depth -= 1
	_current_trace_id = parent_trace_id
	_finalize_trace(trace)

	return mutable

func process_post_event(event_dict: Dictionary, actor_ids: Array[String], game_state_provider: Variant) -> void:
	_process_post_event_impl(event_dict, actor_ids, {}, game_state_provider)

func process_post_event_to_related(event_dict: Dictionary, actor_ids: Array[String], related_actor_ids: Dictionary, game_state_provider: Variant) -> void:
	_process_post_event_impl(event_dict, actor_ids, related_actor_ids, game_state_provider)

## 内部实现：统一 Post 阶段处理逻辑
## related_filter 为空表示不过滤（广播给所有 actor_ids），非空表示只广播给 related 中的 actor
func _process_post_event_impl(event_dict: Dictionary, actor_ids: Array[String], related_filter: Dictionary, game_state_provider: Variant) -> void:
	Log.assert_crash(game_state_provider != null, "EventProcessor", "game_state_provider is required")
	if _current_depth >= _config.max_depth:
		var error_msg := "Event recursion depth exceeded: %s\nCurrent event: %s\nEvent call chain:\n%s" % [
			_current_depth,
			event_dict.get("kind", "unknown"),
			_get_event_chain_summary()
		]
		Log.error("EventProcessor", error_msg)
		return

	var trace := _create_trace(event_dict, EventPhase.PHASE_POST)
	var parent_trace_id := _current_trace_id
	_current_depth += 1
	_current_trace_id = trace.get("traceId", "")

	var filter_enabled := not related_filter.is_empty()
	for actor_id in actor_ids:
		if filter_enabled and not related_filter.has(actor_id):
			continue
		var actor: Actor = GameWorld.get_actor(actor_id)
		if actor == null:
			continue
		var ability_set := IAbilitySetOwner.get_ability_set(actor)
		Log.assert_crash(ability_set != null, "EventProcessor", "Actor '%s' in actor_ids must implement IAbilitySetOwner" % actor_id)
		ability_set.receive_event(event_dict, game_state_provider)

	_current_depth -= 1
	_current_trace_id = parent_trace_id
	_finalize_trace(trace)

func get_traces() -> Array[Dictionary]:
	return _traces

func clear_traces() -> void:
	_traces = []

func get_current_depth() -> int:
	return _current_depth

func get_current_trace_id() -> String:
	return _current_trace_id

func export_trace_log() -> String:
	if _traces.is_empty():
		return "(No traces recorded)"

	var lines: Array[String] = []
	for trace in _traces:
		lines.append("")
		lines.append("[Trace %s] %s (%s, depth: %s)" % [
			trace.get("traceId", ""),
			trace.get("eventKind", ""),
			trace.get("phase", ""),
			trace.get("depth", ""),
		])
		if trace.has("parentTraceId") and str(trace["parentTraceId"]) != "":
			lines.append("  Parent: %s" % trace["parentTraceId"])

		if trace.get("phase", "") == EventPhase.PHASE_PRE:
			var original_values: Dictionary = trace.get("originalValues", {})
			if not original_values.is_empty():
				lines.append("  Original: %s" % JSON.stringify(original_values))
			var intents: Array[Dictionary] = trace.get("intents", []) as Array[Dictionary]
			for record in intents:
				var intent: Dictionary = record.get("intent", {})
				var intent_type: String = intent.get("type", "")
				var has_error: bool = record.get("error", null) != null
				var error_suffix := " ERROR" if has_error else ""
				lines.append("  [%s] -> %s%s" % [record.get("handlerName", record.get("handlerId", "")), intent_type, error_suffix])
				if has_error:
					lines.append("    Error: %s" % record["error"].get("message", ""))
				elif intent_type == EventPhase.INTENT_CANCEL:
					lines.append("    Reason: %s" % intent.get("reason", ""))
				elif intent_type == EventPhase.INTENT_MODIFY:
					for mod in intent.get("modifications", []):
						lines.append("    %s: %s %s" % [mod.get("field", ""), mod.get("operation", ""), mod.get("value", "")])

			if trace.get("cancelled", false):
				lines.append("  CANCELLED by %s: %s" % [trace.get("cancelledBy", ""), trace.get("cancelReason", "")])
			else:
				var final_values: Dictionary = trace.get("finalValues", {})
				if not final_values.is_empty():
					lines.append("  Final: %s" % JSON.stringify(final_values))

		var duration := 0
		if trace.has("endTime") and trace.get("endTime", null) != null:
			duration = (trace.get("endTime", 0) as int) - (trace.get("startTime", 0) as int)
		lines.append("  Duration: %sms" % duration)

	return "\n".join(lines)

func _create_trace(event_dict: Dictionary, phase: String) -> Dictionary:
	var trace := {
		"traceId": EventPhase.create_trace_id(),
		"eventKind": event_dict.get("kind", ""),
		"phase": phase,
		"depth": _current_depth,
		"parentTraceId": _current_trace_id,
		"intents": [],
		"originalValues": {},
		"finalValues": {},
		"cancelled": false,
		"startTime": Time.get_ticks_msec(),
	}
	if _config.trace_level > 0:
		_traces.append(trace)
	return trace

func _finalize_trace(trace: Dictionary) -> void:
	trace["endTime"] = Time.get_ticks_msec()

## 获取事件调用链摘要（用于错误信息）
func _get_event_chain_summary() -> String:
	if _traces.is_empty():
		return "  (no trace available)"
	
	var lines: Array[String] = []
	# 只显示最近的事件链（最多 10 个）
	var start_idx := max(0, _traces.size() - 10)
	for i in range(start_idx, _traces.size()):
		var trace: Dictionary = _traces[i]
		var indent := "  " + "  ".repeat(trace.get("depth", 0) as int)
		var event_kind: String = trace.get("eventKind", "unknown")
		var phase: String = trace.get("phase", "")
		var trace_id: String = trace.get("traceId", "")
		lines.append("%s[%d] %s (%s) - trace_id: %s" % [indent, i, event_kind, phase, trace_id])
	
	return "\n".join(lines)
