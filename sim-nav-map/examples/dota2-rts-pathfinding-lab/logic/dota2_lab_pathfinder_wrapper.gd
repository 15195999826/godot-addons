class_name Dota2LabPathfinderWrapper
extends RefCounted

# Fable-version navigation wrapper: STATIC WORLD ONLY.
#
# Units never enter the nav map. Long paths plan around terrain bounds and
# static obstacles; unit-vs-unit interaction is entirely the motion engine's
# separation solve. That removes the whole class of same-tick-staleness bugs
# the old dynamic-obstruction refresh had.
#
# Planning is deferred and time-sliced: commands enqueue, the engine drains
# ONE request per tick through the core queue while units walk a
# straight-line placeholder for those few ticks. With the JPS+ ray tables a
# warm cross-map query is ~0.8 ms (was 5-6 ms; a synchronous 8-unit group
# command once froze the input frame for ~250 ms). The bake + table build is
# prewarmed inside rebuild_context, so every plan runs at warm cost.
# (A worker-thread variant was tried and reverted twice — GDScript-level
# lock contention; see the fable-motion design note.)

const PASSABILITY_CLASS_NAME := "ground"
const PLAN_BUDGET_PER_TICK := 1


# 8 px raster cells: after core gained CLEARANCE_EXTENSION_RADIUS (+1 raster
# cell), 16 px cells inflated static bands to clearance+16 = 28 px per side and
# sealed 56 px narrow-gap fixtures outright. 8 px keeps the band at
# clearance+8 = 20 px per side and halves center quantization.
var map_size: Vector2 = Vector2(1320.0, 900.0)
var cell_size: float = 8.0
var default_clearance: float = 12.0
var nav_map: SimNavMap = null
var pass_mask: int = 0
var hierarchical: SimNavHierarchicalPathfinder = null
var long_pathfinder: SimNavLongPathfinder = null
var facade: SimNavPathfinderFacade = null
var vertex_pathfinder: SimNavVertexPathfinder = null
var path_queue: SimNavPathRequestQueue = null
var plan_count: int = 0
var line_check_count: int = 0
# Compute cost of the most recent drained plan (usec) — HUD observability.
var last_plan_usec: int = 0

var _line_filter: SimNavObstructionFilter = null

# ── Native backend (knife 5, opt-in) ─────────────────────────────────────────
# When true AND the simnav_native extension is present, rebuild_context builds
# the C++ map/facade instead of the GDScript stack and planning/line checks
# route through it. Plan results convert back to SimNavLongPathResult at plan
# granularity, so every consumer type stays unchanged. Default OFF — GDScript
# is the reference implementation (approved decision, docs/gdextension-port-plan.md).
#
# Planning runs on a TRUE background worker (SimNavNativeQueue) with a
# deterministic fixed-latency contract: everything requested during tick T is
# visible at tick T+1's pump, regardless of thread timing — a whole group
# command lands in one tick instead of draining one-per-tick (approved
# decision: switching backends may change plan-arrival cadence). On platforms
# without threads (web nothreads) the same schedule computes synchronously.
var use_native: bool = false
var native_map: Object = null
var native_facade: Object = null
var native_queue: Object = null
var _native_static_shapes: Array[SimNavObstructionShapeStatic] = []

# ── Open-field mode (air layer) ──────────────────────────────────────────────
# Opt-in for wrappers whose world is provably obstacle-free forever (the lab's
# air layer). The playable area is a single rectangle, so the straight line
# between any two clamped points is always valid: planning degenerates to
# "walk the placeholder", request_plan returns 0 (no ticket, no queue), line
# checks are unconditionally clear, and NO nav stack is built — neither the
# GDScript one nor the native one, so both planner twins stay untouched and
# A/B-welded. Explicit flag rather than auto-detecting empty obstacles: ground
# worlds that merely happen to have no obstacles (lane fixtures, wrapper A/B
# smokes) must keep exercising real planning.
var open_field: bool = false


func _init(
	p_map_size: Vector2 = Vector2(1320.0, 900.0),
	p_cell_size: float = 8.0,
	p_default_clearance: float = 12.0
) -> void:
	map_size = p_map_size
	cell_size = p_cell_size
	default_clearance = p_default_clearance
	_line_filter = SimNavObstructionFilter.all()
	_line_filter.include_units = false


