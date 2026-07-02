extends Node

# M5 weld: the background-worker queue must deliver results identical to
# synchronous facade computation, on a deterministic fixed-latency schedule,
# with safe main-thread reads while a batch is in flight, correct cancel /
# dirty-map-guard semantics, and run-to-run determinism.

const MAP_W := 165
const MAP_H := 113
const CELL := 8.0
const BLOCK_PATHFINDING := 8

var _failures: Array[String] = []
var _nmap: Object = null
var _nfacade: Object = null
var _ground_mask := 0
var _large_mask := 0


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - native background queue deterministic and sync-identical")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures.slice(0, 5)))
	get_tree().quit(1)


func _run() -> void:
	if not ClassDB.class_exists("SimNavNativeQueue"):
		_failures.append("SimNavNativeQueue missing (build native/ first)")
		return
	_build_fixture()

	var queue: Object = ClassDB.instantiate("SimNavNativeQueue")
	queue.call("setup", _nfacade)
	var supported := bool(queue.call("worker_supported"))
	print("[m5] worker_supported=%s" % supported)
	if OS.get_name() == "Windows" and not supported:
		_failures.append("worker must be supported on Windows")
		return

	# ── Batch results == synchronous facade results, twice (determinism) ─────
	var queries := _query_batch(30)
	var first_round: Array = []
	for round_index in range(2):
		var tickets: Array[int] = []
		for query in queries:
			tickets.append(int(queue.call("enqueue", query)))
		queue.call("begin_tick")
		# Main-thread reads while the worker computes (concurrency stress).
		var line_checks := 0
		for i in range(3000):
			_nfacade.call("movement_line_clear", Vector2(20 + (i % 40) * 30.0, 30.0), Vector2(1200.0, 800.0 - (i % 25) * 30.0), 12.0, _ground_mask, {})
			line_checks += 1
		var collected := int(queue.call("collect"))
		if collected != queries.size():
			_failures.append("round %d: collected %d of %d" % [round_index, collected, queries.size()])
			return
		var round_results: Array = []
		for i in range(tickets.size()):
			var result: Dictionary = queue.call("take_result", tickets[i])
			if result.is_empty():
				_failures.append("round %d: missing result %d" % [round_index, i])
				return
			round_results.append(result)
		if round_index == 0:
			first_round = round_results
			for i in range(queries.size()):
				var sync_result: Dictionary = _nfacade.call("compute_path_result", queries[i])
				if not _dicts_equal(sync_result, round_results[i]):
					_failures.append("query %d: worker result differs from synchronous compute" % i)
					return
			print("[m5] 30 worker results == synchronous compute (with %d concurrent line checks)" % line_checks)
		else:
			for i in range(queries.size()):
				if not _dicts_equal(first_round[i], round_results[i]):
					_failures.append("determinism: round 2 result %d differs from round 1" % i)
					return
			print("[m5] round 2 identical to round 1 (run-to-run determinism)")

	# ── In-flight frozen guards (concurrency contract, loudly enforced) ──────
	var frozen_batch := _query_batch(100)
	for query in frozen_batch:
		queue.call("enqueue", query)
	queue.call("begin_tick")
	print("[m5] frozen guards: expected native errors follow")
	var cell_probe := Vector2i(5, 5)
	var before := int(_nmap.call("get_navcell_data", cell_probe))
	_nmap.call("or_navcell_data", cell_probe, _ground_mask)
	if int(_nmap.call("get_navcell_data", cell_probe)) != before:
		_failures.append("map mutation went through while a batch was in flight")
	var flush_out: Dictionary = _nfacade.call("recompute_dirty", PackedInt32Array([_ground_mask]), true)
	if not flush_out.is_empty():
		_failures.append("recompute_dirty went through while a batch was in flight")
	var open_a := Vector2(30, 860)
	var open_b := Vector2(300, 860)
	var frozen_ground := bool(_nfacade.call("movement_line_clear", open_a, open_b, 12.0, _ground_mask, {}))
	var frozen_large := bool(_nfacade.call("movement_line_clear", open_a, open_b, 20.0, _large_mask, {}))
	if frozen_large:
		_failures.append("unbuilt-mask line check must be refused (false) while a batch is in flight")
	queue.call("collect")
	var thawed_ground := bool(_nfacade.call("movement_line_clear", open_a, open_b, 12.0, _ground_mask, {}))
	var thawed_large := bool(_nfacade.call("movement_line_clear", open_a, open_b, 20.0, _large_mask, {}))
	if frozen_ground != thawed_ground:
		_failures.append("prewarmed-mask line check changed across freeze (frozen=%s thawed=%s)" % [frozen_ground, thawed_ground])
	if not thawed_large:
		_failures.append("unbuilt-mask line check should build lazily and pass after collect")
	if not _failures.is_empty():
		return
	print("[m5] frozen guards ok (map edit + flush refused, unbuilt mask read-only refused, prewarmed mask served)")
	queue.call("clear")

	# ── Cancel semantics: pre-begin and mid-flight ───────────────────────────
	var t_keep := int(queue.call("enqueue", queries[0]))
	var t_pre := int(queue.call("enqueue", queries[1]))
	if not bool(queue.call("cancel", t_pre)):
		_failures.append("cancel of a pending ticket must return true")
	queue.call("begin_tick")
	var t_late := int(queue.call("enqueue", queries[2]))  # pending behind the in-flight batch
	if not bool(queue.call("cancel", t_late)):
		_failures.append("cancel of a queued-behind ticket must return true")
	if not bool(queue.call("cancel", t_keep)):
		_failures.append("cancel of an in-flight ticket must return true")
	if bool(queue.call("cancel", 999999)):
		_failures.append("cancel of an unknown ticket must return false")
	queue.call("collect")
	if bool(queue.call("has_result", t_keep)) or bool(queue.call("has_result", t_pre)):
		_failures.append("cancelled tickets must not deliver results")
		return
	print("[m5] cancel semantics ok (pre-begin true, in-flight true, queued true, unknown false)")
	queue.call("clear")

	# ── Dirty-map guard: synchronous fallback with an error, results intact ──
	_nmap.call("or_navcell_data", Vector2i(80, 40), _ground_mask)
	var guard_ticket := int(queue.call("enqueue", queries[3]))
	print("[m5] dirty-map guard: expected native error follows")
	queue.call("begin_tick")
	queue.call("collect")
	var diagnostics: Dictionary = queue.call("get_diagnostics")
	if int(diagnostics.get("sync_fallback_count", 0)) != 1:
		_failures.append("dirty-map begin_tick must take the synchronous fallback (count=%s)" % diagnostics.get("sync_fallback_count"))
		return
	var guard_result: Dictionary = queue.call("take_result", guard_ticket)
	var guard_reference: Dictionary = _nfacade.call("compute_path_result", queries[3])
	if not _dicts_equal(guard_result, guard_reference):
		_failures.append("dirty-map fallback result differs from synchronous compute")
		return
	_nmap.call("and_navcell_data", Vector2i(80, 40), _ground_mask)
	_nfacade.call("recompute_dirty", PackedInt32Array([_ground_mask]), true)
	print("[m5] dirty-map guard ok (sync fallback, correct result)")

	# ── Overlap perf: main-thread work hides the batch compute ──────────────
	var heavy := _query_batch(100)
	for query in heavy:
		queue.call("enqueue", query)
	queue.call("begin_tick")
	var busy_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - busy_start < 10000:
		_nfacade.call("movement_line_clear", Vector2(30, 30), Vector2(1250, 850), 12.0, _ground_mask, {})
	queue.call("collect")
	var perf: Dictionary = queue.call("get_diagnostics")
	print("[m5-perf] 100-plan batch: compute %.2f ms on worker | collect wait %.3f ms after 10 ms main-thread work" % [
		int(perf.get("last_batch_compute_usec", 0)) / 1000.0, int(perf.get("last_collect_wait_usec", 0)) / 1000.0])
	queue.call("clear")


