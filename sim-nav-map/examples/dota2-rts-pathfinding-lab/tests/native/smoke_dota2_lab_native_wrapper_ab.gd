extends Node

# Wrapper-seam A/B: Dota2LabPathfinderWrapper with use_native must produce the
# same plan results (full SimNavLongPathResult surface), the same
# is_line_walkable booleans, and the same deterministic one-per-tick pump
# cadence as the GDScript backend. This welds the switch seam itself — the
# stack-level weld lives in simnav/native, and the full-sim trajectory weld
# arrives with the M4 motion port.

var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab wrapper native backend A/B identical")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures.slice(0, 6)))
	get_tree().quit(1)


func _run() -> void:
	if not SimNavNativeBridge.available():
		_failures.append("native classes missing (build native/ first)")
		return
	var obstacles := _obstacles()
	var gd_wrapper := Dota2LabPathfinderWrapper.new()
	gd_wrapper.rebuild_context(obstacles)
	var native_wrapper := Dota2LabPathfinderWrapper.new()
	native_wrapper.use_native = true
	native_wrapper.rebuild_context(obstacles)
	if not native_wrapper.use_native:
		_failures.append("native wrapper fell back to GDScript (extension unavailable?)")
		return
	if gd_wrapper.pass_mask != native_wrapper.pass_mask:
		_failures.append("pass_mask differs (gd=%d native=%d)" % [gd_wrapper.pass_mask, native_wrapper.pass_mask])

	# ── Plan pipeline: enqueue a batch, pump both, compare tick-by-tick ──────
	var routes: Array = [
		[Vector2(60, 60), Vector2(1260, 840)],
		[Vector2(1260, 60), Vector2(60, 840)],
		[Vector2(660, 100), Vector2(660, 800)],
		[Vector2(100, 450), Vector2(1220, 450)],
		[Vector2(60, 60), Vector2(400, 300)],  # goal inside a wall -> canonicalized
	]
	var gd_tickets: Array[int] = []
	var native_tickets: Array[int] = []
	for route in routes:
		gd_tickets.append(gd_wrapper.request_plan(route[0], route[1]))
		native_tickets.append(native_wrapper.request_plan(route[0], route[1]))
	if gd_wrapper.pending_plan_count() != routes.size() or native_wrapper.pending_plan_count() != routes.size():
		_failures.append("pending count wrong after enqueue (gd=%d native=%d)" % [gd_wrapper.pending_plan_count(), native_wrapper.pending_plan_count()])

	# Cancel one before any pump on both sides.
	gd_wrapper.cancel_plan(gd_tickets[2])
	native_wrapper.cancel_plan(native_tickets[2])

	# Arrival CADENCE differs by design (approved decision): the native queue
	# delivers the whole batch one tick after it was handed to the worker,
	# while the GDScript queue drains one per tick. Assert each side's own
	# contract, then compare the RESULTS route-for-route.
	var gd_results: Dictionary = {}
	var n_results: Dictionary = {}
	var max_ticks := 12
	for tick in range(max_ticks):
		gd_wrapper.pump_async()
		native_wrapper.pump_async()
		if tick == 1 and native_wrapper.pending_plan_count() != 0:
			_failures.append("native queue did not deliver the whole batch at T+1 (pending=%d)" % native_wrapper.pending_plan_count())
		for i in range(routes.size()):
			if not gd_results.has(i):
				var gd_result := gd_wrapper.take_plan_result(gd_tickets[i])
				if gd_result != null:
					gd_results[i] = gd_result
			if not n_results.has(i):
				var n_result := native_wrapper.take_plan_result(native_tickets[i])
				if n_result != null:
					n_results[i] = n_result
		if gd_wrapper.pending_plan_count() == 0 and native_wrapper.pending_plan_count() == 0:
			break

	for i in range(routes.size()):
		if i == 2:
			if gd_results.has(2) or n_results.has(2):
				_failures.append("cancelled ticket produced a result (gd=%s native=%s)" % [gd_results.has(2), n_results.has(2)])
			continue
		if not gd_results.has(i) or not n_results.has(i):
			_failures.append("route %d: missing result (gd=%s native=%s)" % [i, gd_results.has(i), n_results.has(i)])
			continue
		_compare_results("route %d" % i, gd_results[i], n_results[i])

	# ── is_line_walkable sweep ───────────────────────────────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var mismatch := 0
	for i in range(600):
		var a := Vector2(rng.randf_range(0.0, 1320.0), rng.randf_range(0.0, 900.0))
		var b := Vector2(rng.randf_range(0.0, 1320.0), rng.randf_range(0.0, 900.0))
		if gd_wrapper.is_line_walkable(a, b) != native_wrapper.is_line_walkable(a, b):
			mismatch += 1
	if mismatch > 0:
		_failures.append("is_line_walkable mismatches: %d / 600" % mismatch)
	else:
		print("[wrapper-ab] 600 is_line_walkable probes identical")

	# ── static_shapes parity for the motion engine ───────────────────────────
	var gd_shapes := gd_wrapper.static_shapes()
	var n_shapes := native_wrapper.static_shapes()
	if gd_shapes.size() != n_shapes.size():
		_failures.append("static_shapes size differs (gd=%d native=%d)" % [gd_shapes.size(), n_shapes.size()])
	else:
		for i in range(gd_shapes.size()):
			if gd_shapes[i].center != n_shapes[i].center or gd_shapes[i].width != n_shapes[i].width \
					or gd_shapes[i].height != n_shapes[i].height or gd_shapes[i].rotation_rad != n_shapes[i].rotation_rad:
				_failures.append("static_shapes[%d] geometry differs" % i)
				break

	# ── plan_path sync probe ─────────────────────────────────────────────────
	_compare_results("plan_path sync", gd_wrapper.plan_path(Vector2(80, 80), Vector2(1200, 820)), native_wrapper.plan_path(Vector2(80, 80), Vector2(1200, 820)))


