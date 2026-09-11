## EventProcessor - 事件处理器
##
## 统一处理 Pre/Post 双阶段事件，支持深度优先递归和追踪。
##
## 每个 GameplayInstance 持有自己的 EventProcessor（`instance.event_processor`）：
## 有状态（_current_depth, _traces, pre / post handler 注册表, owner 派发序号），这些状态跟随所属 instance 的生命周期，两个 instance 的 handler 互不可见。
## 配置经 instance 构造形参传入（`GameplayInstance.new(id, EventProcessorConfig.new(max_depth))` / 子类 `super._init(id, config)`）；
## 调试时对已有 processor 调 `set_trace_level(1)` 开始记录事件链。
## 不持有 instance / Ability / Component 的引用（handler 闭包只捕获 id），instance → processor 是单向强边。
##
## ========== 核心职责 ==========
##
## 1. **Pre 阶段处理**：收集所有处理器的意图，应用修改，判断是否取消
## 2. **Post 阶段处理**：派发给订阅了该 kind 的处理器，深度优先处理被动产生的新事件
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
## - 观众由注册决定：Ability 在 apply_effects 时按 component 的 trigger kind 订阅，remove_effects 时退订
## - 死活由 actor 决定：handler 重建 context 前问 owner 的 is_event_responsive(event_dict, "post")
## - 可能触发被动技能（如反伤、吸血）产生新事件
##
## 定向投递（DIRECT_DELIVERY_KINDS：激活请求 / grant 自投递）不走 post 派发，由 AbilitySet.receive_event 投给单个 actor。
##
## ========== 使用示例 ==========
##
## @example 在 Action 中使用双阶段处理
## ```gdscript
## var battle := HexBattleGameStateUtils.world(ctx)  # 项目层 helper：必须有世界
## var event_processor := battle.event_processor
##
## # Pre 阶段：允许减伤/免疫
## var mutable: MutableEvent = event_processor.process_pre_event(pre_event)
##
## if not mutable.cancelled:
##     # 获取修改后的伤害值
##     var final_damage: float = mutable.get_current_value("damage")
##
##     # 应用效果（原子操作）
##     ctx.event_collector.push(damage_event)
##     target.modify_hp(-final_damage)
##
##     # Post 阶段：触发反伤/吸血等被动（被击杀的目标是否仍响应由它的 is_event_responsive 决定）
##     event_processor.process_post_event(damage_event)
## ```
##
## @example 查看追踪日志
## ```gdscript
## print(event_processor.export_trace_log())
## ```

class_name EventProcessor
extends RefCounted

## 定向投递的 kind：激活请求与 grant 自投递由 AbilitySet.receive_event 投给单个 actor 的全部 ability。
## 永不注册 post handler，也不许传给 process_post_event——两条路都走就是双投递。
const DIRECT_DELIVERY_KINDS: Array[String] = [GameEvent.ABILITY_ACTIVATE_EVENT, GameEvent.ABILITY_GRANTED_EVENT]

## 没经 note_actor_added 登记的 owner（孤立使用 processor 的测试）排在所有已登记 owner 之后。
const _UNLISTED_OWNER_SEQ := 9223372036854775807

var _config: EventProcessorConfig
var _current_depth := 0
var _traces: Array[Dictionary] = []
var _current_trace_id := ""
## 存储格式: { event_kind: Array[PreHandlerRegistration] }
var _pre_handlers: Dictionary = {}
## 存储格式: { event_kind: Array[PostHandlerRegistration] }，按 (owner_seq, seq) 升序
var _post_handlers: Dictionary = {}
## 存储格式: { owner_id: int }，owner 进 registry 的顺序
var _owner_seq: Dictionary = {}
var _next_owner_seq := 0
var _next_post_seq := 0


## 初始化事件处理器
func _init(config: EventProcessorConfig = null):
	_config = config if config != null else EventProcessorConfig.new()


## 调整追踪级别（调试用：递归超限报错里的事件链摘要取自 trace）。改的是本 processor 持有的 config 对象。
func set_trace_level(level: int) -> void:
	_config.trace_level = level


## owner 进 registry（GameplayInstance.add_actor 调）：登记它在 post 派发里的先后。
func note_actor_added(actor_id: String) -> void:
	_owner_seq[actor_id] = _next_owner_seq
	_next_owner_seq += 1


