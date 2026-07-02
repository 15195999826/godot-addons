extends Node

# M3 A/B weld: the native hierarchical + long-path + facade chain must
# reproduce the GDScript stack result-for-result — connectivity region grids,
# every long-path result field (statuses, canonicalization metadata, raw
# cells, waypoints bitwise, costs, lengths, search diagnostics), the
# movement_line_clear boolean (raster + exact static geometry stages, filter
# semantics), and the facade flush stats — across a terrain-change flush
# round. Also prints the first batch of native-vs-GDScript perf numbers.

const MAP_W := 165
const MAP_H := 113
const CELL := 8.0
const BLOCK_PATHFINDING := 8
const BLOCK_MOVEMENT := 1

var _failures: Array[String] = []

var _gd_map: SimNavMap = null
var _gd_hier: SimNavHierarchicalPathfinder = null
var _gd_long: SimNavLongPathfinder = null
var _gd_facade: SimNavPathfinderFacade = null
var _nmap: Object = null
var _nfacade: Object = null
var _tags: Array[int] = []
var _ground_mask := 0
var _large_mask := 0


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - native longpath+hierarchical+facade A/B identical")
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
	_build_fixture()
	if not _failures.is_empty():
		return

	_compare_connectivity("initial", _ground_mask)
	_compare_connectivity("initial", _large_mask)

	var matrix := _query_matrix()
	for entry in matrix:
		_compare_query(str(entry[0]), entry[1] as SimNavLongPathQuery)
	_sweep_lines("initial", 400)
	_control_group_probe()
	_invalid_goal_reachability_probe()

	# ── Terrain-change flush round ───────────────────────────────────────────
	_gd_map.move_obstruction(_tags[0], Vector2(260, 240), 0.0)
	_nmap.call("move_obstruction", _tags[0], Vector2(260, 240), 0.0)
	_gd_map.remove_obstruction(_tags[6])
	_nmap.call("remove_obstruction", _tags[6])
	_add_static(Vector2(520, 700), 140, 40, 0.25, BLOCK_PATHFINDING)
	_set_terrain(Vector2i(30, 25), 0)
	_set_terrain(Vector2i(95, 65), 2)
	_gd_map.or_navcell_data(Vector2i(80, 12), _ground_mask)
	_nmap.call("or_navcell_data", Vector2i(80, 12), _ground_mask)

	var gd_stats := _gd_facade.recompute_dirty([_ground_mask, _large_mask])
	var n_stats: Dictionary = _nfacade.call("recompute_dirty", PackedInt32Array([_ground_mask, _large_mask]), true)
	for key in ["dirty_navcells", "changed_obstruction_navcells", "rebuilt_chunks", "invalidated_long_path_cache"]:
		if int(gd_stats.get(key, -1)) != int(n_stats.get(key, -2)):
			_failures.append("flush stats differ at %s (gd=%s native=%s)" % [key, gd_stats.get(key), n_stats.get(key)])

	_compare_connectivity("after flush", _ground_mask)
	_compare_connectivity("after flush", _large_mask)
	for entry in _query_matrix().slice(0, 6):
		_compare_query("post-flush " + str(entry[0]), entry[1] as SimNavLongPathQuery)
	_sweep_lines("after flush", 200)

	_perf_phase()


# ── Fixture ──────────────────────────────────────────────────────────────────

