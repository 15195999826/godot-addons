extends Node

# LAB-006: Lab adapter drops waypoints when grid-fallback fires after a
# vertex skip (status=success, refined_waypoint_count=3, but path_size=0
# delivered to the unit, so it sits frozen with has_move_order=true).
#
# Repro: replay the exact failing inputs from a user export-log capture
# (tick 631) — blue_3 at (581.87, 212.93) commanded to (63, 226) with
# the default 3 static obstacles plus 5 other blue mobiles + 2 red
# blockers. plan_path() should return a non-empty path because the core
# long pathfinder reports status=success / refined_waypoint_count=3.
#
# At HEAD (before fix): plan_path returns an empty path because
# _string_pull's smoothed result fails _path_respects_lab_bounds and the
# function silently returns []. FAIL.
# After fix: smoothing-validation failure falls back to the unsmoothed
# core long path (LOS-cleared by compute_path_result), so the unit
# receives a non-empty path. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_006_grid_fallback_empty_path.tscn

const LabObstacle := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabPathfinder := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_pathfinder.gd")
const LabUnit := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_unit.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-006 grid-fallback empty path (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-006 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var pf := LabPathfinder.new(Vector2(720.0, 420.0), 16.0, 11.0)
	var obstacles: Array[RtsPathfindingLabObstacle] = [
		LabObstacle.new("stone_block", Vector2(340.0, 210.0), Vector2(110.0, 110.0)),
		LabObstacle.new("north_wall", Vector2(340.0, 75.0), Vector2(120.0, 80.0)),
		LabObstacle.new("south_wall", Vector2(340.0, 345.0), Vector2(120.0, 80.0)),
	]
	# Five other blue mobiles at their last-known positions plus two red
	# blockers — the population that drives `dynamic_obstacle_count` over
	# the limit and triggers the `crowded_edge_long_query` vertex skip.
	var units: Array[RtsPathfindingLabUnit] = [
		LabUnit.new("blue_0", "blue", Vector2(556.0, 195.0), 11.0, 98.0, true),
		LabUnit.new("blue_1", "blue", Vector2(580.0, 195.0), 11.0, 98.0, true),
		LabUnit.new("blue_2", "blue", Vector2(604.0, 195.0), 11.0, 98.0, true),
		LabUnit.new("blue_4", "blue", Vector2(556.0, 230.0), 11.0, 98.0, true),
		LabUnit.new("blue_5", "blue", Vector2(580.0, 230.0), 11.0, 98.0, true),
		LabUnit.new("red_blocker_n", "red", Vector2(455.0, 145.0), 14.0, 0.0, false),
		LabUnit.new("red_blocker_s", "red", Vector2(455.0, 275.0), 14.0, 0.0, false),
	]
	var start := Vector2(581.87, 212.93)
	var goal := Vector2(63.0, 226.0)
	var path: Array[Vector2] = pf.plan_path(start, goal, obstacles, units, "blue", true, true)
	var report := pf.last_report
	var path_size: int = path.size()
	var used_grid_fallback := bool(report.get("used_grid_fallback", false))
	var skipped_reason := str(report.get("skipped_vertex_reason", ""))
	var long_path_status := ""
	if report.has("long_path_result"):
		var long_report: Dictionary = report["long_path_result"]
		long_path_status = str(long_report.get("status", ""))
	if path_size == 0:
		_failures.append(
			"plan_path returned 0 waypoints from %s to %s (used_grid_fallback=%s, skipped_vertex_reason=%s, long_path_status=%s, refined_waypoint_count=%s, lab_smoothed_path_size=%s, core_refined_path_size=%s)"
			% [
				str(start),
				str(goal),
				str(used_grid_fallback),
				skipped_reason,
				long_path_status,
				str((report.get("long_path_result", {}) as Dictionary).get("refined_waypoint_count", "?")),
				str(report.get("lab_smoothed_path_size", "?")),
				str(report.get("core_refined_path_size", "?")),
			]
		)
		return
	# Final waypoint should be at or near the requested goal. The core long
	# pathfinder's refined waypoints are navcell-center based, so the lab's
	# continuous-LOS segment_clear can flag the start→first-waypoint or
	# inter-waypoint segments as marginal-clip even when each navcell
	# center on the route is passable; that is for the runtime push-out
	# to handle. The fix only needs to guarantee the unit gets a non-empty
	# path so it does not freeze with has_move_order=true.
	var last_point: Vector2 = path[path.size() - 1]
	if last_point.distance_to(goal) > 64.0:
		_failures.append(
			"final waypoint %s is %.1f px away from goal %s (expected close to goal)"
			% [str(last_point), last_point.distance_to(goal), str(goal)]
		)