## owner 离开 registry（GameplayInstance.remove_actor 调）：注销它的 pre / post handler 与派发序号。
func note_actor_removed(actor_id: String) -> void:
	remove_handlers_by_owner_id(actor_id)
	_owner_seq.erase(actor_id)


## 注册 Pre 阶段处理器
## @return 取消注册的 Callable（按 id 注销、幂等；只捕获 kind 与 id，不延长 registration 的寿命）
func register_pre_handler(registration: PreHandlerRegistration) -> Callable:
	var event_kind: String = registration.event_kind
	if not _pre_handlers.has(event_kind):
		_pre_handlers[event_kind] = [] as Array[PreHandlerRegistration]
	(_pre_handlers[event_kind] as Array[PreHandlerRegistration]).append(registration)

	var registration_id := registration.id
	return func() -> void:
		if not _pre_handlers.has(event_kind):
			return
		var handlers: Array[PreHandlerRegistration] = _pre_handlers[event_kind]
		for i in range(handlers.size()):
			if handlers[i].id == registration_id:
				handlers.remove_at(i)
				break


## 注册 Post 阶段处理器，按 (owner_seq, seq) 插入：派发顺序 = owner 进 registry 的顺序 → 注册顺序
## （同一 ability 的多个 component 由 Ability.receive_event 按 component 顺序处理）。
## @return 取消注册的 Callable（按 id 注销、幂等；只捕获 kind 与 id，不延长 registration 的寿命）
func register_post_handler(registration: PostHandlerRegistration) -> Callable:
	var event_kind := registration.event_kind
	if DIRECT_DELIVERY_KINDS.has(event_kind):
		Log.assert_crash(false, "EventProcessor",
			"'%s' 是定向投递 kind，只经 AbilitySet.receive_event 投递，不能注册 post handler" % event_kind)
		return func() -> void: pass
	registration.owner_seq = _owner_seq.get(registration.owner_id, _UNLISTED_OWNER_SEQ)
	registration.seq = _next_post_seq
	_next_post_seq += 1
	if not _post_handlers.has(event_kind):
		_post_handlers[event_kind] = [] as Array[PostHandlerRegistration]
	var handlers: Array[PostHandlerRegistration] = _post_handlers[event_kind]
	# seq 单调递增：插入点只需越过尾部 owner_seq 更大的那些
	var index := handlers.size()
	while index > 0 and handlers[index - 1].owner_seq > registration.owner_seq:
		index -= 1
	handlers.insert(index, registration)

	var registration_id := registration.id
	return func() -> void:
		if not _post_handlers.has(event_kind):
			return
		var registered: Array[PostHandlerRegistration] = _post_handlers[event_kind]
		for i in range(registered.size()):
			if registered[i].id == registration_id:
				registered.remove_at(i)
				break


func remove_handlers_by_ability_id(ability_id: String) -> void:
	_remove_handlers_where(func(_handler_owner_id: String, handler_ability_id: String) -> bool:
		return handler_ability_id == ability_id)


func remove_handlers_by_owner_id(owner_id: String) -> void:
	_remove_handlers_where(func(handler_owner_id: String, _handler_ability_id: String) -> bool:
		return handler_owner_id == owner_id)


## 清空 pre / post 两张注册表（GameplayInstance.end() 调）。owner 的派发序号跟 registry 走，不在这里清。
func remove_all_handlers() -> void:
	_pre_handlers.clear()
	_post_handlers.clear()


## 同时清 pre / post 两张表。should_remove: func(owner_id: String, ability_id: String) -> bool。
## 换新数组而非原地删：进行中的 pre 派发遍历的是旧数组，不会跳元素。
func _remove_handlers_where(should_remove: Callable) -> void:
	for event_kind: String in _pre_handlers.keys():
		var kept_pre: Array[PreHandlerRegistration] = []
		for registration: PreHandlerRegistration in _pre_handlers[event_kind]:
			if not should_remove.call(registration.owner_id, registration.ability_id):
				kept_pre.append(registration)
		_pre_handlers[event_kind] = kept_pre
	for event_kind: String in _post_handlers.keys():
		var kept_post: Array[PostHandlerRegistration] = []
		for registration: PostHandlerRegistration in _post_handlers[event_kind]:
			if not should_remove.call(registration.owner_id, registration.ability_id):
				kept_post.append(registration)
		_post_handlers[event_kind] = kept_post

