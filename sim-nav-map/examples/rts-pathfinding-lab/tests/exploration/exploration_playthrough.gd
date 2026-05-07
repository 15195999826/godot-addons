extends Node

# Exploration playthrough — drives the rts-pathfinding-lab through a sequence
# of realistic user operations and records what happens. Pure observation
# script: no PASS/FAIL gate, always exits 0. Read the EXPLORE_OBSERVATION
# lines and the end-of-run summary table to learn which scenarios trigger
# which symptoms — and which open issues each scenario likely exercises.
#
# Phases simulate what a developer / player would do at the console:
#   1. baseline_open_movement      — units cross a default scene unimpeded
#   2. drop_static_in_path         — drop a wall directly in front of moving units
#   3. wide_wall_detour            — long obstacle forces a multi-waypoint detour
#   4. unreachable_goal_inside     — command into the middle of an obstacle
#   5. fully_blocked_path          — wall units off completely from the goal
#   6. many_units_one_point        — issue a single command for the whole group
#   7. drop_obstacle_on_unit       — drop a static obstacle on top of blue_0
#   8. command_outside_map         — issue a command target way outside the lab map
#   9. rapid_obstacle_thrash       — add/remove blockers every few ticks during travel
#  10. partial_wall_with_gap       — vertical wall with a 50 px gap, units must find it
#  11. dynamic_blocker_swarm       — six circular blockers seeded across the corridor
#  12. formation_packing           — open-area arrival, isolates formation slot logic
#
# Each phase prints one EXPLORE_OBSERVATION dict with: arrived units, total
# replans, max single-step wall time, max single-step world-space delta and
# its owning unit, plus stuck-unit count, path-failure-tick count, and
# phase-specific notes. The final block prints a summary table mapping
# observed symptoms to suspected issue IDs.
#
# Run: godot --headless --path . addons/sim-nav-map/examples/rts-pathfinding-lab/tests/exploration/exploration_playthrough.tscn
#
# Notes:
#   - This script is NOT a smoke. It does not assert thresholds and does not
#     belong in test_groups.json. Use the per-issue repro smokes
#     (tests/repro_core_*, examples/.../repro_lab_*) for hard FAIL/PASS gates.
#   - Lab obstacles are AABB only; rotated-OBB scenarios (CORE-001) cannot
#     be exercised through the lab adapter and must use a core-only repro.


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")

const DT := 1.0 / 60.0


var _phase_results: Array[Dictionary] = []


func _ready() -> void:
	print("=== EXPLORATION PLAYTHROUGH BEGIN ===")
	_phase_baseline_open_movement()
	_phase_drop_static_in_path()
	_phase_wide_wall_detour()
	_phase_unreachable_goal_inside()
	_phase_fully_blocked_path()
	_phase_many_units_one_point()
	_phase_drop_obstacle_on_unit()
	_phase_command_outside_map()
	_phase_rapid_obstacle_thrash()
	_phase_partial_wall_with_gap()
	_phase_dynamic_blocker_swarm()
	_phase_formation_packing()
	_print_summary_table()
	print("=== EXPLORATION PLAYTHROUGH END ===")
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Phase implementations
# ---------------------------------------------------------------------------

func _phase_baseline_open_movement() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Default target is set by setup_default; just step until arrival or 240 ticks.
	var observer := PhaseObserver.new(world, "1_baseline_open_movement")
	observer.run_steps(240, true)
	observer.note("expected", "no anomalies — units traverse default scene cleanly")
	_record(observer.finish())


func _phase_drop_static_in_path() -> void:
	var world := LabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "2_drop_static_in_path")
	# Let units start moving toward the default target (610, 210).
	observer.run_steps(20, false)
	# Now drop a static wall in the corridor directly in front of them.
	var drop_pos := Vector2(220.0, 210.0)
	world.add_static_obstacle(drop_pos, Vector2(60.0, 80.0))
	observer.note("event", "static obstacle dropped at %s after 20 ticks" % str(drop_pos))
	observer.run_steps(220, true)
	_record(observer.finish())


func _phase_wide_wall_detour() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Add a long wall mid-map. Default target stays at (610, 210).
	world.add_static_obstacle(Vector2(420.0, 210.0), Vector2(40.0, 280.0))
	world.set_group_target(Vector2(610.0, 210.0))
	var observer := PhaseObserver.new(world, "3_wide_wall_detour")
	observer.run_steps(360, true)
	observer.note("event", "long vertical wall (40x280) at (420, 210)")
	_record(observer.finish())


