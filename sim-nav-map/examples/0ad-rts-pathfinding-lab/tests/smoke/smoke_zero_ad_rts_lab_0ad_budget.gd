extends Node


const UNIT_COUNT: int = 32

var _failures: Array[String] = []


func _ready() -> void:
	_test_path_requests_are_budgeted()
	_test_idle_step_skips_dynamic_refresh_and_push()
	_test_push_adjust_uses_spatial_bucket()

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
	world.units = _make_grid_units(UNIT_COUNT)
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


func _make_grid_units(count: int) -> Array[ZeroAdRtsLabUnit]:
	var result: Array[ZeroAdRtsLabUnit] = []
	for i in range(count):
		var x := 48.0 + float(i % 8) * 70.0
		@warning_ignore("integer_division")
		var y := 52.0 + float(i / 8) * 54.0
		result.append(ZeroAdRtsLabUnit.new("blue_%02d" % i, "blue", Vector2(x, y), 10.0, 96.0, true))
	return result
