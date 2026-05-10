extends Node

# 0AD stress playthrough.
#
# Stress harness for the 0ad-rts-pathfinding-lab. The "torture" set: scenarios
# where the system is intentionally beaten on but no business outcome
# assertion is appropriate. Promoted phases (deterministic scenarios with
# binary contracts) live in
#   tests/smoke/smoke_zero_ad_rts_lab_edge_cases.tscn
# instead — that is the only place new behaviour assertions belong.
#
# This scene enforces *only* hard safety invariants — NaN / inf / out-of-map /
# illegal teleport — shared with the fuzz mode at the bottom of the file.
# Violations of these invariants exit non-zero so a regression here is loud.
# Soft observations (path-request counts, slow frames, etc.) print into
# STRESS_OBSERVATION lines and a summary table for human inspection only.
#
# Run:
# godot --headless --path . addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/stress/stress_playthrough.tscn
#
# Optional fuzz (random ops on the default 6 units + obstacle add/remove):
# godot --headless --path . addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/stress/stress_playthrough.tscn -- --fuzz --seed=42 --iterations=10 --ticks=240
#
# Optional swarm (N independent units, each gets a fresh random target every --retarget-every ticks):
# godot --headless --path . addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/stress/stress_playthrough.tscn -- --swarm --units=50 --ticks=600 --retarget-every=120 --seed=42
#
# NOT registered in test_groups.json — observation-only by design.


const DT := 1.0 / 60.0
const DEFAULT_TARGET := Vector2(610.0, 210.0)
const FUZZ_DEFAULT_SEED := 42
const FUZZ_DEFAULT_ITERATIONS := 10
const FUZZ_DEFAULT_TICKS := 240
const FUZZ_MAX_JUMP_PX := 80.0
const FUZZ_MAP_MARGIN := 1.0
const SWARM_DEFAULT_SEED := 42
const SWARM_DEFAULT_UNITS := 50
const SWARM_DEFAULT_TICKS := 600
const SWARM_DEFAULT_RETARGET_EVERY := 120
const SWARM_GRACE_TICKS := 10
const SWARM_UNIT_RADIUS := 11.0
const SWARM_UNIT_SPEED := 96.0
const SWARM_SPAWN_MAX_ATTEMPTS_PER_UNIT := 80
const SWARM_RETARGET_MAX_ATTEMPTS := 20


var _phase_results: Array[Dictionary] = []
var _violations: Array[String] = []


func _ready() -> void:
	if _cli_has("--fuzz"):
		_fuzz_mode_main()
		return
	if _cli_has("--swarm"):
		_swarm_mode_main()
		return
	print("=== 0AD STRESS PLAYTHROUGH BEGIN ===")
	_phase_rapid_obstacle_thrash()
	_phase_dynamic_blocker_swarm()
	_phase_gap_close_mid_travel()
	_phase_alternating_corridor_seal()
	_print_summary_table()
	print("=== 0AD STRESS PLAYTHROUGH END ===")
	if _violations.is_empty():
		get_tree().quit(0)
	else:
		for v in _violations:
			print("STRESS_VIOLATION: %s" % v)
			printerr("STRESS_VIOLATION: %s" % v)
		get_tree().quit(1)


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
	_record_phase(observer)


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
	_record_phase(observer)


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
	_record_phase(observer)


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
	_record_phase(observer)


