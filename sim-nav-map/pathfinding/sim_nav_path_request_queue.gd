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


func _init(facade: SimNavPathfinderFacade = null, vertex_pathfinder: SimNavVertexPathfinder = null) -> void:
	_facade = facade
	_vertex_pathfinder = vertex_pathfinder


func enqueue_long_path(start_world: Vector2, goal: SimNavPathGoal, pass_mask: int) -> int:
	if goal == null:
		push_error("[SimNavPathRequestQueue] enqueue_long_path: goal is null")
		return 0
	var ticket := _allocate_ticket()
	_pending.append({
		"ticket": ticket,
		"kind": RequestKind.LONG,
		"start_world": start_world,
		"goal": _clone_goal(goal),
		"pass_mask": pass_mask,
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
		"request": _clone_short_request(request),
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
	if _in_worker.has(ticket_id):
		removed = true
	return removed


func process_budget(max_requests: int) -> int:
	if max_requests <= 0:
		return 0
	var processed := 0
	while processed < max_requests and not _pending.is_empty():
		var request: Dictionary = _pending[0]
		_pending.remove_at(0)
		var ticket_id := int(request["ticket"])
		if _cancelled.has(ticket_id):
			continue
		var path := _compute_request(request)
		if _cancelled.has(ticket_id):
			continue
		_results[ticket_id] = path
		processed += 1
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
	for result in worker_results:
		var result_dict := result as Dictionary
		var ticket_id := int(result_dict["ticket"])
		_in_worker.erase(ticket_id)
		if _cancelled.has(ticket_id):
			continue
		_results[ticket_id] = result_dict["path"] as SimNavWaypointPath
		collected += 1
	return collected


func has_result(ticket_id: int) -> bool:
	return _results.has(ticket_id)


func take_result(ticket_id: int) -> SimNavWaypointPath:
	if not _results.has(ticket_id):
		return null
	var path: SimNavWaypointPath = _results[ticket_id]
	_results.erase(ticket_id)
	return path


func pending_count() -> int:
	return _pending.size()


func result_count() -> int:
	return _results.size()


func clear() -> void:
	collect_worker_results(true)
	_pending.clear()
	_results.clear()
	_cancelled.clear()
	_in_worker.clear()


func _allocate_ticket() -> int:
	var ticket := _next_ticket
	_next_ticket += 1
	return ticket


func _compute_request(request: Dictionary) -> SimNavWaypointPath:
	var kind := int(request["kind"])
	if kind == RequestKind.LONG:
		if _facade == null:
			push_error("[SimNavPathRequestQueue] long request requires SimNavPathfinderFacade")
			return SimNavWaypointPath.new()
		var start_world: Vector2 = request["start_world"]
		var goal: SimNavPathGoal = request["goal"]
		var pass_mask := int(request["pass_mask"])
		return _facade.compute_path_immediate(start_world, goal, pass_mask)

	if kind == RequestKind.SHORT:
		if _vertex_pathfinder == null:
			push_error("[SimNavPathRequestQueue] short request requires SimNavVertexPathfinder")
			return SimNavWaypointPath.new()
		var short_request: SimNavShortPathRequest = request["request"]
		return _vertex_pathfinder.compute_short_path_immediate(short_request)

	push_error("[SimNavPathRequestQueue] unknown request kind: %d" % kind)
	return SimNavWaypointPath.new()


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
		worker_results.append({
			"ticket": int(request["ticket"]),
			"path": _compute_request(request),
		})
	return worker_results


func _clone_goal(goal: SimNavPathGoal) -> SimNavPathGoal:
	var cloned_goal := SimNavPathGoal.new(goal.type, goal.center)
	cloned_goal.hw = goal.hw
	cloned_goal.hh = goal.hh
	cloned_goal.u = goal.u
	cloned_goal.v = goal.v
	cloned_goal.maxdist = goal.maxdist
	return cloned_goal


func _clone_short_request(request: SimNavShortPathRequest) -> SimNavShortPathRequest:
	var cloned_request := SimNavShortPathRequest.new()
	cloned_request.start = request.start
	cloned_request.goal = _clone_goal(request.goal)
	cloned_request.clearance = request.clearance
	cloned_request.range_px = request.range_px
	cloned_request.pass_mask = request.pass_mask
	cloned_request.avoid_moving_units = request.avoid_moving_units
	cloned_request.control_group = request.control_group
	return cloned_request
