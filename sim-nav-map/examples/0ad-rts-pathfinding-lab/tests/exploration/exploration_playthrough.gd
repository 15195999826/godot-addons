extends Node

# 0AD exploration playthrough.
#
# Observation-only harness for the 0ad-rts-pathfinding-lab. It drives realistic
# user operations, prints EXPLORE_OBSERVATION dictionaries, and exits 0 for the
# curated pass. Do not add this scene to test_groups.json; extract focused smoke
# tests from any reproduced bug after the motion rule is understood.
#
# Run:
# godot --headless --path . addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/exploration/exploration_playthrough.tscn
#
# Optional fuzz:
# godot --headless --path . addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/exploration/exploration_playthrough.tscn -- --fuzz --seed=42 --iterations=10 --ticks=240


const DT := 1.0 / 60.0
const DEFAULT_TARGET := Vector2(610.0, 210.0)
const FUZZ_DEFAULT_SEED := 42
const FUZZ_DEFAULT_ITERATIONS := 10
const FUZZ_DEFAULT_TICKS := 240
const FUZZ_MAX_JUMP_PX := 80.0
const FUZZ_MAP_MARGIN := 1.0


var _phase_results: Array[Dictionary] = []


func _ready() -> void:
	if _cli_has("--fuzz"):
		_fuzz_mode_main()
		return
	print("=== 0AD EXPLORATION PLAYTHROUGH BEGIN ===")
	_phase_idle_default_scene()
	_phase_baseline_open_movement()
	_phase_user_reported_runaway_repath()
	_phase_unreachable_goal_inside()
	_phase_fully_blocked_path()
	_phase_many_units_one_point()
	_phase_drop_obstacle_on_unit()
	_phase_command_outside_map()
	_phase_rapid_obstacle_thrash()
	_phase_partial_wall_with_gap()
	_phase_dynamic_blocker_swarm()
	_phase_formation_packing()
	_phase_progressive_seal_all_paths()
	_phase_seal_behind_unit()
	_phase_gap_close_mid_travel()
	_phase_goal_blocked_at_arrival()
	_phase_alternating_corridor_seal()
	_print_summary_table()
	print("=== 0AD EXPLORATION PLAYTHROUGH END ===")
	get_tree().quit(0)


func _phase_idle_default_scene() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "0_idle_default_scene")
	observer.run_steps(180, false)
	observer.note("expected", "idle default scene should skip dynamic refresh, movement, and push")
	_record(observer.finish())


func _phase_baseline_open_movement() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "1_baseline_open_movement")
	observer.run_steps(300, true)
	observer.note("expected", "units should traverse default scene without runaway replans")
	_record(observer.finish())


func _phase_user_reported_runaway_repath() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "2_user_reported_runaway_repath")
	observer.run_steps(67, false)
	world.set_units_target(["blue_0", "blue_1"], Vector2(316.0, 326.0))
	observer.note("event_67", "move selected blue_0/blue_1 to (316, 326)")
	observer.run_steps(29, false)
	world.set_units_target(["blue_0", "blue_1"], Vector2(350.0, 311.0))
	observer.note("event_96", "move selected blue_0/blue_1 to (350, 311)")
	observer.run_steps(620, true)
	observer.note("expected", "active units should either arrive, fail cleanly, or stop growing path requests")
	_record(observer.finish())


func _phase_unreachable_goal_inside() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	var unreachable := Vector2(360.0, 210.0)
	world.set_group_target(unreachable)
	var observer := PhaseObserver.new(world, "3_unreachable_goal_inside")
	observer.run_steps(240, true)
	var separated := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(unit.path_target) > 0.5:
			separated += 1
	observer.note("event", "command target = center of default center_block")
	observer.note("target_path_target_separated", "%d/%d units" % [separated, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_fully_blocked_path() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	for y_value in [110.0, 165.0, 215.0, 270.0, 325.0]:
		world.add_static_obstacle(Vector2(400.0, y_value), Vector2(40.0, 60.0))
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "4_fully_blocked_path")
	observer.run_steps(360, true)
	observer.note("event", "vertical wall stack at x=400 fully separates start from target")
	_record(observer.finish())


func _phase_many_units_one_point() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	_add_mobile_unit(world, "blue_2", Vector2(82.0, 170.0))
	_add_mobile_unit(world, "blue_3", Vector2(82.0, 250.0))
	_add_mobile_unit(world, "blue_4", Vector2(118.0, 170.0))
	_add_mobile_unit(world, "blue_5", Vector2(118.0, 250.0))
	world.set_group_target(Vector2(580.0, 210.0))
	var observer := PhaseObserver.new(world, "5_many_units_one_point")
	observer.run_steps(420, true)
	observer.note("max_pair_overlap_px", "%.2f" % _max_mobile_overlap(world))
	_record(observer.finish())


func _phase_drop_obstacle_on_unit() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "6_drop_obstacle_on_unit")
	observer.run_steps(20, false)
	var blue_0 := world.get_unit("blue_0")
	if blue_0 != null:
		world.add_static_obstacle(blue_0.position, Vector2(60.0, 60.0))
		observer.note("event", "60x60 static obstacle dropped on blue_0 at %s" % str(blue_0.position))
	observer.run_steps(160, true)
	_record(observer.finish())