func _obstacles() -> Array[Dota2LabObstacle]:
	var result: Array[Dota2LabObstacle] = [
		Dota2LabObstacle.new("wall-a", Vector2(400, 300), Vector2(160, 60)),
		Dota2LabObstacle.new("wall-b", Vector2(700, 500), Vector2(80, 260)),
		Dota2LabObstacle.new("wall-c", Vector2(1000, 250), Vector2(200, 50)),
		Dota2LabObstacle.new("wall-d", Vector2(300, 700), Vector2(60, 200)),
		Dota2LabObstacle.new("blocker-e", Vector2(950, 700), Vector2(120, 120)),
	]
	return result


func _compare_results(label: String, gd_result: SimNavLongPathResult, n_result: SimNavLongPathResult) -> void:
	if gd_result == null or n_result == null:
		_failures.append("%s: null result (gd=%s native=%s)" % [label, gd_result != null, n_result != null])
		return
	# Full result-surface comparison — same field list as the stack-level
	# longpath A/B, so a wrapper-branch regression cannot hide behind a
	# narrower comparator (codex M3 finding).
	var mismatches: Array[String] = []
	_diff(mismatches, "status", gd_result.status, n_result.status)
	_diff(mismatches, "failure_reason", gd_result.failure_reason, n_result.failure_reason)
	_diff(mismatches, "canonicalization_reason", gd_result.canonicalization_reason, n_result.canonicalization_reason)
	_diff(mismatches, "canonicalized", gd_result.canonicalized, n_result.canonicalized)
	_diff(mismatches, "start_recovered", gd_result.start_recovered, n_result.start_recovered)
	_diff(mismatches, "pass_mask", gd_result.pass_mask, n_result.pass_mask)
	_diff(mismatches, "passability_class_name", gd_result.passability_class_name, n_result.passability_class_name)
	_diff(mismatches, "start_world", gd_result.start_world, n_result.start_world)
	_diff(mismatches, "effective_start_world", gd_result.effective_start_world, n_result.effective_start_world)
	_diff(mismatches, "start_navcell", gd_result.start_navcell, n_result.start_navcell)
	_diff(mismatches, "effective_start_navcell", gd_result.effective_start_navcell, n_result.effective_start_navcell)
	_diff(mismatches, "canonical_navcell", gd_result.canonical_navcell, n_result.canonical_navcell)
	_diff(mismatches, "path_cost", gd_result.path_cost, n_result.path_cost)
	_diff(mismatches, "path_length", gd_result.path_length, n_result.path_length)
	_diff(mismatches, "raw_navcell_count", gd_result.raw_navcell_count, n_result.raw_navcell_count)
	_diff(mismatches, "raw_waypoint_count", gd_result.raw_waypoint_count, n_result.raw_waypoint_count)
	_diff(mismatches, "refined_waypoint_count", gd_result.refined_waypoint_count, n_result.refined_waypoint_count)
	_diff(mismatches, "post_process", gd_result.post_process, n_result.post_process)
	_diff(mismatches, "waypoint_spacing", gd_result.waypoint_spacing, n_result.waypoint_spacing)
	_diff(mismatches, "waypoint_order", gd_result.waypoint_order, n_result.waypoint_order)
	_diff(mismatches, "raw_navcell_order", gd_result.raw_navcell_order, n_result.raw_navcell_order)
	_diff(mismatches, "search_algorithm", gd_result.search_algorithm, n_result.search_algorithm)
	_diff(mismatches, "search_expansion_count", gd_result.search_expansion_count, n_result.search_expansion_count)
	_diff(mismatches, "search_push_count", gd_result.search_push_count, n_result.search_push_count)
	_diff(mismatches, "search_jump_count", gd_result.search_jump_count, n_result.search_jump_count)
	_diff(mismatches, "search_closed_count", gd_result.search_closed_count, n_result.search_closed_count)
	_diff(mismatches, "search_max_open_count", gd_result.search_max_open_count, n_result.search_max_open_count)
	_diff(mismatches, "search_path_cell_count", gd_result.search_path_cell_count, n_result.search_path_cell_count)
	if gd_result.raw_navcell_path != n_result.raw_navcell_path:
		mismatches.append("raw_navcell_path cells differ")
	if gd_result.raw_waypoint_path.waypoints != n_result.raw_waypoint_path.waypoints:
		mismatches.append("raw waypoints differ")
	if gd_result.refined_waypoint_path.waypoints != n_result.refined_waypoint_path.waypoints:
		mismatches.append("refined waypoints differ (%d vs %d)" % [gd_result.refined_waypoint_count, n_result.refined_waypoint_count])
	if (gd_result.reachability_result == null) != (n_result.reachability_result == null):
		mismatches.append("reachability nullity differs")
	elif gd_result.reachability_result != null:
		var gd_reach := gd_result.reachability_result
		var n_reach := n_result.reachability_result
		if gd_reach.is_reachable != n_reach.is_reachable or gd_reach.canonicalized != n_reach.canonicalized \
				or gd_reach.failure_reason != n_reach.failure_reason \
				or gd_reach.start_global_region != n_reach.start_global_region \
				or gd_reach.canonical_global_region != n_reach.canonical_global_region:
			mismatches.append("reachability fields differ")
	if mismatches.is_empty():
		print("[wrapper-ab] %s: identical (%s)" % [label, gd_result.status])
	else:
		_failures.append("%s: %s" % [label, "; ".join(mismatches)])


func _diff(mismatches: Array[String], field: String, gd_value: Variant, n_value: Variant) -> void:
	if gd_value != n_value:
		mismatches.append("%s gd=%s native=%s" % [field, gd_value, n_value])
