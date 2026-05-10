extends Node

# Edge-case smoke for the 0ad-rts-pathfinding-lab world.
#
# Each sub-test promotes a previously observation-only stress phase into a
# binary contract assertion. The contract being checked is named at the top
# of each sub-test; numeric thresholds chosen for runaway / overlap detection
# are intentionally loose so the contract reflects a system invariant rather
# than the exact metrics produced by the current implementation.


const DT := 1.0 / 60.0
const DEFAULT_TARGET := Vector2(610.0, 210.0)


var _failures: Array[String] = []


func _ready() -> void:
	_test_unreachable_goal_inside_canonicalizes_path_target()
	_test_many_units_one_point_avoids_overlap()
	_test_drop_obstacle_on_unit_pushes_or_fails()
	_test_command_outside_map_clamps_path_target()
	_test_formation_packing_keeps_units_apart()
	_test_progressive_seal_all_paths_bounds_replans()
	_test_seal_behind_unit_bounds_replans()
	_test_goal_blocked_at_arrival_canonicalizes_path_target()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - 0ad rts lab edge cases")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


# Contract: commanding the centre of a static obstacle must canonicalize the
# resolved path_target away from the requested target. Without canonicalization
# every active unit would walk into the wall.
func _test_unreachable_goal_inside_canonicalizes_path_target() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.set_group_target(Vector2(360.0, 210.0))
	_run_world_steps(world, 240, true)
	var separated := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(unit.path_target) > 0.5:
			separated += 1
	if separated <= 0:
		_failures.append("unreachable-goal: expected at least one unit with path_target ≠ target, all %d match" % world.get_mobile_units().size())


# Contract: ten units commanded to the same point must not catastrophically
# overlap. Threshold 8 px is "no more than 75% of one radius (11 px) of
# overlap": severe enough to be a visible bug, loose enough to not regress on
# the current push policy (observed ~5.6 px in this scenario; tighten when
# the 0 A.D. CCmpUnitMotionManager::Push pressure scaling lands).
func _test_many_units_one_point_avoids_overlap() -> void:
	var world := ZeroAdRtsLabWorld.new()
	_add_mobile_unit(world, "blue_6", Vector2(82.0, 170.0))
	_add_mobile_unit(world, "blue_7", Vector2(82.0, 250.0))
	_add_mobile_unit(world, "blue_8", Vector2(118.0, 170.0))
	_add_mobile_unit(world, "blue_9", Vector2(118.0, 250.0))
	world.set_group_target(Vector2(580.0, 210.0))
	_run_world_steps(world, 420, true)
	var max_overlap := _max_mobile_overlap(world)
	if max_overlap > 8.0:
		_failures.append("many-units-one-point: expected max_pair_overlap ≤ 8 px (catastrophic-overlap guard), got %.2f" % max_overlap)


# Contract: dropping a static obstacle on a moving unit must end with the
# unit either pushed clear or marked move_failed. Sitting inside the static
# obstacle clearance ring without acknowledging failure is the bug.
func _test_drop_obstacle_on_unit_pushes_or_fails() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.set_group_target(DEFAULT_TARGET)
	_run_world_steps(world, 20, false)
	var blue_0 := world.get_unit("blue_0")
	if blue_0 == null:
		_failures.append("drop-obstacle: missing blue_0")
		return
	world.add_static_obstacle(blue_0.position, Vector2(60.0, 60.0))
	_run_world_steps(world, 160, true)
	var inside_static := false
	for obstacle in world.obstacles:
		if obstacle.contains_point_with_clearance(blue_0.position, blue_0.radius):
			inside_static = true
			break
	if inside_static and not blue_0.move_failed:
		_failures.append("drop-obstacle: blue_0 sits inside static obstacle without move_failed at %s" % str(blue_0.position))


# Contract: an off-map command must canonicalize each unit's path_target to a
# point inside the map (with a 1-px tolerance). Without clamping the unit
# would chase a coordinate that no navcell can resolve.
func _test_command_outside_map_clamps_path_target() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var off_map := Vector2(1500.0, 500.0)
	world.set_group_target(off_map)
	_run_world_steps(world, 180, true)
	var map_size := world.map_size
	var bad_ids: Array[String] = []
	for unit in world.get_mobile_units():
		var path_target := unit.path_target
		if (path_target.x > map_size.x + 1.0
				or path_target.y > map_size.y + 1.0
				or path_target.x < -1.0
				or path_target.y < -1.0):
			bad_ids.append("%s=%s" % [unit.id, str(path_target)])
	if not bad_ids.is_empty():
		_failures.append("command-outside-map: path_target out of %s for %s" % [str(map_size), str(bad_ids)])


# Contract: a tight formation moving as a control group must not collapse
# into overlapping units. Keeping a non-trivial pair distance is the visible
# evidence that formation slots are honoured.
func _test_formation_packing_keeps_units_apart() -> void:
	var world := ZeroAdRtsLabWorld.new()
	_add_mobile_unit(world, "blue_6", Vector2(82.0, 170.0))
	_add_mobile_unit(world, "blue_7", Vector2(82.0, 250.0))
	_add_mobile_unit(world, "blue_8", Vector2(118.0, 170.0))
	_add_mobile_unit(world, "blue_9", Vector2(118.0, 250.0))
	world.set_group_target(Vector2(560.0, 75.0))
	_run_world_steps(world, 420, true)
	var min_dist := _min_mobile_pair_distance(world)
	if min_dist < 5.0:
		_failures.append("formation-packing: expected min pair distance ≥ 5 px, got %.2f" % min_dist)