func _phase_command_outside_map() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	var off_map := Vector2(1500.0, 500.0)
	world.set_group_target(off_map)
	var observer := PhaseObserver.new(world, "7_command_outside_map")
	observer.run_steps(180, true)
	var clamped_count := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(off_map) > 50.0:
			clamped_count += 1
	observer.note("event", "command target = (1500, 500)")
	observer.note("targets_clamped_or_canonicalized", "%d/%d units" % [clamped_count, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_rapid_obstacle_thrash() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "8_rapid_obstacle_thrash")
	observer.run_steps(5, false)
	var blocker_x := 180.0
	var add_count := 0
	var remove_count := 0
	for i in range(360):
		if i % 6 == 0:
			var y_band := 195.0 if int(i / 6) % 2 == 0 else 225.0
			world.add_blocker(Vector2(blocker_x, y_band), 14.0)
			add_count += 1
			blocker_x += 18.0
			if blocker_x > 580.0:
				blocker_x = 180.0
		if i % 9 == 0 and i > 0:
			world.remove_nearest_editable(Vector2(blocker_x - 24.0, 210.0))
			remove_count += 1
		if i % 30 == 0 and i > 0:
			world.set_group_target(DEFAULT_TARGET)
		observer.step_once()
	observer.note("blockers_added", str(add_count))
	observer.note("blockers_removed", str(remove_count))
	_record(observer.finish())


func _phase_partial_wall_with_gap() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.add_static_obstacle(Vector2(400.0, 132.0), Vector2(40.0, 105.0))
	world.add_static_obstacle(Vector2(400.0, 287.0), Vector2(40.0, 105.0))
	world.set_group_target(Vector2(560.0, 210.0))
	var observer := PhaseObserver.new(world, "9_partial_wall_with_gap")
	observer.run_steps(460, true)
	observer.note("event", "wall at x=400 with 50 px gap centered y=210")
	_record(observer.finish())


func _phase_dynamic_blocker_swarm() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	var blocker_positions: Array[Vector2] = [
		Vector2(280.0, 180.0),
		Vector2(280.0, 240.0),
		Vector2(380.0, 165.0),
		Vector2(380.0, 255.0),
		Vector2(480.0, 195.0),
		Vector2(480.0, 225.0),
	]
	for blocker_pos in blocker_positions:
		world.add_blocker(blocker_pos, 14.0)
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "10_dynamic_blocker_swarm")
	observer.run_steps(460, true)
	observer.note("event", "%d circular blockers seeded in corridor" % blocker_positions.size())
	_record(observer.finish())


func _phase_formation_packing() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	_add_mobile_unit(world, "blue_2", Vector2(82.0, 170.0))
	_add_mobile_unit(world, "blue_3", Vector2(82.0, 250.0))
	_add_mobile_unit(world, "blue_4", Vector2(118.0, 170.0))
	_add_mobile_unit(world, "blue_5", Vector2(118.0, 250.0))
	world.set_group_target(Vector2(560.0, 75.0))
	var observer := PhaseObserver.new(world, "11_formation_packing")
	observer.run_steps(420, true)
	observer.note("formation_min_pair_dist_px", "%.2f" % _min_mobile_pair_distance(world))
	observer.note("formation_max_pair_dist_px", "%.2f" % _max_mobile_pair_distance(world))
	_record(observer.finish())


func _phase_progressive_seal_all_paths() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "12_progressive_seal_all_paths")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 5.0), Vector2(300.0, 30.0))
	observer.note("event_30", "top edge sealed")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 415.0), Vector2(300.0, 30.0))
	observer.note("event_60", "bottom edge sealed")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 130.0), Vector2(40.0, 30.0))
	observer.note("event_90", "upper detour sealed")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 290.0), Vector2(40.0, 30.0))
	observer.note("event_120", "lower detour sealed")
	observer.run_steps(260, true)
	observer.note("units_far_from_goal", _units_far_from(world, DEFAULT_TARGET, 50.0))
	_record(observer.finish())


func _phase_seal_behind_unit() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "13_seal_behind_unit")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(480.0, 210.0), Vector2(40.0, 420.0))
	observer.note("event_30", "forward wall at x=480")
	observer.run_steps(20, false)
	world.add_static_obstacle(Vector2(180.0, 210.0), Vector2(40.0, 420.0))
	observer.note("event_50", "rear wall at x=180")
	observer.run_steps(320, true)
	observer.note("units_far_from_goal", _units_far_from(world, DEFAULT_TARGET, 50.0))
	_record(observer.finish())