class PhaseObserver:
	const STUCK_TICK_THRESHOLD := 30
	const STUCK_MOVEMENT_THRESHOLD_PX := 1.0
	const RUNAWAY_REPATH_THRESHOLD := 40
	const RUNAWAY_BLOCKED_THRESHOLD := 80
	const MAX_SLOW_FRAME_LOG_ENTRIES := 24
	const FUZZ_MAX_JUMP_PX := 80.0
	const FUZZ_MAP_MARGIN := 1.0
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
	var violation: String = ""
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
		# Snapshot prev_positions BEFORE the per-unit update loop so the
		# invariant jump check sees the real previous frame.
		var prev_snapshot := prev_positions.duplicate()
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
		# Hard invariant check (mirror of _fuzz_check_invariants — keep in sync).
		if violation.is_empty():
			violation = _check_world_invariants(prev_snapshot, step_count)
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

	# Mirror of _fuzz_check_invariants at the bottom of this file.
	# Same NaN / inf / out-of-map / jump rules; keep both in sync.
	func _check_world_invariants(prev_snapshot: Dictionary, tick: int) -> String:
		var map_x_max: float = world.map_size.x + FUZZ_MAP_MARGIN
		var map_y_max: float = world.map_size.y + FUZZ_MAP_MARGIN
		var obstacle_rects: Array[Rect2] = []
		for obstacle in world.obstacles:
			obstacle_rects.append(Rect2(obstacle.center - obstacle.size * 0.5, obstacle.size))
		for unit in world.get_mobile_units():
			if is_nan(unit.position.x) or is_nan(unit.position.y):
				return "NaN_position phase=%s tick=%d unit=%s pos=%s" % [phase_name, tick, unit.id, str(unit.position)]
			if is_inf(unit.position.x) or is_inf(unit.position.y):
				return "inf_position phase=%s tick=%d unit=%s pos=%s" % [phase_name, tick, unit.id, str(unit.position)]
			if unit.position.x < -FUZZ_MAP_MARGIN or unit.position.x > map_x_max:
				return "out_of_map_x phase=%s tick=%d unit=%s x=%.2f" % [phase_name, tick, unit.id, unit.position.x]
			if unit.position.y < -FUZZ_MAP_MARGIN or unit.position.y > map_y_max:
				return "out_of_map_y phase=%s tick=%d unit=%s y=%.2f" % [phase_name, tick, unit.id, unit.position.y]
			if is_nan(unit.target.x) or is_nan(unit.target.y):
				return "NaN_target phase=%s tick=%d unit=%s target=%s" % [phase_name, tick, unit.id, str(unit.target)]
			if is_nan(unit.path_target.x) or is_nan(unit.path_target.y):
				return "NaN_path_target phase=%s tick=%d unit=%s path_target=%s" % [phase_name, tick, unit.id, str(unit.path_target)]
			var prev_pos: Vector2 = prev_snapshot.get(unit.id, unit.position)
			var jump: float = unit.position.distance_to(prev_pos)
			if jump > FUZZ_MAX_JUMP_PX:
				var inside_obstacle := false
				for rect in obstacle_rects:
					if rect.grow(unit.radius).has_point(prev_pos):
						inside_obstacle = true
						break
				if not inside_obstacle:
					return "jump phase=%s tick=%d unit=%s jump=%.2f prev=%s curr=%s" % [
						phase_name,
						tick,
						unit.id,
						jump,
						str(prev_pos),
						str(unit.position),
					]
		return ""

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
			"violation": violation,
			"notes": notes,
		}
		print("STRESS_OBSERVATION: %s" % str(result))
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


func _record_phase(observer: PhaseObserver) -> void:
	var result := observer.finish()
	_phase_results.append(result)
	if not str(result.get("violation", "")).is_empty():
		_violations.append(str(result.get("violation", "")))


func _print_summary_table() -> void:
	print("")
	print("=== 0AD STRESS SUMMARY ===")
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
	print("Stress observation only. The only fail path is a hard invariant violation (printed as STRESS_VIOLATION).")


func _result_has_runaway_repath(result: Dictionary) -> bool:
	var request_total := int(result.get("short_requests", 0)) + int(result.get("long_requests", 0))
	return (
		request_total >= 40
		and int(result.get("blocked_moves", 0)) >= 80
		and int(result.get("active_count", 0)) > 0
		and int(result.get("path_result_failures", 0)) == 0
	)


func _suspected_issue(result: Dictionary) -> String:
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


# Mirror of PhaseObserver._check_world_invariants — keep both in sync.
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


# Swarm mode: N independent mobile units, each periodically retargeted to a
# fresh random point. Designed to expose unit-vs-unit interaction at scale —
# push collapses, formation deadlocks, mutual blocking — that fuzz mode (only
# 6 units, often retargeted as a group) cannot reach.
#
# Hard fail conditions:
#   - PhaseObserver invariants (NaN / inf / out-of-map / illegal teleport)
#   - Any mobile unit sitting inside an obstacle's clearance ring after
#     the SWARM_GRACE_TICKS warm-up. With pre-cleared spawn positions and a
#     working push system this should never happen; if it does, push is
#     pushing units into static geometry.
# Soft observations (printed in STRESS_OBSERVATION, never fail):
#   - max_pair_overlap_px (push system effectiveness under crowding)
#   - retargets / pathless_active_ticks / runaway_repath_ticks / stuck_count
#     (already tracked by PhaseObserver)
func _swarm_mode_main() -> void:
	var seed_val := _cli_int("--seed", SWARM_DEFAULT_SEED)
	var unit_count := _cli_int("--units", SWARM_DEFAULT_UNITS)
	var max_ticks := _cli_int("--ticks", SWARM_DEFAULT_TICKS)
	var retarget_every := _cli_int("--retarget-every", SWARM_DEFAULT_RETARGET_EVERY)
	print("=== 0AD SWARM MODE BEGIN === seed=%d units=%d ticks=%d retarget_every=%d" % [seed_val, unit_count, max_ticks, retarget_every])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var world := _swarm_setup_world(unit_count, rng)
	var actually_spawned := world.get_mobile_unit_ids().size()
	if actually_spawned < unit_count:
		print("SWARM_WARN: spawned %d / %d units (rejected by obstacles or other units)" % [actually_spawned, unit_count])
	var observer := PhaseObserver.new(world, "swarm_%d_units_seed_%d" % [actually_spawned, seed_val])
	var retarget_count := 0
	var static_violation_tick := -1
	var static_violation_units: Array[String] = []
	for tick in range(max_ticks):
		if tick % retarget_every == 0:
			_swarm_random_retarget(world, rng)
			retarget_count += 1
		observer.step_once()
		if not observer.violation.is_empty():
			break
		if tick > SWARM_GRACE_TICKS:
			static_violation_units = _swarm_collect_static_violators(world)
			if not static_violation_units.is_empty():
				static_violation_tick = tick
				break
	observer.note("retargets", str(retarget_count))
	observer.note("max_pair_overlap_px", "%.2f" % _swarm_max_overlap(world))
	if static_violation_tick >= 0:
		observer.note("static_violation_tick", str(static_violation_tick))
		observer.note("static_violation_units", str(static_violation_units))
	var result := observer.finish()
	var fatal := false
	if not str(result.get("violation", "")).is_empty():
		var msg := "SWARM_VIOLATION: %s" % str(result.get("violation", ""))
		print(msg)
		printerr(msg)
		fatal = true
	if static_violation_tick >= 0:
		var msg := "SWARM_VIOLATION: static_clearance tick=%d units=%s" % [static_violation_tick, str(static_violation_units)]
		print(msg)
		printerr(msg)
		fatal = true
	if fatal:
		print("=== 0AD SWARM MODE END === violations=1")
		get_tree().quit(1)
		return
	print("=== 0AD SWARM MODE END === violations=0")
	get_tree().quit(0)