## Pre 阶段处理：收集所有处理器的意图（修改/取消/放行），返回 MutableEvent。
##
## Handler 注册链路：
##   PreEventConfig → PreEventComponent.on_apply() → register_pre_handler() → _pre_handlers
##   PreEventComponent 在技能激活时将 handler 注册到 EventProcessor，
##   在技能移除时通过返回的 Callable 自动取消注册。
##   registration.call_handler(mutable) 以注册时建好的 HandlerContext 调用具体的 handler。
##
## 流程：
## 1. 创建 MutableEvent 包装原始事件数据
## 2. 按 event_kind 查找已注册的 PreHandlerRegistration 列表
## 3. 依次调用每个处理器，获取 Intent（意图）：
##    - pass_through → 跳过，继续下一个处理器
##    - cancel       → 标记事件取消，立即停止遍历
##    - modify       → 将修改（Modification）追加到 MutableEvent
## 4. 返回 MutableEvent，调用方通过 mutable.cancelled / mutable.get_current_value() 读取结果
func process_pre_event(event_dict: Dictionary) -> MutableEvent:
	var mutable := MutableEvent.new(event_dict, EventPhase.PHASE_PRE)

	# ── 递归保护 ──
	if _depth_exceeded(event_dict):
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

		var start_time := Time.get_ticks_msec()

		# 调用处理器，返回 Intent（pass_through / cancel / modify）
		var intent := registration.call_handler(mutable)

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

## Post 阶段派发：依次调用订阅了该 kind 的处理器（顺序 = owner 进 registry 的顺序 → 注册顺序）。
##
## 观众由注册决定、死活由 actor 决定：Ability 注册的 handler 按 id 重建 context，owner 此刻不响应这条事件
## （is_event_responsive 返回 false）或 ability 已不在 owner 的 AbilitySet 里时，本条不执行。
## 遍历注册表的快照：派发中新注册的 handler 收不到进行中的这条事件。
## 定向投递 kind 不许走这里（见 DIRECT_DELIVERY_KINDS）。
func process_post_event(event_dict: Dictionary) -> void:
	var event_kind: String = event_dict.get("kind", "")
	if DIRECT_DELIVERY_KINDS.has(event_kind):
		Log.assert_crash(false, "EventProcessor",
			"'%s' 是定向投递 kind，只经 AbilitySet.receive_event 投递，不走 process_post_event" % event_kind)
		return
	if _depth_exceeded(event_dict):
		return

	var trace := _create_trace(event_dict, EventPhase.PHASE_POST)
	var parent_trace_id := _current_trace_id
	_current_depth += 1
	_current_trace_id = trace.get("traceId", "")

	if _post_handlers.has(event_kind):
		var handlers: Array[PostHandlerRegistration] = []
		handlers.assign(_post_handlers[event_kind])
		var records: Array[Dictionary] = []
		for registration in handlers:
			if _config.trace_level < 2:
				registration.call_handler(event_dict)
				continue
			var start_time := Time.get_ticks_msec()
			var triggered := registration.call_handler(event_dict)
			records.append({
				"handlerId": registration.id,
				"handlerName": registration.get_display_name(),
				"triggered": triggered,
				"executionTime": Time.get_ticks_msec() - start_time,
			})
		if not records.is_empty():
			trace["handlers"] = records

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
		else:
			var handler_records: Array = trace.get("handlers", [])
			for record: Dictionary in handler_records:
				lines.append("  [%s] -> %s" % [
					record.get("handlerName", record.get("handlerId", "")),
					"triggered" if record.get("triggered", false) else "not triggered",
				])

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

## 递归深度已到上限：报错并返回 true，调用方随即放弃本次处理。
func _depth_exceeded(event_dict: Dictionary) -> bool:
	if _current_depth < _config.max_depth:
		return false
	var error_msg := "Event recursion depth exceeded: %s\nCurrent event: %s\nEvent call chain:\n%s" % [
		_current_depth,
		event_dict.get("kind", "unknown"),
		_get_event_chain_summary()
	]
	Log.error("EventProcessor", error_msg)
	return true

## 获取事件调用链摘要（用于错误信息）
func _get_event_chain_summary() -> String:
	if _traces.is_empty():
		# trace_level 默认 0（不累积 trace），所以这里通常是空的。
		# 事件链是排查事件循环的主要线索，提示怎么把它打开。
		return "  (no trace available; 重跑前对所属 instance 调 event_processor.set_trace_level(1) 以记录事件链)"

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