func rebuild_context(static_obstacles: Array[Dota2LabObstacle]) -> void:
	if open_field:
		Log.assert_crash(static_obstacles.is_empty(), "Dota2LabPathfinderWrapper",
			"open_field wrapper cannot take static obstacles")
		use_native = false
		nav_map = null
		hierarchical = null
		long_pathfinder = null
		facade = null
		vertex_pathfinder = null
		path_queue = null
		return
	if use_native:
		if SimNavNativeBridge.available():
			_rebuild_context_native(static_obstacles)
			return
		push_warning("[Dota2LabPathfinderWrapper] use_native requested but simnav_native extension is missing; falling back to GDScript")
		use_native = false
	if path_queue != null:
		path_queue.clear()
	var width := int(ceil(map_size.x / cell_size))
	var height := int(ceil(map_size.y / cell_size))
	nav_map = SimNavMap.new(width, height, cell_size, Vector2.ZERO, 1)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = PASSABILITY_CLASS_NAME
	ground.clearance = default_clearance
	ground.affects_pathfinding = true
	pass_mask = nav_map.register_passability_class(ground)
	_mark_out_of_playable_navcells(default_clearance)
	for obstacle in static_obstacles:
		nav_map.add_static_obstruction(_static_shape_for_obstacle(obstacle))
	nav_map.rebuild_dirty()
	hierarchical = SimNavHierarchicalPathfinder.new()
	hierarchical.recompute(nav_map, [pass_mask])
	nav_map.clear_dirty_navcells()
	long_pathfinder = SimNavLongPathfinder.new(nav_map)
	# Rebuild already freezes the frame; folding the jump-table build in here
	# keeps the first plan after it at warm cost (~0.8 ms) instead of ~11 ms.
	long_pathfinder.prewarm_jump_point_cache(pass_mask)
	facade = SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	vertex_pathfinder = SimNavVertexPathfinder.new(nav_map)
	path_queue = SimNavPathRequestQueue.new(facade, vertex_pathfinder)


# ── Native backend context ───────────────────────────────────────────────────

func _rebuild_context_native(static_obstacles: Array[Dota2LabObstacle]) -> void:
	if native_queue != null:
		native_queue.call("clear")
	var width := int(ceil(map_size.x / cell_size))
	var height := int(ceil(map_size.y / cell_size))
	native_map = ClassDB.instantiate("SimNavNativeMap")
	native_map.call("setup", width, height, cell_size, Vector2.ZERO, 1)
	pass_mask = int(native_map.call("register_passability_class", PASSABILITY_CLASS_NAME, default_clearance, true, 0))
	for y in range(height):
		for x in range(width):
			var coord := Vector2i(x, y)
			var point: Vector2 = native_map.call("navcell_center_world", coord)
			if _point_inside_playable_bounds(point, default_clearance):
				continue
			native_map.call("or_navcell_data", coord, pass_mask)
	_native_static_shapes = []
	for obstacle in static_obstacles:
		var shape := _static_shape_for_obstacle(obstacle)
		_native_static_shapes.append(shape)
		var tag := int(native_map.call("add_static_obstruction", shape.entity_id, shape.center, shape.width, shape.height, shape.rotation_rad, shape.flags))
		shape.tag = tag
	native_map.call("rebuild_dirty")
	native_facade = ClassDB.instantiate("SimNavNativeFacade")
	native_facade.call("setup", native_map)
	native_facade.call("recompute", PackedInt32Array([pass_mask]))
	native_map.call("clear_dirty_navcells")
	native_facade.call("prewarm_jump_point_cache", pass_mask)
	native_queue = ClassDB.instantiate("SimNavNativeQueue")
	native_queue.call("setup", native_facade)
	nav_map = null
	hierarchical = null
	long_pathfinder = null
	facade = null
	vertex_pathfinder = null
	path_queue = null


# ── Async plan API (normal engine path) ──────────────────────────────────────

# Enqueue a long-path request for the worker thread. Reachable-goal
# canonicalization applies as in plan_path.
func request_plan(start: Vector2, goal: Vector2) -> int:
	if open_field:
		# The engine's straight-line placeholder already IS the final path;
		# 0 = no ticket, so no plan ever computes or lands.
		return 0
	if use_native:
		plan_count += 1
		return int(native_queue.call("enqueue", SimNavNativeBridge.query_to_dict(_build_long_path_query(start, goal))))
	if path_queue == null:
		return 0
	plan_count += 1
	return path_queue.enqueue_long_path_query(_build_long_path_query(start, goal))


func cancel_plan(ticket: int) -> void:
	if ticket <= 0:
		return
	if use_native:
		native_queue.call("cancel", ticket)
		return
	if path_queue == null:
		return
	path_queue.cancel(ticket)


# Once per tick. GDScript backend: compute at most PLAN_BUDGET_PER_TICK
# requests on the main thread (time-slicing). Native backend: harvest the
# background batch handed last tick (blocking collect = deterministic
# fixed-latency arrival), then hand everything pending to the worker.
func pump_async() -> void:
	if open_field:
		return
	if use_native:
		if int(native_queue.call("collect")) > 0:
			var diagnostics: Dictionary = native_queue.call("get_diagnostics")
			var batch_size := maxi(1, int(diagnostics.get("last_batch_size", 1)))
			@warning_ignore("integer_division")
			var per_plan: int = int(diagnostics.get("last_batch_compute_usec", 0)) / batch_size
			last_plan_usec = per_plan
		native_queue.call("begin_tick")
		return
	if path_queue == null:
		return
	if path_queue.pending_count() <= 0:
		return
	if path_queue.process_budget(PLAN_BUDGET_PER_TICK) > 0:
		var processed: Array = path_queue.get_diagnostics().get("last_processed_requests", [])
		if not processed.is_empty():
			last_plan_usec = int((processed.back() as Dictionary).get("compute_usec", 0))


