class_name SimNavPathRequestQueue
extends RefCounted


enum RequestKind {
	LONG,
	SHORT,
}

var _facade: SimNavPathfinderFacade = null
var _vertex_pathfinder: SimNavVertexPathfinder = null
var _next_ticket := 1
var _pending: Array[Dictionary] = []
var _results: Dictionary = {}
var _cancelled: Dictionary = {}
var _in_worker: Dictionary = {}
var _worker_thread: Thread = null
var _processed_count: int = 0
var _cancelled_count: int = 0
var _stale_result_count: int = 0
var _worker_batch_count: int = 0
var _worker_collected_count: int = 0
var _last_batch_size: int = 0
var _last_process_budget_usec: int = 0
var _last_process_elapsed_usec: int = 0
var _last_processed_tickets: Array[int] = []
var _last_collected_tickets: Array[int] = []
var _last_processed_requests: Array[Dictionary] = []
var _last_collected_requests: Array[Dictionary] = []


func _init(facade: SimNavPathfinderFacade = null, vertex_pathfinder: SimNavVertexPathfinder = null) -> void:
	_facade = facade
	_vertex_pathfinder = vertex_pathfinder


func enqueue_long_path(start_world: Vector2, goal: SimNavPathGoal, pass_mask: int) -> int:
	return enqueue_long_path_query(SimNavLongPathQuery.from_values(start_world, goal, pass_mask))


func enqueue_long_path_query(query: SimNavLongPathQuery) -> int:
	if query == null or query.goal == null:
		push_error("[SimNavPathRequestQueue] enqueue_long_path_query: query or goal is null")
		return 0
	var ticket := _allocate_ticket()
	_pending.append({
		"ticket": ticket,
		"kind": RequestKind.LONG,
		"query": query.clone(),
	})
	return ticket


func enqueue_short_path(request: SimNavShortPathRequest) -> int:
	if request == null or request.goal == null:
		push_error("[SimNavPathRequestQueue] enqueue_short_path: request or goal is null")
		return 0
	var ticket := _allocate_ticket()
	_pending.append({
		"ticket": ticket,
		"kind": RequestKind.SHORT,
		"request": request.clone(),
	})
	return ticket


func cancel(ticket_id: int) -> bool:
	if ticket_id <= 0:
		return false
	_cancelled[ticket_id] = true
	var removed := false
	for i in range(_pending.size() - 1, -1, -1):
		var pending_request: Dictionary = _pending[i]
		if int(pending_request["ticket"]) == ticket_id:
			_pending.remove_at(i)
			removed = true
	if _results.erase(ticket_id):
		removed = true
		_stale_result_count += 1
	if _in_worker.has(ticket_id):
		removed = true
	if removed:
		_cancelled_count += 1
	return removed


func process_budget(max_requests: int, max_usec: int = 0) -> int:
	_last_process_budget_usec = max_usec
	_last_process_elapsed_usec = 0
	if max_requests <= 0:
		return 0
	var processed := 0
	var budget_start_usec := Time.get_ticks_usec()
	_last_processed_tickets.clear()
	_last_processed_requests.clear()
	while processed < max_requests and not _pending.is_empty():
		var request: Dictionary = _pending[0]
		_pending.remove_at(0)
		var ticket_id := int(request["ticket"])
		if _cancelled.has(ticket_id):
			continue
		var kind := int(request["kind"])
		var compute_start_usec := Time.get_ticks_usec()
		var result = _compute_request(request)
		var compute_usec := Time.get_ticks_usec() - compute_start_usec
		if _cancelled.has(ticket_id):
			_stale_result_count += 1
			continue
		_results[ticket_id] = result
		_processed_count += 1
		_last_processed_tickets.append(ticket_id)
		var diagnostic := {
			"ticket": ticket_id,
			"kind": _request_kind_name(kind),
			"compute_usec": compute_usec,
		}
		_merge_result_diagnostics(diagnostic, result)
		_last_processed_requests.append(diagnostic)
		processed += 1
		_last_process_elapsed_usec = Time.get_ticks_usec() - budget_start_usec
		if max_usec > 0 and _last_process_elapsed_usec >= max_usec:
			break
	return processed