func _build_fixture() -> void:
	_nmap = ClassDB.instantiate("SimNavNativeMap")
	_nmap.call("setup", MAP_W, MAP_H, CELL, Vector2.ZERO, 1)
	_ground_mask = int(_nmap.call("register_passability_class", "ground", 12.0, true, 0))
	# Registered but never prewarmed: its jump tables must be refused (not
	# lazily built) while a batch is in flight.
	_large_mask = int(_nmap.call("register_passability_class", "large", 20.0, true, 0))
	_nmap.call("add_static_obstruction", "a", Vector2(400, 300), 160.0, 60.0, 0.0, BLOCK_PATHFINDING, "", "")
	_nmap.call("add_static_obstruction", "b", Vector2(700, 500), 80.0, 260.0, 0.0, BLOCK_PATHFINDING, "", "")
	_nmap.call("add_static_obstruction", "c", Vector2(1000, 250), 200.0, 50.0, 0.35, BLOCK_PATHFINDING, "", "")
	_nmap.call("rebuild_dirty")
	_nfacade = ClassDB.instantiate("SimNavNativeFacade")
	_nfacade.call("setup", _nmap)
	_nfacade.call("recompute", PackedInt32Array([_ground_mask]))
	_nmap.call("clear_dirty_navcells")
	_nfacade.call("prewarm_jump_point_cache", _ground_mask)


func _query_batch(count: int) -> Array:
	var queries: Array = []
	for i in range(count):
		var start := Vector2(40 + (i % 6) * 15.0, 40 + (i % 9) * 80.0)
		var goal := Vector2(1280 - (i % 5) * 22.0, 860 - (i % 7) * 90.0)
		queries.append({
			"start_world": start,
			"goal": { "type": 0, "center": goal, "hw": 0.0, "hh": 0.0, "u": Vector2(1, 0), "v": Vector2(0, 1), "maxdist": 0.0 },
			"pass_mask": _ground_mask,
			"passability_class_name": "ground",
			"excluded_regions": [],
			"post_process": "line_of_sight",
			"waypoint_spacing": CELL * 12.0 - 1.0,
		})
	return queries


func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a.keys():
		if not b.has(key):
			return false
		if typeof(a[key]) != typeof(b[key]):
			return false
		if a[key] != b[key]:
			return false
	return true