# Contract: when every navigable corridor is sealed off, replans must be
# bounded — not runaway. Threshold ≤ 600 over 260 ticks ≈ 100 retries / mobile
# unit, well above the steady-state ~1.5 req/tick observed when active units
# are still searching. Whether units actually arrive is allowed to vary.
func _test_progressive_seal_all_paths_bounds_replans() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.set_group_target(DEFAULT_TARGET)
	_run_world_steps(world, 30, false)
	world.add_static_obstacle(Vector2(340.0, 5.0), Vector2(300.0, 30.0))
	_run_world_steps(world, 30, false)
	world.add_static_obstacle(Vector2(340.0, 415.0), Vector2(300.0, 30.0))
	_run_world_steps(world, 30, false)
	world.add_static_obstacle(Vector2(340.0, 130.0), Vector2(40.0, 30.0))
	_run_world_steps(world, 30, false)
	world.add_static_obstacle(Vector2(340.0, 290.0), Vector2(40.0, 30.0))
	var seal_metrics := world.get_metrics()
	_run_world_steps(world, 260, true)
	var metrics := world.get_metrics()
	var requests := _request_delta(metrics, seal_metrics)
	if requests >= 600:
		_failures.append("progressive-seal: expected ≤ 600 path requests after final seal (runaway-replan guard), got %d" % requests)


# Contract: with a wall ahead and behind the formation, replans must be
# bounded — same runaway-replan guard as progressive-seal.
func _test_seal_behind_unit_bounds_replans() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.set_group_target(DEFAULT_TARGET)
	_run_world_steps(world, 30, false)
	world.add_static_obstacle(Vector2(480.0, 210.0), Vector2(40.0, 420.0))
	_run_world_steps(world, 20, false)
	world.add_static_obstacle(Vector2(180.0, 210.0), Vector2(40.0, 420.0))
	var seal_metrics := world.get_metrics()
	_run_world_steps(world, 320, true)
	var metrics := world.get_metrics()
	var requests := _request_delta(metrics, seal_metrics)
	if requests >= 600:
		_failures.append("seal-behind: expected ≤ 600 path requests after fore+aft seal (runaway-replan guard), got %d" % requests)


# Contract: dropping an obstacle exactly on the goal mid-arrival must
# canonicalize at least one unit's path_target away from the now-blocked goal.
func _test_goal_blocked_at_arrival_canonicalizes_path_target() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.set_group_target(DEFAULT_TARGET)
	_run_world_steps(world, 200, false)
	world.add_static_obstacle(DEFAULT_TARGET, Vector2(60.0, 60.0))
	_run_world_steps(world, 260, true)
	var separated := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(unit.path_target) > 0.5:
			separated += 1
	if separated <= 0:
		_failures.append("goal-blocked-at-arrival: expected at least one unit with path_target ≠ target")


# ---------------------------------------------------------------------------
# Helpers


func _run_world_steps(world: ZeroAdRtsLabWorld, count: int, stop_on_arrival: bool) -> void:
	for _i in range(count):
		world.step(DT)
		if stop_on_arrival and _all_mobile_arrived(world):
			break


func _all_mobile_arrived(world: ZeroAdRtsLabWorld) -> bool:
	for unit in world.get_mobile_units():
		if not unit.arrived:
			return false
	return true


func _add_mobile_unit(world: ZeroAdRtsLabWorld, unit_id: String, position: Vector2) -> void:
	world.units.append(ZeroAdRtsLabUnit.new(unit_id, "blue", position, 11.0, 96.0, true))
	world.pathfinder.refresh_dynamic_units(world.units)
	world.clear_traces()


func _max_mobile_overlap(world: ZeroAdRtsLabWorld) -> float:
	var mobile_units := world.get_mobile_units()
	var max_overlap := 0.0
	for i in range(mobile_units.size()):
		for j in range(i + 1, mobile_units.size()):
			var first_unit := mobile_units[i]
			var second_unit := mobile_units[j]
			var dist: float = first_unit.position.distance_to(second_unit.position)
			var overlap := maxf(0.0, first_unit.radius + second_unit.radius - dist)
			max_overlap = maxf(max_overlap, overlap)
	return max_overlap


func _min_mobile_pair_distance(world: ZeroAdRtsLabWorld) -> float:
	var mobile_units := world.get_mobile_units()
	if mobile_units.size() < 2:
		return 0.0
	var min_dist := INF
	for i in range(mobile_units.size()):
		for j in range(i + 1, mobile_units.size()):
			min_dist = minf(min_dist, mobile_units[i].position.distance_to(mobile_units[j].position))
	return min_dist


func _request_delta(metrics: Dictionary, base: Dictionary) -> int:
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base.get("short_path_requests", 0))
	var long_delta := int(metrics.get("long_path_requests", 0)) - int(base.get("long_path_requests", 0))
	return short_delta + long_delta