func start_worker(max_requests: int = 0) -> int:
	if is_worker_running():
		return 0
	var batch := _take_worker_batch(max_requests)
	if batch.is_empty():
		return 0
	_worker_thread = Thread.new()
	var err := _worker_thread.start(Callable(self, "_compute_worker_batch").bind(batch))
	if err != OK:
		_worker_thread = null
		for i in range(batch.size() - 1, -1, -1):
			_pending.insert(0, batch[i])
		push_error("[SimNavPathRequestQueue] failed to start worker thread: %d" % err)
		return 0
	_worker_batch_count += 1
	_last_batch_size = batch.size()
	return batch.size()


func is_worker_running() -> bool:
	return _worker_thread != null and _worker_thread.is_alive()


func collect_worker_results(block: bool = false) -> int:
	if _worker_thread == null:
		return 0
	if not block and _worker_thread.is_alive():
		return 0
	var worker_results: Array = _worker_thread.wait_to_finish()
	_worker_thread = null
	var collected := 0
	_last_collected_tickets.clear()
	_last_collected_requests.clear()
	for result in worker_results:
		var result_dict := result as Dictionary
		var ticket_id := int(result_dict["ticket"])
		_in_worker.erase(ticket_id)
		if _cancelled.has(ticket_id):
			_stale_result_count += 1
			continue
		_results[ticket_id] = result_dict["result"]
		_worker_collected_count += 1
		_last_collected_tickets.append(ticket_id)
		_last_collected_requests.append(result_dict.get("diagnostic", {}) as Dictionary)
		collected += 1
	return collected


func has_result(ticket_id: int) -> bool:
	return _results.has(ticket_id)


func take_result(ticket_id: int) -> SimNavWaypointPath:
	if not _results.has(ticket_id):
		return null
	var stored_result = _results[ticket_id]
	_results.erase(ticket_id)
	if stored_result is SimNavLongPathResult:
		return (stored_result as SimNavLongPathResult).path
	if stored_result is SimNavShortPathResult:
		return (stored_result as SimNavShortPathResult).path
	return stored_result as SimNavWaypointPath


func take_long_path_result(ticket_id: int) -> SimNavLongPathResult:
	if not _results.has(ticket_id):
		return null
	var stored_result = _results[ticket_id]
	_results.erase(ticket_id)
	if stored_result is SimNavLongPathResult:
		return stored_result as SimNavLongPathResult
	return null


func take_short_path_result(ticket_id: int) -> SimNavShortPathResult:
	if not _results.has(ticket_id):
		return null
	var stored_result = _results[ticket_id]
	_results.erase(ticket_id)
	if stored_result is SimNavShortPathResult:
		return stored_result as SimNavShortPathResult
	return null


func pending_count() -> int:
	return _pending.size()


func result_count() -> int:
	return _results.size()


func pending_tickets() -> Array[int]:
	var result: Array[int] = []
	for request in _pending:
		var request_dict := request as Dictionary
		result.append(int(request_dict["ticket"]))
	return result


func result_tickets() -> Array[int]:
	var result: Array[int] = []
	for ticket in _results.keys():
		result.append(int(ticket))
	result.sort()
	return result


func get_diagnostics() -> Dictionary:
	return {
		"next_ticket": _next_ticket,
		"pending_count": pending_count(),
		"pending_tickets": pending_tickets(),
		"result_count": result_count(),
		"result_tickets": result_tickets(),
		"cancelled_ticket_count": _cancelled.size(),
		"in_worker_count": _in_worker.size(),
		"worker_running": is_worker_running(),
		"processed_count": _processed_count,
		"cancelled_count": _cancelled_count,
		"stale_result_count": _stale_result_count,
		"worker_batch_count": _worker_batch_count,
		"worker_collected_count": _worker_collected_count,
		"last_batch_size": _last_batch_size,
		"last_process_budget_usec": _last_process_budget_usec,
		"last_process_elapsed_usec": _last_process_elapsed_usec,
		"last_processed_tickets": _last_processed_tickets.duplicate(),
		"last_collected_tickets": _last_collected_tickets.duplicate(),
		"last_processed_requests": _last_processed_requests.duplicate(true),
		"last_collected_requests": _last_collected_requests.duplicate(true),
	}