func take_plan_result(ticket: int) -> SimNavLongPathResult:
	if ticket <= 0:
		return null
	if use_native:
		var result_dict: Dictionary = native_queue.call("take_result", ticket)
		if result_dict.is_empty():
			return null
		return SimNavNativeBridge.to_long_path_result(result_dict)
	if path_queue == null:
		return null
	return path_queue.take_long_path_result(ticket)


func pending_plan_count() -> int:
	if use_native:
		return int(native_queue.call("pending_count"))
	if path_queue == null:
		return 0
	return path_queue.pending_count()


# ── Synchronous plan (tools/probes only) ─────────────────────────────────────

# Same query as request_plan, computed immediately.
func plan_path(start: Vector2, goal: Vector2) -> SimNavLongPathResult:
	if open_field:
		return _direct_result(start, goal)
	plan_count += 1
	if use_native:
		var result_dict: Dictionary = native_facade.call("compute_path_result", SimNavNativeBridge.query_to_dict(_build_long_path_query(start, goal)))
		return SimNavNativeBridge.to_long_path_result(result_dict)
	return facade.compute_path_result(_build_long_path_query(start, goal))


# Synthesized straight-line result for open-field sync probes; the async path
# never plans at all (request_plan returns 0).
func _direct_result(start: Vector2, goal: Vector2) -> SimNavLongPathResult:
	var result := SimNavLongPathResult.new()
	result.configure_query(_build_long_path_query(start, goal))
	var direct := SimNavWaypointPath.new()
	direct.push_back(goal)
	var no_cells: Array[Vector2i] = []
	result.set_paths(SimNavLongPathResult.STATUS_DIRECT_GOAL, no_cells, SimNavWaypointPath.new(), direct, 0)
	return result


func _build_long_path_query(start: Vector2, goal: Vector2) -> SimNavLongPathQuery:
	var query := SimNavLongPathQuery.from_values(
		start,
		SimNavPathGoal.point(goal),
		pass_mask,
		PASSABILITY_CLASS_NAME
	)
	query.post_process = SimNavLongPathQuery.POST_PROCESS_LINE_OF_SIGHT
	query.waypoint_spacing = cell_size * 12.0 - 1.0
	return query


# Raster LOS against statics only, at class clearance. Used for waypoint
# shortcutting: conservative (band-inflated) on purpose so a shortcut can
# never commit the unit to a line the planner would have refused. Boolean
# fast path — this runs per tick for every moving unit.
func is_line_walkable(start: Vector2, target: Vector2) -> bool:
	if open_field:
		return true  # one rectangular playable area: every segment is clear
	line_check_count += 1
	if use_native:
		# Statics-only filter is the native default (units never enter the
		# native map); crossing is a plain bool, no DTO.
		return bool(native_facade.call("movement_line_clear", start, target, default_clearance, pass_mask, {}))
	return facade.movement_line_clear(
		start, target, default_clearance, pass_mask, _line_filter
	)


# Exact static geometry for the separation solve's project-out step.
func static_shapes() -> Array[SimNavObstructionShapeStatic]:
	if use_native:
		return _native_static_shapes
	if nav_map == null:
		return []
	return nav_map.get_static_obstruction_shapes()


func clamp_to_playable(point: Vector2, radius: float) -> Vector2:
	return Vector2(
		clampf(point.x, radius, map_size.x - radius),
		clampf(point.y, radius, map_size.y - radius)
	)


func diagnostics() -> Dictionary:
	return {
		"plan_count": plan_count,
		"line_check_count": line_check_count,
		"plans_pending": pending_plan_count(),
		"last_plan_usec": last_plan_usec,
	}


func _static_shape_for_obstacle(obstacle: Dota2LabObstacle) -> SimNavObstructionShapeStatic:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = obstacle.id
	shape.center = obstacle.center
	shape.width = obstacle.size.x
	shape.height = obstacle.size.y
	shape.rotation_rad = obstacle.rotation_rad
	shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	return shape


func _mark_out_of_playable_navcells(clearance: float) -> void:
	for y in range(nav_map.height):
		for x in range(nav_map.width):
			var coord := Vector2i(x, y)
			var point := nav_map.navcell_center_world(coord)
			if _point_inside_playable_bounds(point, clearance):
				continue
			nav_map.or_navcell_data(coord, pass_mask)


func _point_inside_playable_bounds(point: Vector2, clearance: float) -> bool:
	return (
		point.x >= clearance
		and point.y >= clearance
		and point.x <= map_size.x - clearance
		and point.y <= map_size.y - clearance
	)