func _build_fixture() -> void:
	_gd_map = SimNavMap.new(MAP_W, MAP_H, CELL, Vector2.ZERO, 1)
	_nmap = ClassDB.instantiate("SimNavNativeMap")
	_nmap.call("setup", MAP_W, MAP_H, CELL, Vector2.ZERO, 1)
	_tags = []

	_ground_mask = _register_class("ground", 12.0, true, 1)
	_large_mask = _register_class("large", 20.0, true, 2)
	if _ground_mask == 0 or _large_mask == 0:
		return

	_gd_map.set_bounds(12.0, 12.0, MAP_W * CELL - 12.0, MAP_H * CELL - 12.0)
	_nmap.call("set_bounds", 12.0, 12.0, MAP_W * CELL - 12.0, MAP_H * CELL - 12.0)

	for i in range(30):
		_set_terrain(Vector2i(25 + i, 20 + i), 1)
	for i in range(18):
		_set_terrain(Vector2i(45 + i, 85), 2)

	_add_static(Vector2(200, 200), 120, 40, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(480, 300), 60, 220, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(700, 500), 90, 90, 0.35, BLOCK_PATHFINDING)
	_add_static(Vector2(900, 250), 140, 50, -1.2, BLOCK_PATHFINDING)
	_add_static(Vector2(300, 650), 200, 30, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(1000, 700), 80, 80, 0.0, BLOCK_MOVEMENT)
	_add_static(Vector2(600, 120), 50, 50, 0.0, BLOCK_PATHFINDING)
	# Walled pocket around (1150, 160): interior reachable only... not — the
	# ring is closed, so a goal inside canonicalizes to the nearest outside
	# navcell.
	_add_static(Vector2(1150, 100), 140, 16, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(1150, 220), 140, 16, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(1080, 160), 16, 140, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(1220, 160), 16, 140, 0.0, BLOCK_PATHFINDING)
	# Control-group probe shape (see _control_group_probe).
	_add_static(Vector2(400, 800), 120, 60, 0.0, BLOCK_PATHFINDING, "cg-test")

	_gd_map.rebuild_dirty()
	_nmap.call("rebuild_dirty")

	_gd_hier = SimNavHierarchicalPathfinder.new()
	_gd_hier.recompute(_gd_map, [_ground_mask, _large_mask])
	_gd_long = SimNavLongPathfinder.new(_gd_map)
	_gd_facade = SimNavPathfinderFacade.new(_gd_map, _gd_hier, _gd_long)
	_nfacade = ClassDB.instantiate("SimNavNativeFacade")
	_nfacade.call("setup", _nmap)
	_nfacade.call("recompute", PackedInt32Array([_ground_mask, _large_mask]))

	_gd_map.clear_dirty_navcells()
	_nmap.call("clear_dirty_navcells")
	_gd_long.prewarm_jump_point_cache(_ground_mask)
	_gd_long.prewarm_jump_point_cache(_large_mask)
	_nfacade.call("prewarm_jump_point_cache", _ground_mask)
	_nfacade.call("prewarm_jump_point_cache", _large_mask)