func clear() -> void:
	collect_worker_results(true)
	_pending.clear()
	_results.clear()
	_cancelled.clear()
	_in_worker.clear()
	_last_batch_size = 0
	_last_process_budget_usec = 0
	_last_process_elapsed_usec = 0
	_last_processed_tickets.clear()
	_last_collected_tickets.clear()
	_last_processed_requests.clear()
	_last_collected_requests.clear()


func _allocate_ticket() -> int:
	var ticket := _next_ticket
	_next_ticket += 1
	return ticket


func _compute_request(request: Dictionary):
	var kind := int(request["kind"])
	if kind == RequestKind.LONG:
		if _facade == null:
			push_error("[SimNavPathRequestQueue] long request requires SimNavPathfinderFacade")
			var missing_result := SimNavLongPathResult.new()
			missing_result.set_failure(SimNavLongPathResult.STATUS_INVALID_QUERY, SimNavLongPathResult.FAILURE_NAV_MAP_MISSING)
			return missing_result
		var query: SimNavLongPathQuery = request["query"]
		return _facade.compute_path_result(query)

	if kind == RequestKind.SHORT:
		if _vertex_pathfinder == null:
			push_error("[SimNavPathRequestQueue] short request requires SimNavVertexPathfinder")
			var missing_short_result := SimNavShortPathResult.new()
			missing_short_result.set_failure(SimNavShortPathResult.STATUS_INVALID_QUERY, SimNavShortPathResult.FAILURE_NAV_MAP_MISSING)
			return missing_short_result
		var short_request: SimNavShortPathRequest = request["request"]
		return _vertex_pathfinder.compute_short_path_result(short_request)

	push_error("[SimNavPathRequestQueue] unknown request kind: %d" % kind)
	return SimNavWaypointPath.new()


func _request_kind_name(request_kind: int) -> String:
	match request_kind:
		RequestKind.LONG:
			return "long"
		RequestKind.SHORT:
			return "short"
		_:
			return "unknown"


func _take_worker_batch(max_requests: int) -> Array[Dictionary]:
	var batch: Array[Dictionary] = []
	var limit := max_requests
	if limit <= 0:
		limit = _pending.size()
	while batch.size() < limit and not _pending.is_empty():
		var request: Dictionary = _pending[0]
		_pending.remove_at(0)
		var ticket_id := int(request["ticket"])
		if _cancelled.has(ticket_id):
			continue
		_in_worker[ticket_id] = true
		batch.append(request)
	return batch


func _compute_worker_batch(batch: Array[Dictionary]) -> Array[Dictionary]:
	var worker_results: Array[Dictionary] = []
	for request in batch:
		var compute_start_usec := Time.get_ticks_usec()
		var request_result = _compute_request(request)
		var kind := int(request["kind"])
		worker_results.append({
			"ticket": int(request["ticket"]),
			"result": request_result,
			"diagnostic": _request_diagnostic(
				int(request["ticket"]),
				kind,
				Time.get_ticks_usec() - compute_start_usec,
				request_result
			),
		})
	return worker_results


func _request_diagnostic(ticket_id: int, kind: int, compute_usec: int, result) -> Dictionary:
	var diagnostic := {
		"ticket": ticket_id,
		"kind": _request_kind_name(kind),
		"compute_usec": compute_usec,
	}
	_merge_result_diagnostics(diagnostic, result)
	return diagnostic


func _merge_result_diagnostics(diagnostic: Dictionary, result) -> void:
	if result is SimNavShortPathResult:
		var short_result := result as SimNavShortPathResult
		diagnostic["status"] = short_result.status
		diagnostic["failure_reason"] = short_result.failure_reason
		diagnostic["path_size"] = short_result.path.size()
		var graph_diagnostics := short_result.graph_diagnostics()
		for key in graph_diagnostics.keys():
			diagnostic[key] = graph_diagnostics[key]
	elif result is SimNavLongPathResult:
		var long_result := result as SimNavLongPathResult
		diagnostic["status"] = long_result.status
		diagnostic["failure_reason"] = long_result.failure_reason
		diagnostic["path_size"] = long_result.path.size()
