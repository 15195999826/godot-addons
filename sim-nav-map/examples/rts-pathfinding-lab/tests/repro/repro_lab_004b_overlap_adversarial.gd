extends Node

# LAB-004 (adversarial): overlap matrix lock-in under stress
#
# The existing repro_lab_004_overlap_policy locks the *default* arrival
# case (max idle-idle overlap < 1.0 px). This adversarial smoke scripts
# the codex Issue 4 stress case the original LAB-004 issue text called
# out: edge-adjacent target + obstacle edits during arrival. Asserts the
# overlap matrix thresholds defined in rts_pathfinding_lab_world.gd hold:
#   - active-vs-active: may briefly exceed ARRIVE_MAX_OVERLAP while
#     moving units negotiate; bounded by OVERLAP_PUSH_MAX_PER_FRAME_CELLS
#     · cell_size per unit per frame.
#   - idle-vs-idle: must stay ≤ ARRIVE_MAX_OVERLAP after settle.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_004b_overlap_adversarial.tscn

const LabObstacle := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_obstacle.gd")
const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - LAB-004 adversarial overlap policy locked in")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - LAB-004 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var world := LabWorld.new()
	world.setup_default()

	# Edge-adjacent target near the top-right corner forces all 6 units to
	# pack into a small area against the map edge. Formation slot offsets
	# spread them out, but several units crowd the same edge column.
	var target := Vector2(640.0, 36.0)
	world.set_group_target(target)

	# Drop additional obstacles partway through arrival to exercise the
	# blocker-near-target packing scenario. Positions chosen to leave a
	# narrow lane to the target while crowding the approach.
	var dt := 1.0 / 60.0
	var max_active_overlap := 0.0
	var arrival_step := -1
	var max_steps := 400
	for step_idx in range(max_steps):
		match step_idx:
			40:
				world.add_static_obstacle(Vector2(560.0, 130.0), Vector2(60.0, 60.0))
			80:
				world.add_static_obstacle(Vector2(605.0, 90.0), Vector2(40.0, 40.0))
		world.step(dt)
		var active_overlap := _max_pair_overlap(world)
		if active_overlap > max_active_overlap:
			max_active_overlap = active_overlap
		if world.all_mobile_arrived() and arrival_step < 0:
			arrival_step = step_idx
			break
	# The smoke locks in the OVERLAP matrix, not the arrival outcome —
	# edge-adjacent + obstacle-edited targets are intentionally hostile to
	# arrival (LAB-001 / LAB-003 territory). What we lock here: even when
	# units DON'T fully arrive, the overlap policy must not spike past the
	# active-active threshold mid-flight, and units that DO settle must
	# respect the idle-idle bound. Run extra ticks regardless of arrival
	# state to settle whoever can.
	for _i in range(60):
		world.step(dt)
		var current_overlap := _max_pair_overlap(world)
		if current_overlap > max_active_overlap:
			max_active_overlap = current_overlap

	var settled_overlap := _max_pair_overlap(world)
	var active_active_threshold := 6.0
	var idle_idle_threshold := LabWorld.ARRIVE_MAX_OVERLAP

	# Only enforce idle-idle on units that actually idled. Units still
	# active at the end of the run are accounted for under active-active.
	var idle_overlap := _max_idle_pair_overlap(world)

	print(
		"LAB-004 adversarial: arrived_at_step=%d, max_active_pair_overlap=%.2f px (≤ %.1f), max_idle_pair_overlap=%.2f px (≤ %.1f), settled_any_pair_overlap=%.2f px"
		% [arrival_step, max_active_overlap, active_active_threshold, idle_overlap, idle_idle_threshold, settled_overlap]
	)
	if max_active_overlap > active_active_threshold:
		_failures.append(
			"active-active overlap matrix breach: %.2f px > %.1f px"
			% [max_active_overlap, active_active_threshold]
		)
	if idle_overlap > idle_idle_threshold + 0.01:
		_failures.append(
			"idle-idle overlap matrix breach after settle: %.2f px > %.1f px"
			% [idle_overlap, idle_idle_threshold]
		)


func _max_idle_pair_overlap(world: RtsPathfindingLabWorld) -> float:
	var idles: Array[RtsPathfindingLabUnit] = []
	for unit in world.get_mobile_units():
		if unit.arrived and not unit.has_move_order:
			idles.append(unit)
	var max_overlap := 0.0
	for i in range(idles.size()):
		for j in range(i + 1, idles.size()):
			var a := idles[i]
			var b := idles[j]
			var overlap := a.radius + b.radius - a.position.distance_to(b.position)
			if overlap > max_overlap:
				max_overlap = overlap
	return max_overlap


func _max_pair_overlap(world: RtsPathfindingLabWorld) -> float:
	var mobile := world.get_mobile_units()
	var max_overlap := 0.0
	for i in range(mobile.size()):
		for j in range(i + 1, mobile.size()):
			var a := mobile[i]
			var b := mobile[j]
			var overlap := a.radius + b.radius - a.position.distance_to(b.position)
			if overlap > max_overlap:
				max_overlap = overlap
	return max_overlap
