extends Node


const UNIT_COUNT: int = 32
const STATIC_WALL_SHORT_PATH_MAX_USEC: int = 8000

var _failures: Array[String] = []


func _ready() -> void:
	_test_path_requests_are_budgeted()
	_test_idle_step_skips_dynamic_refresh_and_push()
	_test_push_adjust_uses_spatial_bucket()
	_test_static_wall_short_path_does_not_burn_frame()
	_test_partial_wall_with_gap_arrives_with_fast_short_path()

	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - 0ad rts lab budget")
		get_tree().quit(0)
	else:
		var msg := "SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures)
		printerr(msg)
		print(msg)
		get_tree().quit(1)


func _test_path_requests_are_budgeted() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = _make_grid_units(UNIT_COUNT, false)
	world.pathfinder.rebuild_context(world.obstacles)
	world.clear_traces()

	world.set_group_target(Vector2(650.0, 210.0))
	var queued_before := world.pathfinder.path_queue_diagnostics()
	if int(queued_before.get("pending_count", 0)) != UNIT_COUNT:
		_failures.append("budget: expected all unit paths queued before stepping")
		return

	world.step(0.1)
	var queued_after_one := world.pathfinder.path_queue_diagnostics()
	var processed_after_one := int(queued_after_one.get("processed_count", 0))
	if processed_after_one > ZeroAdRtsLabWorld.PATH_REQUEST_BUDGET_PER_TICK:
		_failures.append("budget: processed more than per-tick budget after one step")
	if int(queued_after_one.get("pending_count", 0)) < UNIT_COUNT - ZeroAdRtsLabWorld.PATH_REQUEST_BUDGET_PER_TICK:
		_failures.append("budget: queue drained too much in one step")

	for _i in range(32):
		world.step(0.1)
		if int(world.pathfinder.path_queue_diagnostics().get("pending_count", 0)) == 0:
			break
	if int(world.pathfinder.path_queue_diagnostics().get("pending_count", 0)) != 0:
		_failures.append("budget: queued long paths did not drain over later frames")
	var processed_total := int(world.pathfinder.path_queue_diagnostics().get("processed_count", 0))
	if processed_total < UNIT_COUNT:
		_failures.append("budget: expected queued long-path requests to be processed")


func _test_idle_step_skips_dynamic_refresh_and_push() -> void:
	var world := ZeroAdRtsLabWorld.new()
	var base_dynamic_refreshes := world.pathfinder.dynamic_refreshes
	var sentinel_push_checks := 123
	world.motion.push_pair_checks = sentinel_push_checks

	world.step(0.1)
	world.step(0.1)

	if world.pathfinder.dynamic_refreshes != base_dynamic_refreshes:
		_failures.append("idle-budget: expected idle steps to skip dynamic refresh")
	if world.motion.push_pair_checks != sentinel_push_checks:
		_failures.append("idle-budget: expected idle steps to skip push adjust")


func _test_push_adjust_uses_spatial_bucket() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.obstacles = []
	world.units = _make_grid_units(64)
	world.pathfinder.rebuild_context(world.obstacles)

	world.motion.apply_push_adjust(world.units, world.pathfinder)
	var naive_pair_count := world.units.size() * (world.units.size() - 1) / 2
	if world.motion.push_pair_checks >= naive_pair_count / 2:
		_failures.append("push-grid: pair checks too close to full pair scan (%d/%d)" % [
			world.motion.push_pair_checks,
			naive_pair_count,
		])
	if world.motion.push_grid_cells <= 1:
		_failures.append("push-grid: expected units to be distributed across buckets")


func _test_static_wall_short_path_does_not_burn_frame() -> void:
	var world := ZeroAdRtsLabWorld.new()
	for y_value in [110.0, 165.0, 215.0, 270.0, 325.0]:
		world.add_static_obstacle(Vector2(400.0, y_value), Vector2(40.0, 60.0))
	world.set_group_target(Vector2(610.0, 210.0))
	var base_metrics := world.get_metrics()
	var max_short_compute_usec := 0
	var max_profile: Dictionary = {}
	for _i in range(360):
		world.step(1.0 / 60.0)
		for request in world.last_step_profile.get("path_request_batch", []):
			var request_data: Dictionary = request as Dictionary
			if String(request_data.get("kind", "")) != "short":
				continue
			var compute_usec := int(request_data.get("compute_usec", 0))
			if compute_usec > max_short_compute_usec:
				max_short_compute_usec = compute_usec
				max_profile = world.last_step_profile.duplicate(true)
	var metrics := world.get_metrics()
	var short_delta := int(metrics.get("short_path_requests", 0)) - int(base_metrics.get("short_path_requests", 0))
	var long_delta := int(metrics.get("long_path_requests", 0)) - int(base_metrics.get("long_path_requests", 0))
	if max_short_compute_usec > STATIC_WALL_SHORT_PATH_MAX_USEC:
		_failures.append("static-wall-short-path: short path burned %dus, profile=%s" % [
			max_short_compute_usec,
			str(max_profile),
		])
	if short_delta + long_delta > 20:
		_failures.append("static-wall-short-path: expected bounded replans, short=%d long=%d metrics=%s" % [
			short_delta,
			long_delta,
			str(metrics),
		])


func _test_partial_wall_with_gap_arrives_with_fast_short_path() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.add_static_obstacle(Vector2(400.0, 132.0), Vector2(40.0, 105.0))
	world.add_static_obstacle(Vector2(400.0, 287.0), Vector2(40.0, 105.0))
	world.set_group_target(Vector2(560.0, 210.0))
	var max_short_compute_usec := 0
	var max_profile: Dictionary = {}
	for _i in range(500):
		world.step(1.0 / 60.0)
		for request in world.last_step_profile.get("path_request_batch", []):
			var request_data: Dictionary = request as Dictionary
			if String(request_data.get("kind", "")) != "short":
				continue
			var compute_usec := int(request_data.get("compute_usec", 0))
			if compute_usec > max_short_compute_usec:
				max_short_compute_usec = compute_usec
				max_profile = world.last_step_profile.duplicate(true)
		if _all_mobile_arrived(world):
			break
	if not _all_mobile_arrived(world):
		_failures.append("partial-wall-gap: expected all mobile units to arrive, metrics=%s" % str(world.get_metrics()))
	if max_short_compute_usec > STATIC_WALL_SHORT_PATH_MAX_USEC:
		_failures.append("partial-wall-gap: short path burned %dus, profile=%s" % [
			max_short_compute_usec,
			str(max_profile),
		])


func _make_grid_units(count: int, blocks_pathfinding: bool = true) -> Array[ZeroAdRtsLabUnit]:
	var result: Array[ZeroAdRtsLabUnit] = []
	for i in range(count):
		var x := 48.0 + float(i % 8) * 70.0
		@warning_ignore("integer_division")
		var y := 52.0 + float(i / 8) * 54.0
		var unit := ZeroAdRtsLabUnit.new("blue_%02d" % i, "blue", Vector2(x, y), 10.0, 96.0, true)
		unit.blocks_pathfinding = blocks_pathfinding
		result.append(unit)
	return result


func _all_mobile_arrived(world: ZeroAdRtsLabWorld) -> bool:
	for unit in world.get_mobile_units():
		if not unit.arrived:
			return false
	return true