func _swarm_setup_world(unit_count: int, rng: RandomNumberGenerator) -> ZeroAdRtsLabWorld:
	var world := ZeroAdRtsLabWorld.new()
	world.setup_default()
	# Drop the 6 default mobile units; keep the obstacles + red_blocker so the
	# swarm has something to dodge.
	var keep_units: Array[ZeroAdRtsLabUnit] = []
	for unit in world.units:
		if not unit.mobile:
			keep_units.append(unit)
	world.units = keep_units
	var spawned := 0
	var attempts := 0
	var max_attempts := unit_count * SWARM_SPAWN_MAX_ATTEMPTS_PER_UNIT
	while spawned < unit_count and attempts < max_attempts:
		attempts += 1
		var pos := _swarm_random_map_point(world, rng, SWARM_UNIT_RADIUS)
		if not _swarm_position_clear(world, pos, SWARM_UNIT_RADIUS):
			continue
		var unit := ZeroAdRtsLabUnit.new("swarm_%d" % spawned, "blue", pos, SWARM_UNIT_RADIUS, SWARM_UNIT_SPEED, true)
		world.units.append(unit)
		spawned += 1
	world.pathfinder.refresh_dynamic_units(world.units)
	world.clear_traces()
	return world


func _swarm_random_retarget(world: ZeroAdRtsLabWorld, rng: RandomNumberGenerator) -> void:
	for unit in world.get_mobile_units():
		var target := unit.position
		for _attempt in range(SWARM_RETARGET_MAX_ATTEMPTS):
			var candidate := _swarm_random_map_point(world, rng, SWARM_UNIT_RADIUS)
			if _swarm_target_clear_of_obstacles(world, candidate, SWARM_UNIT_RADIUS):
				target = candidate
				break
		world.issue_move(unit.id, target)


func _swarm_random_map_point(world: ZeroAdRtsLabWorld, rng: RandomNumberGenerator, radius: float) -> Vector2:
	return Vector2(
		rng.randf_range(radius + 5.0, world.map_size.x - radius - 5.0),
		rng.randf_range(radius + 5.0, world.map_size.y - radius - 5.0)
	)


func _swarm_position_clear(world: ZeroAdRtsLabWorld, pos: Vector2, radius: float) -> bool:
	if not _swarm_target_clear_of_obstacles(world, pos, radius):
		return false
	for unit in world.units:
		if pos.distance_to(unit.position) < (radius + unit.radius + 4.0):
			return false
	return true


func _swarm_target_clear_of_obstacles(world: ZeroAdRtsLabWorld, pos: Vector2, radius: float) -> bool:
	for obstacle in world.obstacles:
		if obstacle.contains_point_with_clearance(pos, radius):
			return false
	return true


func _swarm_collect_static_violators(world: ZeroAdRtsLabWorld) -> Array[String]:
	var bad: Array[String] = []
	for unit in world.get_mobile_units():
		for obstacle in world.obstacles:
			if obstacle.contains_point_with_clearance(unit.position, unit.radius):
				bad.append("%s@(%.1f,%.1f) in %s" % [unit.id, unit.position.x, unit.position.y, obstacle.id])
				break
	return bad


func _swarm_max_overlap(world: ZeroAdRtsLabWorld) -> float:
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