func _phase_gap_close_mid_travel() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.add_static_obstacle(Vector2(520.0, 132.0), Vector2(40.0, 105.0))
	world.add_static_obstacle(Vector2(520.0, 287.0), Vector2(40.0, 105.0))
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "14_gap_close_mid_travel")
	observer.note("event_0", "wall column at x=520 with 50 px gap")
	observer.run_steps(80, false)
	world.add_static_obstacle(Vector2(520.0, 210.0), Vector2(40.0, 50.0))
	observer.note("event_80", "gap plugged")
	observer.run_steps(300, true)
	_record(observer.finish())


func _phase_goal_blocked_at_arrival() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "15_goal_blocked_at_arrival")
	observer.run_steps(200, false)
	var min_dist_at_drop := INF
	for unit in world.get_mobile_units():
		if unit.has_move_order:
			min_dist_at_drop = minf(min_dist_at_drop, unit.position.distance_to(DEFAULT_TARGET))
	world.add_static_obstacle(DEFAULT_TARGET, Vector2(60.0, 60.0))
	observer.note("event_200", "60x60 wall dropped on goal; closest active unit %.1f px away" % min_dist_at_drop)
	observer.run_steps(260, true)
	var separated := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(unit.path_target) > 0.5:
			separated += 1
	observer.note("target_path_target_separated", "%d/%d units" % [separated, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_alternating_corridor_seal() -> void:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var observer := PhaseObserver.new(world, "16_alternating_corridor_seal")
	var upper_pos := Vector2(340.0, 130.0)
	var lower_pos := Vector2(340.0, 290.0)
	var seal_size := Vector2(40.0, 30.0)
	var upper_closed := false
	var swap_count := 0
	for i in range(360):
		if i % 30 == 0:
			if upper_closed:
				world.remove_nearest_editable(upper_pos, 80.0)
				world.add_static_obstacle(lower_pos, seal_size)
				upper_closed = false
			else:
				world.remove_nearest_editable(lower_pos, 80.0)
				world.add_static_obstacle(upper_pos, seal_size)
				upper_closed = true
			swap_count += 1
		observer.step_once()
	observer.note("seal_swaps", str(swap_count))
	observer.note("final_state", "upper_closed=%s" % str(upper_closed))
	_record(observer.finish())


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


func _max_mobile_pair_distance(world: ZeroAdRtsLabWorld) -> float:
	var mobile_units := world.get_mobile_units()
	var max_dist := 0.0
	for i in range(mobile_units.size()):
		for j in range(i + 1, mobile_units.size()):
			max_dist = maxf(max_dist, mobile_units[i].position.distance_to(mobile_units[j].position))
	return max_dist


func _units_far_from(world: ZeroAdRtsLabWorld, point: Vector2, threshold: float) -> String:
	var far_count := 0
	var mobile_count := world.get_mobile_units().size()
	for unit in world.get_mobile_units():
		if unit.position.distance_to(point) > threshold:
			far_count += 1
	return "%d/%d" % [far_count, mobile_count]


class PhaseObserver:
	const STUCK_TICK_THRESHOLD := 30
	const STUCK_MOVEMENT_THRESHOLD_PX := 1.0
	const RUNAWAY_REPATH_THRESHOLD := 40
	const RUNAWAY_BLOCKED_THRESHOLD := 80
	const MAX_SLOW_FRAME_LOG_ENTRIES := 24
	const PerfSummaryScript := preload("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_perf_summary.gd")

	var world: ZeroAdRtsLabWorld
	var phase_name: String
	var prev_positions: Dictionary = {}
	var total_step_usec: int = 0
	var max_step_usec: int = 0
	var max_step_at: int = -1
	var max_step_profile: Dictionary = {}
	var max_short_compute_usec: int = 0
	var max_short_profile: Dictionary = {}
	var step_usec_samples: Array[int] = []
	var idle_step_usec_samples: Array[int] = []
	var step_profiles: Array[Dictionary] = []
	var idle_step_profiles: Array[Dictionary] = []
	var slow_frames: Array[Dictionary] = []
	var max_jump_px: float = 0.0
	var max_jump_unit: String = ""
	var max_jump_at: int = -1
	var step_count: int = 0
	var arrived_at_step: int = -1
	var notes: Dictionary = {}
	var last_movement_step: Dictionary = {}
	var pathless_active_ticks: int = 0
	var runaway_repath_ticks: int = 0
	var saw_move_order: bool = false
	var _step_t0: int = 0
	var _base_metrics: Dictionary = {}
	var _last_request_total: int = 0
	var _last_blocked_moves: int = 0

	func _init(p_world: ZeroAdRtsLabWorld, p_phase_name: String) -> void:
		world = p_world
		phase_name = p_phase_name
		for unit in world.get_mobile_units():
			prev_positions[unit.id] = unit.position
			last_movement_step[unit.id] = 0
		_base_metrics = world.get_metrics()
		_last_request_total = _request_total(_base_metrics)
		_last_blocked_moves = int(_base_metrics.get("blocked_moves", 0))

	func before_step() -> void:
		_step_t0 = Time.get_ticks_usec()

	func after_step() -> void:
		var step_usec := Time.get_ticks_usec() - _step_t0
		total_step_usec += step_usec
		var profile := world.last_step_profile.duplicate(true)
		step_usec_samples.append(step_usec)
		step_profiles.append(profile)
		if PerfSummaryScript.is_idle_profile(profile):
			idle_step_usec_samples.append(step_usec)
			idle_step_profiles.append(profile)
		if step_usec > max_step_usec:
			max_step_usec = step_usec
			max_step_at = step_count
			max_step_profile = world.last_step_profile.duplicate(true)
		if step_usec >= PerfSummaryScript.DEFAULT_SLOW_FRAME_THRESHOLD_USEC:
			_record_slow_frame(step_usec)
		for request in world.last_step_profile.get("path_request_batch", []):
			var request_data: Dictionary = request as Dictionary
			if String(request_data.get("kind", "")) != "short":
				continue
			var compute_usec := int(request_data.get("compute_usec", 0))
			if compute_usec > max_short_compute_usec:
				max_short_compute_usec = compute_usec
				max_short_profile = world.last_step_profile.duplicate(true)
		for unit in world.get_mobile_units():
			if unit.has_move_order:
				saw_move_order = true
			if not prev_positions.has(unit.id):
				prev_positions[unit.id] = unit.position
				last_movement_step[unit.id] = step_count
			var prev_pos: Vector2 = prev_positions.get(unit.id, unit.position)
			var jump: float = unit.position.distance_to(prev_pos)
			if jump > max_jump_px:
				max_jump_px = jump
				max_jump_unit = unit.id
				max_jump_at = step_count
			if jump > STUCK_MOVEMENT_THRESHOLD_PX:
				last_movement_step[unit.id] = step_count
			prev_positions[unit.id] = unit.position
			if unit.has_move_order and not unit.arrived and not _unit_has_active_path(unit) and unit.pending_long_ticket == 0 and unit.pending_short_ticket == 0:
				pathless_active_ticks += 1
		var metrics := world.get_metrics()
		var request_total := _request_total(metrics)
		var blocked_moves := int(metrics.get("blocked_moves", 0))
		if request_total > _last_request_total and blocked_moves > _last_blocked_moves:
			runaway_repath_ticks += 1
		_last_request_total = request_total
		_last_blocked_moves = blocked_moves
		step_count += 1
		if saw_move_order and arrived_at_step < 0 and _world_all_mobile_arrived():
			arrived_at_step = step_count

	func step_once() -> void:
		before_step()
		world.step(DT)
		after_step()

	func run_steps(count: int, stop_on_arrival: bool) -> void:
		for _i in range(count):
			step_once()
			if stop_on_arrival and _world_all_mobile_arrived():
				break

	func note(key: String, value: String) -> void:
		notes[key] = value

	func finish() -> Dictionary:
		var metrics := world.get_metrics()
		var mobile_units := world.get_mobile_units()
		var arrived := 0
		var active := 0
		var stuck_ids: Array[String] = []
		var failed_total := 0
		for unit in mobile_units:
			failed_total += unit.failed_movements
			if unit.arrived:
				arrived += 1
				continue
			if unit.has_move_order:
				active += 1
				var last_moved: int = last_movement_step.get(unit.id, 0)
				if step_count - last_moved >= STUCK_TICK_THRESHOLD:
					stuck_ids.append(unit.id)
		var short_delta := int(metrics.get("short_path_requests", 0)) - int(_base_metrics.get("short_path_requests", 0))
		var long_delta := int(metrics.get("long_path_requests", 0)) - int(_base_metrics.get("long_path_requests", 0))
		var blocked_delta := int(metrics.get("blocked_moves", 0)) - int(_base_metrics.get("blocked_moves", 0))
		var avg_step_usec := float(total_step_usec) / float(maxi(step_count, 1))
		var perf_summary := PerfSummaryScript.summarize_steps(step_usec_samples, idle_step_usec_samples)
		var slow_summary := PerfSummaryScript.summarize_slow_frames(slow_frames)
		var stage_summary := PerfSummaryScript.summarize_stage_profiles(step_profiles, idle_step_profiles)
		var max_step_stage_classification := PerfSummaryScript.classify_step(max_step_profile)
		var result := {
			"phase": phase_name,
			"steps_run": step_count,
			"arrived": "%d/%d" % [arrived, mobile_units.size()],
			"arrived_at_step": arrived_at_step,
			"active_count": active,
			"avg_step_usec": "%.2f" % avg_step_usec,
			"warm_avg_step_usec": float(perf_summary.get("warm_avg_step_usec", 0.0)),
			"p95_step_usec": int(perf_summary.get("p95_step_usec", 0)),
			"p99_step_usec": int(perf_summary.get("p99_step_usec", 0)),
			"idle_avg_step_usec": float(perf_summary.get("idle_avg_step_usec", 0.0)),
			"warm_sample_count": int(perf_summary.get("warm_sample_count", 0)),
			"idle_sample_count": int(perf_summary.get("idle_sample_count", 0)),
			"percentile_scope": String(perf_summary.get("percentile_scope", "")),
			"slow_frame_count": int(slow_summary.get("slow_frame_count", 0)),
			"slow_frame_stage_counts": slow_summary.get("slow_frame_stage_counts", {}),
			"slow_frame_dominant_stage": String(slow_summary.get("slow_frame_dominant_stage", "none")),
			"slow_frames": slow_frames.duplicate(true),
			"stage_avg_usec": stage_summary.get("stage_avg_usec", {}),
			"warm_stage_avg_usec": stage_summary.get("warm_stage_avg_usec", {}),
			"idle_stage_avg_usec": stage_summary.get("idle_stage_avg_usec", {}),
			"dominant_stage": stage_summary.get("dominant_stage", {}),
			"warm_dominant_stage": stage_summary.get("warm_dominant_stage", {}),
			"idle_dominant_stage": stage_summary.get("idle_dominant_stage", {}),
			"max_step_usec": max_step_usec,
			"max_step_at": max_step_at,
			"max_step_stage_classification": max_step_stage_classification,
			"max_step_profile": max_step_profile,
			"max_short_compute_usec": max_short_compute_usec,
			"max_short_profile": max_short_profile,
			"max_jump_px": "%.2f" % max_jump_px,
			"max_jump_unit": max_jump_unit,
			"max_jump_at": max_jump_at,
			"short_requests": short_delta,
			"long_requests": long_delta,
			"blocked_moves": blocked_delta,
			"move_failures": int(metrics.get("move_failures", 0)) - int(_base_metrics.get("move_failures", 0)),
			"repath_suppressed": int(metrics.get("repath_suppressed", 0)) - int(_base_metrics.get("repath_suppressed", 0)),
			"obsolete_path_requests": int(metrics.get("obsolete_path_requests", 0)) - int(_base_metrics.get("obsolete_path_requests", 0)),
			"known_imperfect_paths": int(metrics.get("known_imperfect_paths", 0)) - int(_base_metrics.get("known_imperfect_paths", 0)),
			"known_imperfect_suppressed": int(metrics.get("known_imperfect_suppressed", 0)) - int(_base_metrics.get("known_imperfect_suppressed", 0)),
			"path_results_applied": int(metrics.get("path_results_applied", 0)) - int(_base_metrics.get("path_results_applied", 0)),
			"path_result_failures": int(metrics.get("path_result_failures", 0)) - int(_base_metrics.get("path_result_failures", 0)),
			"path_queue_pending": int(metrics.get("path_queue_pending", 0)),
			"path_queue_processed": int(metrics.get("path_queue_processed", 0)) - int(_base_metrics.get("path_queue_processed", 0)),
			"dynamic_refreshes": int(metrics.get("dynamic_refreshes", 0)) - int(_base_metrics.get("dynamic_refreshes", 0)),
			"stuck_count": stuck_ids.size(),
			"stuck_ids": stuck_ids,
			"pathless_active_ticks": pathless_active_ticks,
			"runaway_repath_ticks": runaway_repath_ticks,
			"failed_movements_total": failed_total,
			"notes": notes,
		}
		print("EXPLORE_OBSERVATION: %s" % str(result))
		return result

	func has_runaway_repath(result: Dictionary) -> bool:
		var request_total := int(result.get("short_requests", 0)) + int(result.get("long_requests", 0))
		return (
			request_total >= RUNAWAY_REPATH_THRESHOLD
			and int(result.get("blocked_moves", 0)) >= RUNAWAY_BLOCKED_THRESHOLD
			and int(result.get("active_count", 0)) > 0
			and int(result.get("path_result_failures", 0)) == 0
		)

	func _request_total(metrics: Dictionary) -> int:
		return int(metrics.get("short_path_requests", 0)) + int(metrics.get("long_path_requests", 0))

	func _world_all_mobile_arrived() -> bool:
		for unit in world.get_mobile_units():
			if not unit.arrived:
				return false
		return true

	func _unit_has_active_path(unit: ZeroAdRtsLabUnit) -> bool:
		return (
			(unit.long_path != null and not unit.long_path.is_empty())
			or (unit.short_path != null and not unit.short_path.is_empty())
		)

	func _record_slow_frame(step_usec: int) -> void:
		slow_frames.append({
			"step": step_count,
			"tick": int(world.last_step_profile.get("tick", world.tick_count)),
			"step_usec": step_usec,
			"stage_classification": PerfSummaryScript.classify_step(world.last_step_profile),
			"world_step_profile": world.last_step_profile.duplicate(true),
		})
		while slow_frames.size() > MAX_SLOW_FRAME_LOG_ENTRIES:
			slow_frames.pop_front()


func _record(result: Dictionary) -> void:
	_phase_results.append(result)


func _print_summary_table() -> void:
	print("")
	print("=== 0AD EXPLORATION SUMMARY ===")
	print("phase                          | arrived  | active | avg_us | warm_us | p95  | p99  | idle_us | max_us | max_stage    | slow | slow_stage   | short_us | jump_px | short | long | blocked | fail | suppress | runaway | suspected_issue")
	print("-------------------------------|----------|--------|--------|---------|------|------|---------|--------|--------------|------|--------------|----------|---------|-------|------|---------|------|----------|---------|----------------")
	for result in _phase_results:
		var phase_name: String = str(result.get("phase", ""))
		var arrived: String = str(result.get("arrived", ""))
		var active_count := int(result.get("active_count", 0))
		var avg_step_us: String = str(result.get("avg_step_usec", "0.00"))
		var warm_step_us := "%.2f" % float(result.get("warm_avg_step_usec", 0.0))
		var p95_step_us := int(result.get("p95_step_usec", 0))
		var p99_step_us := int(result.get("p99_step_usec", 0))
		var idle_step_us := "%.2f" % float(result.get("idle_avg_step_usec", 0.0))
		var max_step_us := int(result.get("max_step_usec", 0))
		var max_stage_data: Dictionary = result.get("max_step_stage_classification", {}) as Dictionary
		var max_stage: String = str(max_stage_data.get("stage", "none"))
		var slow_count := int(result.get("slow_frame_count", 0))
		var slow_stage: String = str(result.get("slow_frame_dominant_stage", "none"))
		var max_short_us := int(result.get("max_short_compute_usec", 0))
		var jump_str: String = str(result.get("max_jump_px", "0"))
		var short_requests := int(result.get("short_requests", 0))
		var long_requests := int(result.get("long_requests", 0))
		var blocked_moves := int(result.get("blocked_moves", 0))
		var move_failures := int(result.get("move_failures", 0))
		var suppressed := int(result.get("repath_suppressed", 0))
		var runaway := "yes" if _result_has_runaway_repath(result) else "no"
		var suspect := _suspected_issue(result)
		print("%-30s | %-8s | %-6d | %-6s | %-7s | %-4d | %-4d | %-7s | %-6d | %-12s | %-4d | %-12s | %-8d | %-7s | %-5d | %-4d | %-7d | %-4d | %-8d | %-7s | %s" % [
			phase_name,
			arrived,
			active_count,
			avg_step_us,
			warm_step_us,
			p95_step_us,
			p99_step_us,
			idle_step_us,
			max_step_us,
			max_stage,
			slow_count,
			slow_stage,
			max_short_us,
			jump_str,
			short_requests,
			long_requests,
			blocked_moves,
			move_failures,
			suppressed,
			runaway,
			suspect,
		])
	print("")
	print("This scene is observation-only. Use the suspected issue column to extract focused smoke tests.")


func _result_has_runaway_repath(result: Dictionary) -> bool:
	var request_total := int(result.get("short_requests", 0)) + int(result.get("long_requests", 0))
	return (
		request_total >= 40
		and int(result.get("blocked_moves", 0)) >= 80
		and int(result.get("active_count", 0)) > 0
		and int(result.get("path_result_failures", 0)) == 0
	)


func _suspected_issue(result: Dictionary) -> String:
	var phase_name: String = str(result.get("phase", ""))
	var hits: Array[String] = []
	if _result_has_runaway_repath(result):
		hits.append("0AD-MOTION: runaway repath loop (obstructed recovery / imperfect-path gating)")
	if int(result.get("stuck_count", 0)) > 0:
		hits.append("stuck units=%d" % int(result.get("stuck_count", 0)))
	if str(result.get("max_jump_px", "0")).to_float() > 16.0:
		hits.append("jump > 16 px")
	if int(result.get("max_step_usec", 0)) > 4000:
		hits.append("step > 4 ms")
	if int(result.get("pathless_active_ticks", 0)) > 120:
		hits.append("pathless active ticks=%d" % int(result.get("pathless_active_ticks", 0)))
	var notes: Dictionary = result.get("notes", {})
	if phase_name.ends_with("unreachable_goal_inside") or phase_name.ends_with("goal_blocked_at_arrival"):
		var separated: String = str(notes.get("target_path_target_separated", ""))
		if separated.begins_with("0/"):
			hits.append("target/path_target separation missing")
	if phase_name.ends_with("many_units_one_point"):
		var overlap := str(notes.get("max_pair_overlap_px", "0")).to_float()
		if overlap > 1.0:
			hits.append("formation overlap %.2f px" % overlap)
	if hits.is_empty():
		return "(no flagged anomalies)"
	return ", ".join(hits)


func _cli_args() -> PackedStringArray:
	var result := OS.get_cmdline_args()
	result.append_array(OS.get_cmdline_user_args())
	return result


func _cli_has(flag: String) -> bool:
	for arg in _cli_args():
		if arg == flag or arg.begins_with(flag + "="):
			return true
	return false


func _cli_int(flag: String, default_value: int) -> int:
	var prefix := flag + "="
	for arg in _cli_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).to_int()
	return default_value


func _fuzz_mode_main() -> void:
	var base_seed := _cli_int("--seed", FUZZ_DEFAULT_SEED)
	var iterations := _cli_int("--iterations", FUZZ_DEFAULT_ITERATIONS)
	var ticks_per_iter := _cli_int("--ticks", FUZZ_DEFAULT_TICKS)
	print("=== 0AD FUZZ MODE BEGIN === seed=%d iterations=%d ticks=%d" % [base_seed, iterations, ticks_per_iter])
	var passed := 0
	for iter in range(iterations):
		var iter_seed: int = base_seed + iter
		var rng := RandomNumberGenerator.new()
		rng.seed = iter_seed
		var result := _fuzz_run_iteration(iter, iter_seed, ticks_per_iter, rng)
		if not str(result.get("violation", "")).is_empty():
			print("FUZZ_VIOLATION: %s" % str(result))
			print("=== 0AD FUZZ MODE END === passed=%d violations=1" % passed)
			print("Reproduce: -- --fuzz --seed=%d --iterations=1 --ticks=%d" % [iter_seed, ticks_per_iter])
			get_tree().quit(1)
			return
		print("FUZZ_ITER: %s" % str(result))
		passed += 1
	print("=== 0AD FUZZ MODE END === passed=%d violations=0" % passed)
	get_tree().quit(0)


func _fuzz_run_iteration(iter: int, iter_seed: int, max_ticks: int, rng: RandomNumberGenerator) -> Dictionary:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	world.set_group_target(DEFAULT_TARGET)
	var ops_count: Dictionary = {}
	var prev_positions: Dictionary = {}
	for unit in world.get_mobile_units():
		prev_positions[unit.id] = unit.position
	var max_step_usec := 0
	var max_step_at := -1
	var max_jump_px := 0.0
	var max_jump_unit := ""
	var max_jump_at := -1
	for tick in range(max_ticks):
		var op := _fuzz_random_op(rng, world)
		var op_name := str(op.get("op", "?"))
		ops_count[op_name] = int(ops_count.get(op_name, 0)) + 1
		var step_t0 := Time.get_ticks_usec()
		world.step(DT)
		var step_usec := Time.get_ticks_usec() - step_t0
		if step_usec > max_step_usec:
			max_step_usec = step_usec
			max_step_at = tick
		var violation := _fuzz_check_invariants(world, prev_positions, tick, op)
		if not violation.is_empty():
			return {
				"iter": iter,
				"seed": iter_seed,
				"tick": tick,
				"violation": violation,
				"last_op": op,
				"world_dump": _fuzz_dump_world(world, prev_positions),
			}
		for unit in world.get_mobile_units():
			var prev_pos: Vector2 = prev_positions.get(unit.id, unit.position)
			var jump: float = unit.position.distance_to(prev_pos)
			if jump > max_jump_px:
				max_jump_px = jump
				max_jump_unit = unit.id
				max_jump_at = tick
			prev_positions[unit.id] = unit.position
	return {
		"iter": iter,
		"seed": iter_seed,
		"ticks_run": max_ticks,
		"ops": ops_count,
		"max_step_usec": max_step_usec,
		"max_step_at": max_step_at,
		"max_jump_px": "%.2f" % max_jump_px,
		"max_jump_unit": max_jump_unit,
		"max_jump_at": max_jump_at,
		"metrics": world.get_metrics(),
	}


func _fuzz_random_op(rng: RandomNumberGenerator, world: ZeroAdRtsLabWorld) -> Dictionary:
	var roll := rng.randf()
	if roll < 0.40:
		return {"op": "step"}
	if roll < 0.52:
		var target := Vector2(rng.randf_range(20.0, 700.0), rng.randf_range(20.0, 400.0))
		world.set_group_target(target)
		return {"op": "retarget", "target": str(target)}
	if roll < 0.58:
		var off_map := Vector2(rng.randf_range(800.0, 1500.0), rng.randf_range(-200.0, 600.0))
		world.set_group_target(off_map)
		return {"op": "retarget_offmap", "target": str(off_map)}
	if roll < 0.66:
		var center := Vector2(rng.randf_range(50.0, 670.0), rng.randf_range(50.0, 370.0))
		var size := Vector2(rng.randf_range(30.0, 80.0), rng.randf_range(30.0, 80.0))
		var obstacle_id := world.add_static_obstacle(center, size)
		return {"op": "add_obstacle", "id": obstacle_id, "center": str(center), "size": str(size)}
	if roll < 0.74:
		var blocker_center := Vector2(rng.randf_range(50.0, 670.0), rng.randf_range(50.0, 370.0))
		var radius := rng.randf_range(10.0, 24.0)
		var blocker_id := world.add_blocker(blocker_center, radius)
		return {"op": "add_blocker", "id": blocker_id, "center": str(blocker_center), "radius": "%.1f" % radius}
	if roll < 0.86:
		var point := Vector2(rng.randf_range(0.0, 720.0), rng.randf_range(0.0, 420.0))
		var removed := world.remove_nearest_editable(point, 80.0)
		return {"op": "remove", "point": str(point), "removed": removed}
	if roll < 0.94:
		var ids := world.get_mobile_unit_ids()
		if ids.is_empty():
			return {"op": "step"}
		var subset_size: int = rng.randi_range(1, ids.size())
		var picked: Array[String] = []
		var pool: Array[String] = ids.duplicate()
		for _i in range(subset_size):
			if pool.is_empty():
				break
			var idx: int = rng.randi_range(0, pool.size() - 1)
			picked.append(pool[idx])
			pool.remove_at(idx)
		var subset_target := Vector2(rng.randf_range(20.0, 700.0), rng.randf_range(20.0, 400.0))
		world.set_units_target(picked, subset_target)
		return {"op": "split_target", "subset": picked, "target": str(subset_target)}
	if world.obstacles.is_empty():
		return {"op": "step"}
	var obstacle := world.obstacles[rng.randi_range(0, world.obstacles.size() - 1)]
	world.set_group_target(obstacle.center)
	return {"op": "retarget_to_obstacle", "obstacle_id": obstacle.id, "target": str(obstacle.center)}


func _fuzz_check_invariants(world: ZeroAdRtsLabWorld, prev_positions: Dictionary, tick: int, last_op: Dictionary) -> String:
	var map_x_max: float = world.map_size.x + FUZZ_MAP_MARGIN
	var map_y_max: float = world.map_size.y + FUZZ_MAP_MARGIN
	var obstacle_rects: Array[Rect2] = []
	for obstacle in world.obstacles:
		obstacle_rects.append(Rect2(obstacle.center - obstacle.size * 0.5, obstacle.size))
	for unit in world.get_mobile_units():
		if is_nan(unit.position.x) or is_nan(unit.position.y):
			return "NaN_position tick=%d unit=%s pos=%s last_op=%s" % [tick, unit.id, str(unit.position), str(last_op)]
		if is_inf(unit.position.x) or is_inf(unit.position.y):
			return "inf_position tick=%d unit=%s pos=%s last_op=%s" % [tick, unit.id, str(unit.position), str(last_op)]
		if unit.position.x < -FUZZ_MAP_MARGIN or unit.position.x > map_x_max:
			return "out_of_map_x tick=%d unit=%s x=%.2f last_op=%s" % [tick, unit.id, unit.position.x, str(last_op)]
		if unit.position.y < -FUZZ_MAP_MARGIN or unit.position.y > map_y_max:
			return "out_of_map_y tick=%d unit=%s y=%.2f last_op=%s" % [tick, unit.id, unit.position.y, str(last_op)]
		if is_nan(unit.target.x) or is_nan(unit.target.y):
			return "NaN_target tick=%d unit=%s target=%s last_op=%s" % [tick, unit.id, str(unit.target), str(last_op)]
		if is_nan(unit.path_target.x) or is_nan(unit.path_target.y):
			return "NaN_path_target tick=%d unit=%s path_target=%s last_op=%s" % [tick, unit.id, str(unit.path_target), str(last_op)]
		var prev_pos: Vector2 = prev_positions.get(unit.id, unit.position)
		var jump: float = unit.position.distance_to(prev_pos)
		if jump > FUZZ_MAX_JUMP_PX:
			var inside_obstacle := false
			for rect in obstacle_rects:
				if rect.grow(unit.radius).has_point(prev_pos):
					inside_obstacle = true
					break
			if not inside_obstacle:
				return "jump tick=%d unit=%s jump=%.2f prev=%s curr=%s last_op=%s" % [
					tick,
					unit.id,
					jump,
					str(prev_pos),
					str(unit.position),
					str(last_op),
				]
	return ""


func _fuzz_dump_world(world: ZeroAdRtsLabWorld, prev_positions: Dictionary) -> Dictionary:
	var obstacles: Array[Dictionary] = []
	for obstacle in world.obstacles:
		obstacles.append({
			"id": obstacle.id,
			"center": str(obstacle.center),
			"size": str(obstacle.size),
		})
	var units: Array[Dictionary] = []
	for unit in world.units:
		units.append({
			"id": unit.id,
			"pos": str(unit.position),
			"radius": "%.2f" % unit.radius,
			"mobile": unit.mobile,
			"target": str(unit.target),
			"path_target": str(unit.path_target),
			"arrived": unit.arrived,
			"has_move_order": unit.has_move_order,
			"long_path_size": unit.long_path.size() if unit.long_path != null else 0,
			"short_path_size": unit.short_path.size() if unit.short_path != null else 0,
			"prev_pos": str(prev_positions.get(unit.id, unit.position)),
		})
	return {
		"obstacles": obstacles,
		"obstacle_count": obstacles.size(),
		"units": units,
		"metrics": world.get_metrics(),
	}