func _phase_unreachable_goal_inside() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# stone_block sits at (340, 210) with size (110, 110). Aim for its center.
	var unreachable := Vector2(340.0, 210.0)
	world.set_group_target(unreachable)
	var observer := PhaseObserver.new(world, "4_unreachable_goal_inside")
	observer.run_steps(180, true)
	# Capture target / path_target separation for each unit.
	var separated := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(unit.path_target) > 0.5:
			separated += 1
	observer.note("event", "command target = stone_block center")
	observer.note("target_path_target_separated", "%d/%d units" % [separated, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_fully_blocked_path() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Wall the units off from the right side completely. Defaults span y=160-260
	# and target is at x=610. Stack obstacles from y=80 to y=340 at x=400.
	for y in [110.0, 165.0, 215.0, 270.0, 325.0]:
		world.add_static_obstacle(Vector2(400.0, y), Vector2(40.0, 60.0))
	world.set_group_target(Vector2(610.0, 210.0))
	var observer := PhaseObserver.new(world, "5_fully_blocked_path")
	observer.run_steps(300, true)
	observer.note("event", "vertical wall stack at x=400 (5 segments y=110..325)")
	_record(observer.finish())


func _phase_many_units_one_point() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# All 6 mobile blue commanded to a single tight target. set_units_target
	# applies formation offsets so they don't literally stack, but the cluster
	# still packs tightly.
	world.set_group_target(Vector2(580.0, 210.0))
	var observer := PhaseObserver.new(world, "6_many_units_one_point")
	observer.run_steps(360, true)
	# Compute pairwise overlap matrix.
	var mobile := world.get_mobile_units()
	var max_overlap := 0.0
	for i in range(mobile.size()):
		for j in range(i + 1, mobile.size()):
			var ui := mobile[i]
			var uj := mobile[j]
			var dist: float = ui.position.distance_to(uj.position)
			var sum_radii: float = ui.radius + uj.radius
			var ov: float = maxf(0.0, sum_radii - dist)
			if ov > max_overlap:
				max_overlap = ov
	observer.note("max_pair_overlap_px", "%.2f" % max_overlap)
	_record(observer.finish())


func _phase_drop_obstacle_on_unit() -> void:
	var world := LabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "7_drop_obstacle_on_unit")
	observer.run_steps(20, false)
	var blue_0 := world.get_unit_by_id("blue_0")
	if blue_0 != null:
		world.add_static_obstacle(blue_0.position, Vector2(60.0, 60.0))
		observer.note("event", "60×60 static obstacle dropped on blue_0 at %s" % str(blue_0.position))
	else:
		observer.note("event", "blue_0 missing — skipping drop")
	observer.run_steps(120, true)
	_record(observer.finish())


func _phase_command_outside_map() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Lab map is roughly 640×360. (1500, 500) is well outside.
	var off_map := Vector2(1500.0, 500.0)
	world.set_group_target(off_map)
	var observer := PhaseObserver.new(world, "8_command_outside_map")
	observer.run_steps(120, true)
	# Capture each unit's target after canonicalization.
	var clamped_count := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(off_map) > 50.0:
			clamped_count += 1
	observer.note("event", "command target = (1500, 500) (off-map)")
	observer.note("targets_clamped_or_canonicalized", "%d/%d units" % [clamped_count, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_rapid_obstacle_thrash() -> void:
	var world := LabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "9_rapid_obstacle_thrash")
	# Warm up.
	observer.run_steps(5, false)
	# Step 360 ticks while injecting rapid obstacle edits.
	var blocker_x := 180.0
	var add_count := 0
	var remove_count := 0
	for i in range(360):
		if i % 6 == 0:
			var y_band: float = 195.0 if (i / 6) % 2 == 0 else 225.0
			world.add_blocker(Vector2(blocker_x, y_band), 14.0)
			add_count += 1
			blocker_x += 18.0
			if blocker_x > 580.0:
				blocker_x = 180.0
		if i % 9 == 0 and i > 0:
			world.remove_nearest_editable(Vector2(blocker_x - 24.0, 210.0))
			remove_count += 1
		if i % 30 == 0 and i > 0:
			world.set_group_target(Vector2(610.0, 210.0))
		observer.before_step()
		world.step(DT)
		observer.after_step()
	observer.note("blockers_added", str(add_count))
	observer.note("blockers_removed", str(remove_count))
	_record(observer.finish())


func _phase_partial_wall_with_gap() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Vertical wall at x=400 with a 50 px gap centered at y=210. Units must
	# discover the gap rather than detour around the whole map.
	# Top segment covers y in [80, 185]; bottom segment covers y in [235, 340].
	world.add_static_obstacle(Vector2(400.0, 132.0), Vector2(40.0, 105.0))
	world.add_static_obstacle(Vector2(400.0, 287.0), Vector2(40.0, 105.0))
	world.set_group_target(Vector2(560.0, 210.0))
	var observer := PhaseObserver.new(world, "10_partial_wall_with_gap")
	observer.run_steps(420, true)
	observer.note("event", "wall at x=400 with 50 px gap centered y=210")
	_record(observer.finish())


func _phase_dynamic_blocker_swarm() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Six dynamic blockers (circular obstacles, treated as moving units in the
	# vertex pathfinder) sprinkled between the unit starts and the target.
	# Forces frequent short-path replans to weave through.
	var blocker_positions: Array = [
		Vector2(280.0, 180.0),
		Vector2(280.0, 240.0),
		Vector2(380.0, 165.0),
		Vector2(380.0, 255.0),
		Vector2(480.0, 195.0),
		Vector2(480.0, 225.0),
	]
	for pos in blocker_positions:
		world.add_blocker(pos, 14.0)
	world.set_group_target(Vector2(610.0, 210.0))
	var observer := PhaseObserver.new(world, "11_dynamic_blocker_swarm")
	observer.run_steps(420, true)
	observer.note("event", "%d circular blockers seeded in the corridor" % blocker_positions.size())
	_record(observer.finish())


func _phase_formation_packing() -> void:
	var world := LabWorld.new()
	world.setup_default()
	# Open upper-right area with no obstacles between starts and target. This
	# isolates formation slot assignment from obstacle avoidance.
	var target := Vector2(560.0, 75.0)
	world.set_group_target(target)
	var observer := PhaseObserver.new(world, "12_formation_packing")
	observer.run_steps(360, true)
	var mobile: Array = world.get_mobile_units()
	var min_pair := INF
	var max_pair := 0.0
	for i in range(mobile.size()):
		for j in range(i + 1, mobile.size()):
			var d: float = mobile[i].position.distance_to(mobile[j].position)
			if d < min_pair:
				min_pair = d
			if d > max_pair:
				max_pair = d
	observer.note("formation_min_pair_dist_px", "%.2f" % min_pair)
	observer.note("formation_max_pair_dist_px", "%.2f" % max_pair)
	_record(observer.finish())


# ---------------------------------------------------------------------------
# Observer + summary
# ---------------------------------------------------------------------------

class PhaseObserver:
	const STUCK_TICK_THRESHOLD := 30
	const STUCK_MOVEMENT_THRESHOLD_PX := 1.0

	var world
	var phase_name: String
	var prev_positions: Dictionary = {}
	var max_step_usec: int = 0
	var max_step_at: int = -1
	var max_jump_px: float = 0.0
	var max_jump_unit: String = ""
	var max_jump_at: int = -1
	var step_count: int = 0
	var arrived_at_step: int = -1
	var notes: Dictionary = {}
	var _step_t0: int = 0

	# Movement tracking — last step on which each unit moved more than
	# STUCK_MOVEMENT_THRESHOLD_PX. A unit whose last_movement_step trails
	# step_count by ≥ STUCK_TICK_THRESHOLD AND still has a move order is
	# reported as stuck at finish().
	var last_movement_step: Dictionary = {}

	# Cumulative count of (unit, tick) pairs where the unit had an empty
	# planned path while still wanting to move and not yet arrived.
	# High values indicate persistent path-failure pressure during the phase.
	var path_failure_tick_count: int = 0

	func _init(p_world, p_phase_name: String) -> void:
		world = p_world
		phase_name = p_phase_name
		for u in world.get_mobile_units():
			prev_positions[u.id] = u.position
			last_movement_step[u.id] = 0

	func before_step() -> void:
		_step_t0 = Time.get_ticks_usec()

	func after_step() -> void:
		var step_usec := Time.get_ticks_usec() - _step_t0
		if step_usec > max_step_usec:
			max_step_usec = step_usec
			max_step_at = step_count
		for u in world.get_mobile_units():
			var prev: Vector2 = prev_positions.get(u.id, u.position)
			var jump: float = u.position.distance_to(prev)
			if jump > max_jump_px:
				max_jump_px = jump
				max_jump_unit = u.id
				max_jump_at = step_count
			if jump > STUCK_MOVEMENT_THRESHOLD_PX:
				last_movement_step[u.id] = step_count
			prev_positions[u.id] = u.position
			if u.has_move_order and not u.arrived and u.path.is_empty():
				path_failure_tick_count += 1
		step_count += 1
		if arrived_at_step < 0 and world.all_mobile_arrived():
			arrived_at_step = step_count

	func run_steps(count: int, stop_on_arrival: bool) -> void:
		for _i in range(count):
			before_step()
			world.step(DT)
			after_step()
			if stop_on_arrival and world.all_mobile_arrived():
				break

	func note(key: String, value: String) -> void:
		notes[key] = value

	func finish() -> Dictionary:
		var mobile: Array = world.get_mobile_units()
		var arrived := 0
		var stuck_ids: Array[String] = []
		for u in mobile:
			if u.arrived:
				arrived += 1
				continue
			if not u.has_move_order:
				continue
			var last_moved: int = last_movement_step.get(u.id, 0)
			if step_count - last_moved >= STUCK_TICK_THRESHOLD:
				stuck_ids.append(u.id)
		var result := {
			"phase": phase_name,
			"steps_run": step_count,
			"arrived": "%d/%d" % [arrived, mobile.size()],
			"arrived_at_step": arrived_at_step,
			"max_step_usec": max_step_usec,
			"max_step_at": max_step_at,
			"max_jump_px": "%.2f" % max_jump_px,
			"max_jump_unit": max_jump_unit,
			"max_jump_at": max_jump_at,
			"total_replans": world.total_replans,
			"stuck_count": stuck_ids.size(),
			"stuck_ids": stuck_ids,
			"path_failure_ticks": path_failure_tick_count,
			"notes": notes,
		}
		print("EXPLORE_OBSERVATION: %s" % str(result))
		return result


func _record(result: Dictionary) -> void:
	_phase_results.append(result)


func _print_summary_table() -> void:
	print("")
	print("=== EXPLORATION SUMMARY ===")
	print("phase                          | arrived  | max_step_µs | max_jump_px | replans | stuck | pf_ticks | suspected_issue")
	print("-------------------------------|----------|-------------|-------------|---------|-------|----------|------------------")
	for r in _phase_results:
		var phase: String = str(r.get("phase", ""))
		var arrived: String = str(r.get("arrived", ""))
		var step_us: int = int(r.get("max_step_usec", 0))
		var jump_str: String = str(r.get("max_jump_px", ""))
		var replans: int = int(r.get("total_replans", 0))
		var stuck: int = int(r.get("stuck_count", 0))
		var pf_ticks: int = int(r.get("path_failure_ticks", 0))
		var suspect := _suspected_issue(r)
		print("%-30s | %-8s | %-11d | %-11s | %-7d | %-5d | %-8d | %s" % [phase, arrived, step_us, jump_str, replans, stuck, pf_ticks, suspect])
	print("")
	print("Suspect-issue mapping is heuristic — see docs/issues/ for the canonical")
	print("repro smokes per issue. pf_ticks counts (unit, tick) pairs where the")
	print("unit had an empty planned path while still under move orders.")


func _suspected_issue(r: Dictionary) -> String:
	var phase: String = str(r.get("phase", ""))
	var jump: float = (str(r.get("max_jump_px", "0")).to_float())
	var step_us: int = int(r.get("max_step_usec", 0))
	var stuck: int = int(r.get("stuck_count", 0))
	var pf_ticks: int = int(r.get("path_failure_ticks", 0))
	var notes: Dictionary = r.get("notes", {})
	var hits: Array[String] = []
	if jump > 16.0:
		hits.append("LAB-003 (jump > 16 px)")
	if step_us > 4000:
		hits.append("LAB-002 (step > 4 ms)")
	if stuck > 0:
		hits.append("stuck units=%d (needs core-only proof before blaming CORE-003 / escape logic)" % stuck)
	if pf_ticks > 200:
		hits.append("path_failure_ticks=%d (high replan failure pressure — investigate before blaming core)" % pf_ticks)
	if phase.ends_with("unreachable_goal_inside"):
		var sep: String = str(notes.get("target_path_target_separated", ""))
		if sep.begins_with("0/"):
			hits.append("LAB-005 (target/path_target merged)")
	if phase.ends_with("fully_blocked_path"):
		var arrived: String = str(r.get("arrived", "0/0"))
		if arrived.begins_with("0/"):
			hits.append("blocked-path observation (needs core-only proof before CORE-003)")
	if phase.ends_with("many_units_one_point"):
		var ov: String = str(notes.get("max_pair_overlap_px", "0"))
		if ov.to_float() > 1.0:
			hits.append("LAB-004 (overlap > 1 px)")
	if phase.ends_with("command_outside_map"):
		var clamped: String = str(notes.get("targets_clamped_or_canonicalized", ""))
		if clamped.begins_with("0/"):
			hits.append("out-of-bounds observation (needs core-only proof before CORE-004)")
	if phase.ends_with("formation_packing"):
		var min_pair_str: String = str(notes.get("formation_min_pair_dist_px", "0"))
		var min_pair_dist: float = min_pair_str.to_float()
		if min_pair_dist > 0.0 and min_pair_dist < 1.0:
			hits.append("formation slots collapsed: min pair < 1 px (needs LAB-004 follow-up)")
	if hits.is_empty():
		return "(no flagged anomalies)"
	return ", ".join(hits)