func _query_matrix() -> Array:
	var mid := Vector2(MAP_W * CELL * 0.5, MAP_H * CELL * 0.5)
	var entries: Array = []
	entries.append(["cross-map LOS", _make_query(Vector2(40, 40), SimNavPathGoal.point(Vector2(1250, 850)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, CELL * 12.0 - 1.0)])
	entries.append(["cross-map RAW", _make_query(Vector2(40, 40), SimNavPathGoal.point(Vector2(1250, 850)), SimNavLongPathQuery.POST_PROCESS_RAW, 0.0)])
	entries.append(["circle goal", _make_query(Vector2(60, 700), SimNavPathGoal.circle(Vector2(950, 420), 30.0), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["inverted circle", _make_query(mid, SimNavPathGoal.inverted_circle(mid, 320.0), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["square rotated", _make_query(Vector2(120, 500), SimNavPathGoal.square(Vector2(880, 640), 25.0, 15.0, 0.6), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["goal in wall", _make_query(Vector2(40, 40), SimNavPathGoal.point(Vector2(480, 300)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["start in wall", _make_query(Vector2(480, 300), SimNavPathGoal.point(Vector2(60, 60)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["goal in pocket", _make_query(Vector2(40, 40), SimNavPathGoal.point(Vector2(1150, 160)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["goal OOB", _make_query(Vector2(40, 40), SimNavPathGoal.point(Vector2(5000, 5000)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["start OOB", _make_query(Vector2(-500, -500), SimNavPathGoal.point(Vector2(200, 600)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	entries.append(["direct goal", _make_query(Vector2(502, 502), SimNavPathGoal.point(Vector2(500, 500)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)])
	var maxdist_goal := SimNavPathGoal.point(Vector2(1250, 850))
	maxdist_goal.maxdist = 40.0
	entries.append(["max spacing", _make_query(Vector2(40, 40), maxdist_goal, SimNavLongPathQuery.POST_PROCESS_MAX_SPACING, 0.0)])
	var excluded := _make_query(Vector2(40, 40), SimNavPathGoal.point(Vector2(1250, 850)), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, 0.0)
	excluded.add_excluded_circle(Vector2(620, 420), 90.0)
	excluded.add_excluded_circle(Vector2(240, 420), 70.0)
	entries.append(["excluded astar", excluded])
	return entries


func _make_query(start: Vector2, goal: SimNavPathGoal, post_process: String, spacing: float) -> SimNavLongPathQuery:
	var query := SimNavLongPathQuery.from_values(start, goal, _ground_mask, "ground")
	query.post_process = post_process
	query.waypoint_spacing = spacing
	return query


# ── Comparators ──────────────────────────────────────────────────────────────

func _compare_connectivity(label: String, mask: int) -> void:
	var gd_export := _gd_hier.export_connectivity(mask)
	var n_export: Dictionary = _nfacade.call("export_connectivity", mask, "")
	var gd_regions: PackedInt32Array = gd_export.get("regions", PackedInt32Array())
	var n_regions: PackedInt32Array = n_export.get("regions", PackedInt32Array())
	if gd_regions != n_regions:
		var diff := -1
		for i in range(mini(gd_regions.size(), n_regions.size())):
			if gd_regions[i] != n_regions[i]:
				diff = i
				break
		_failures.append("%s mask %d: connectivity regions differ (sizes %d/%d first diff idx=%d)" % [label, mask, gd_regions.size(), n_regions.size(), diff])
	if int(gd_export.get("global_region_count", -1)) != int(n_export.get("global_region_count", -2)):
		_failures.append("%s mask %d: global_region_count differs (gd=%s native=%s)" % [label, mask, gd_export.get("global_region_count"), n_export.get("global_region_count")])


func _compare_query(label: String, query: SimNavLongPathQuery) -> void:
	var gd_result := _gd_facade.compute_path_result(query.clone())
	var n_dict: Dictionary = _nfacade.call("compute_path_result", SimNavNativeBridge.query_to_dict(query))
	var n_result := SimNavNativeBridge.to_long_path_result(n_dict)
	var mismatches: Array[String] = []
	_diff(mismatches, "status", gd_result.status, n_result.status)
	_diff(mismatches, "failure_reason", gd_result.failure_reason, n_result.failure_reason)
	_diff(mismatches, "canonicalization_reason", gd_result.canonicalization_reason, n_result.canonicalization_reason)
	_diff(mismatches, "canonicalized", gd_result.canonicalized, n_result.canonicalized)
	_diff(mismatches, "start_recovered", gd_result.start_recovered, n_result.start_recovered)
	_diff(mismatches, "start_navcell", gd_result.start_navcell, n_result.start_navcell)
	_diff(mismatches, "effective_start_navcell", gd_result.effective_start_navcell, n_result.effective_start_navcell)
	_diff(mismatches, "effective_start_world", gd_result.effective_start_world, n_result.effective_start_world)
	_diff(mismatches, "canonical_navcell", gd_result.canonical_navcell, n_result.canonical_navcell)
	_diff(mismatches, "path_cost", gd_result.path_cost, n_result.path_cost)
	_diff(mismatches, "path_length", gd_result.path_length, n_result.path_length)
	_diff(mismatches, "raw_navcell_count", gd_result.raw_navcell_count, n_result.raw_navcell_count)
	_diff(mismatches, "raw_waypoint_count", gd_result.raw_waypoint_count, n_result.raw_waypoint_count)
	_diff(mismatches, "refined_waypoint_count", gd_result.refined_waypoint_count, n_result.refined_waypoint_count)
	if gd_result.raw_navcell_path != n_result.raw_navcell_path:
		mismatches.append("raw_navcell_path cells differ")
	if gd_result.raw_waypoint_path.waypoints != n_result.raw_waypoint_path.waypoints:
		mismatches.append("raw waypoints differ")
	if gd_result.refined_waypoint_path.waypoints != n_result.refined_waypoint_path.waypoints:
		mismatches.append("refined waypoints differ")
	_diff(mismatches, "search_algorithm", gd_result.search_algorithm, n_result.search_algorithm)
	_diff(mismatches, "search_expansion_count", gd_result.search_expansion_count, n_result.search_expansion_count)
	_diff(mismatches, "search_push_count", gd_result.search_push_count, n_result.search_push_count)
	_diff(mismatches, "search_jump_count", gd_result.search_jump_count, n_result.search_jump_count)
	_diff(mismatches, "search_closed_count", gd_result.search_closed_count, n_result.search_closed_count)
	_diff(mismatches, "search_max_open_count", gd_result.search_max_open_count, n_result.search_max_open_count)
	_diff(mismatches, "search_path_cell_count", gd_result.search_path_cell_count, n_result.search_path_cell_count)
	_diff(mismatches, "waypoint_order", gd_result.waypoint_order, n_result.waypoint_order)
	_diff(mismatches, "raw_navcell_order", gd_result.raw_navcell_order, n_result.raw_navcell_order)
	_diff(mismatches, "post_process", gd_result.post_process, n_result.post_process)
	_diff(mismatches, "waypoint_spacing", gd_result.waypoint_spacing, n_result.waypoint_spacing)
	_diff(mismatches, "pass_mask", gd_result.pass_mask, n_result.pass_mask)
	_diff(mismatches, "passability_class_name", gd_result.passability_class_name, n_result.passability_class_name)
	_compare_goal(mismatches, "query_goal", gd_result.query_goal, n_result.query_goal)
	_compare_goal(mismatches, "canonical_goal", gd_result.canonical_goal, n_result.canonical_goal)
	_compare_reachability(mismatches, gd_result.reachability_result, n_result.reachability_result)
	if mismatches.is_empty():
		print("[m3-ab] %s: identical (%s, %d refined wp)" % [label, gd_result.status, gd_result.refined_waypoint_count])
	else:
		_failures.append("%s: %s" % [label, "; ".join(mismatches)])


func _diff(mismatches: Array[String], field: String, gd_value: Variant, n_value: Variant) -> void:
	if gd_value != n_value:
		mismatches.append("%s gd=%s native=%s" % [field, gd_value, n_value])


func _compare_goal(mismatches: Array[String], label: String, gd_goal: SimNavPathGoal, n_goal: SimNavPathGoal) -> void:
	if (gd_goal == null) != (n_goal == null):
		mismatches.append("%s nullity differs" % label)
		return
	if gd_goal == null:
		return
	if gd_goal.type != n_goal.type or gd_goal.center != n_goal.center or gd_goal.hw != n_goal.hw \
			or gd_goal.hh != n_goal.hh or gd_goal.u != n_goal.u or gd_goal.v != n_goal.v \
			or gd_goal.maxdist != n_goal.maxdist:
		mismatches.append("%s fields differ" % label)


func _compare_reachability(mismatches: Array[String], gd_reach: SimNavReachabilityResult, n_reach: SimNavReachabilityResult) -> void:
	if (gd_reach == null) != (n_reach == null):
		mismatches.append("reachability nullity differs")
		return
	if gd_reach == null:
		return
	if gd_reach.is_reachable != n_reach.is_reachable or gd_reach.canonicalized != n_reach.canonicalized \
			or gd_reach.failure_reason != n_reach.failure_reason \
			or gd_reach.start_navcell != n_reach.start_navcell \
			or gd_reach.effective_start_navcell != n_reach.effective_start_navcell \
			or gd_reach.canonical_navcell != n_reach.canonical_navcell \
			or gd_reach.start_global_region != n_reach.start_global_region \
			or gd_reach.canonical_global_region != n_reach.canonical_global_region:
		mismatches.append("reachability fields differ")


func _sweep_lines(label: String, segment_count: int) -> void:
	var filter := SimNavObstructionFilter.all()
	filter.include_units = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260703
	var mismatch := 0
	for i in range(segment_count):
		var a := Vector2(rng.randf_range(-40.0, MAP_W * CELL + 40.0), rng.randf_range(-40.0, MAP_H * CELL + 40.0))
		var b := Vector2(rng.randf_range(-40.0, MAP_W * CELL + 40.0), rng.randf_range(-40.0, MAP_H * CELL + 40.0))
		if i % 6 == 0:
			b = a + (b - a) * 0.05  # short local hops
		var clearance := 12.0 if i % 3 != 0 else 0.0
		var gd_clear := _gd_facade.movement_line_clear(a, b, clearance, _ground_mask, filter)
		var n_clear := bool(_nfacade.call("movement_line_clear", a, b, clearance, _ground_mask, {}))
		if gd_clear != n_clear:
			mismatch += 1
	if mismatch > 0:
		_failures.append("%s: movement_line_clear mismatches %d / %d" % [label, mismatch, segment_count])
	else:
		print("[m3-ab] %s: %d movement_line probes identical" % [label, segment_count])


func _control_group_probe() -> void:
	# A segment straight through the cg-test shape: blocked by default, clear
	# when the filter excludes that control group — on both backends.
	var a := Vector2(320, 800)
	var b := Vector2(480, 800)
	var plain := SimNavObstructionFilter.all()
	plain.include_units = false
	var excluding := SimNavObstructionFilter.all()
	excluding.include_units = false
	excluding.control_group = "cg-test"
	var gd_blocked := _gd_facade.movement_line_clear(a, b, 12.0, _ground_mask, plain)
	var n_blocked := bool(_nfacade.call("movement_line_clear", a, b, 12.0, _ground_mask, {}))
	if gd_blocked != n_blocked:
		_failures.append("control-group probe: plain filter differs (gd=%s native=%s)" % [gd_blocked, n_blocked])
	var gd_excluded := _gd_facade.movement_line_clear(a, b, 12.0, _ground_mask, excluding)
	var n_excluded := bool(_nfacade.call("movement_line_clear", a, b, 12.0, _ground_mask, { "control_group": "cg-test" }))
	if gd_excluded != n_excluded:
		_failures.append("control-group probe: excluding filter differs (gd=%s native=%s)" % [gd_excluded, n_excluded])
	if gd_excluded == gd_blocked:
		_failures.append("control-group probe fixture is inert (both %s) — move the segment" % gd_blocked)


func _invalid_goal_reachability_probe() -> void:
	# Null/empty goal: both backends must fail invalid_query while keeping the
	# start-cell metadata (codex M3 finding).
	var start := Vector2(200, 200)
	var gd_reach := _gd_facade.query_reachability(start, null, _ground_mask, "ground")
	var n_reach := SimNavNativeBridge.to_reachability_result(_nfacade.call("query_reachability", start, {}, _ground_mask, "ground"))
	var mismatches: Array[String] = []
	if gd_reach.failure_reason != n_reach.failure_reason:
		mismatches.append("failure_reason gd=%s native=%s" % [gd_reach.failure_reason, n_reach.failure_reason])
	if gd_reach.start_navcell != n_reach.start_navcell or gd_reach.effective_start_navcell != n_reach.effective_start_navcell:
		mismatches.append("start cells gd=%s/%s native=%s/%s" % [gd_reach.start_navcell, gd_reach.effective_start_navcell, n_reach.start_navcell, n_reach.effective_start_navcell])
	if not mismatches.is_empty():
		_failures.append("invalid-goal reachability probe: %s" % "; ".join(mismatches))
	else:
		print("[m3-ab] invalid-goal reachability probe identical (%s)" % gd_reach.failure_reason)


# ── Perf numbers (printed, not asserted — budget lines stay GDScript) ────────

func _perf_phase() -> void:
	var starts: Array[Vector2] = [Vector2(40, 40), Vector2(60, 820), Vector2(1240, 60), Vector2(700, 880)]
	var goals: Array[Vector2] = [Vector2(1250, 850), Vector2(1180, 100), Vector2(80, 860), Vector2(120, 80)]
	var plan_count := 40
	var gd_start := Time.get_ticks_usec()
	for i in range(plan_count):
		var query := _make_query(starts[i % 4], SimNavPathGoal.point(goals[(i + 1) % 4]), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, CELL * 12.0 - 1.0)
		_gd_facade.compute_path_result(query)
	var gd_plan_usec := Time.get_ticks_usec() - gd_start
	var n_start := Time.get_ticks_usec()
	for i in range(plan_count):
		var query := _make_query(starts[i % 4], SimNavPathGoal.point(goals[(i + 1) % 4]), SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT, CELL * 12.0 - 1.0)
		SimNavNativeBridge.to_long_path_result(_nfacade.call("compute_path_result", SimNavNativeBridge.query_to_dict(query)))
	var n_plan_usec := Time.get_ticks_usec() - n_start
	print("[m3-perf] cross-map plan x%d: gd %.2f ms (%.1f us/plan) | native %.2f ms (%.1f us/plan, incl DTO roundtrip) | %.1fx" % [
		plan_count, gd_plan_usec / 1000.0, float(gd_plan_usec) / plan_count, n_plan_usec / 1000.0, float(n_plan_usec) / plan_count,
		float(gd_plan_usec) / maxf(1.0, float(n_plan_usec))])

	var flush_rounds := 5
	var gd_flush_usec := 0
	var n_flush_usec := 0
	for i in range(flush_rounds):
		var offset := Vector2(240 + (i % 2) * 20, 220)
		_gd_map.move_obstruction(_tags[0], offset, 0.0)
		var t0 := Time.get_ticks_usec()
		_gd_map.rasterize_dirty_obstructions()
		_gd_facade.recompute_dirty([_ground_mask, _large_mask])
		gd_flush_usec += Time.get_ticks_usec() - t0
		_nmap.call("move_obstruction", _tags[0], offset, 0.0)
		var t1 := Time.get_ticks_usec()
		_nfacade.call("recompute_dirty", PackedInt32Array([_ground_mask, _large_mask]), true)
		n_flush_usec += Time.get_ticks_usec() - t1
	print("[m3-perf] terrain-change flush x%d: gd %.2f ms avg | native %.2f ms avg | %.1fx" % [
		flush_rounds, gd_flush_usec / 1000.0 / flush_rounds, n_flush_usec / 1000.0 / flush_rounds,
		float(gd_flush_usec) / maxf(1.0, float(n_flush_usec))])

	var line_count := 2000
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var segments: Array[Vector2] = []
	for i in range(line_count * 2):
		segments.append(Vector2(rng.randf_range(20.0, MAP_W * CELL - 20.0), rng.randf_range(20.0, MAP_H * CELL - 20.0)))
	var filter := SimNavObstructionFilter.all()
	filter.include_units = false
	var t2 := Time.get_ticks_usec()
	for i in range(line_count):
		_gd_facade.movement_line_clear(segments[i * 2], segments[i * 2 + 1], 12.0, _ground_mask, filter)
	var gd_line_usec := Time.get_ticks_usec() - t2
	var t3 := Time.get_ticks_usec()
	for i in range(line_count):
		_nfacade.call("movement_line_clear", segments[i * 2], segments[i * 2 + 1], 12.0, _ground_mask, {})
	var n_line_usec := Time.get_ticks_usec() - t3
	print("[m3-perf] movement_line_clear x%d: gd %.2f ms | native %.2f ms | %.1fx" % [
		line_count, gd_line_usec / 1000.0, n_line_usec / 1000.0, float(gd_line_usec) / maxf(1.0, float(n_line_usec))])


# ── Twin drivers ─────────────────────────────────────────────────────────────

func _register_class(class_name_id: String, clearance: float, affects: bool, terrain_mask: int) -> int:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = class_name_id
	config.clearance = clearance
	config.affects_pathfinding = affects
	config.terrain_mask = terrain_mask
	var gd_mask := _gd_map.register_passability_class(config)
	var n_mask := int(_nmap.call("register_passability_class", class_name_id, clearance, affects, terrain_mask))
	if gd_mask != n_mask:
		_failures.append("passability mask mismatch for %s" % class_name_id)
		return 0
	return gd_mask


func _set_terrain(tile: Vector2i, value: int) -> void:
	_gd_map.set_terrain_tile_data(tile, value)
	_nmap.call("set_terrain_tile_data", tile, value)


func _add_static(center: Vector2, width: float, height: float, rotation_rad: float, flags: int, control_group: String = "") -> void:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = str(_tags.size() + 1)
	shape.center = center
	shape.width = width
	shape.height = height
	shape.rotation_rad = rotation_rad
	shape.flags = flags
	shape.control_group = control_group
	var gd_tag := _gd_map.add_static_obstruction(shape)
	var n_tag := int(_nmap.call("add_static_obstruction", str(_tags.size() + 1), center, width, height, rotation_rad, flags, control_group, ""))
	if gd_tag != n_tag:
		_failures.append("obstruction tag mismatch (gd=%d native=%d)" % [gd_tag, n_tag])
	_tags.append(gd_tag)
