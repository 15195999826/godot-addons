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
#  13. progressive_seal_all_paths  — close every passable corridor in sequence while
#                                    units travel until the cluster is fully isolated
#  14. seal_behind_unit            — drop a forward wall, then seal the rear so the
#                                    cluster is boxed in (escape / trapped-replan test)
#  15. gap_close_mid_travel        — long wall with 50 px gap, then close the gap
#                                    after units have committed to it
#  16. goal_blocked_at_arrival     — drop a 60×60 wall on the default target after
#                                    units are en route — mid-flight canonicalization
#  17. alternating_corridor_seal   — alternate which y-detour is sealed every 30 ticks
#                                    to maximize replan pressure
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
#     (tests/repro/repro_core_*, examples/.../repro_lab_*) for hard FAIL/PASS gates.
#   - Lab obstacles are AABB only; rotated-OBB scenarios (CORE-001) cannot
#     be exercised through the lab adapter and must use a core-only repro.


const LabWorld := preload("res://addons/sim-nav-map/examples/rts-pathfinding-lab/logic/rts_pathfinding_lab_world.gd")

const DT := 1.0 / 60.0

# Fuzz-mode defaults. Override via CLI args after `--`:
#   godot --headless --path . exploration_playthrough.tscn -- --fuzz --seed=42 --iterations=10 --ticks=200
const FUZZ_DEFAULT_SEED := 42
const FUZZ_DEFAULT_ITERATIONS := 10
const FUZZ_DEFAULT_TICKS := 200
# Single-step jump above this is treated as a teleport — prior observed jumps
# include 41 (phase 7 obstacle on unit) and 62 (phase 14 dual-wall push). 80 px
# is loose enough to ignore those known cases but tight enough that anything
# further would be a real bug.
const FUZZ_MAX_JUMP_PX := 80.0
const FUZZ_MAP_MARGIN := 1.0


var _phase_results: Array[Dictionary] = []


func _ready() -> void:
	if _cli_has("--fuzz"):
		_fuzz_mode_main()
		return
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
	_phase_progressive_seal_all_paths()
	_phase_seal_behind_unit()
	_phase_gap_close_mid_travel()
	_phase_goal_blocked_at_arrival()
	_phase_alternating_corridor_seal()
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


func _phase_progressive_seal_all_paths() -> void:
	# Close every passable corridor in turn while units are travelling, until
	# no route to (610, 210) remains. Default scene leaves four ways through
	# the central wall column: (A) the top edge above north_wall, (B) the
	# upper detour between north_wall and stone_block, (C) the lower detour
	# between stone_block and south_wall, and (D) the bottom edge below
	# south_wall. We seal A → D → B → C in 30-tick increments so the units
	# pick a route, lose it, repick, and finally sit fully isolated.
	# NOTE: phase observer's `arrived` count means "settled" (reached goal
	# OR gave up via _settle_idle_unit), not "reached goal". The real
	# success metric is `units_far_from_goal` — units sitting > 50 px from
	# the goal at the end. Fast units may slip past corridor seals before
	# closure completes — that's expected. The bug-magnet signal is
	# units_far_from_goal == 0/N: every unit escaped before any seal landed.
	var world := LabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "13_progressive_seal_all_paths")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 5.0), Vector2(300.0, 30.0))
	observer.note("event_30", "top edge sealed (A) — 300×30 at y=5")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 415.0), Vector2(300.0, 30.0))
	observer.note("event_60", "bottom edge sealed (D) — 300×30 at y=415")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 130.0), Vector2(40.0, 30.0))
	observer.note("event_90", "upper detour sealed (B) — 40×30 at y=130")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(340.0, 290.0), Vector2(40.0, 30.0))
	observer.note("event_120", "lower detour sealed (C) — 40×30 at y=290 (full isolation)")
	observer.run_steps(220, true)
	var goal := Vector2(610.0, 210.0)
	var far_count := 0
	var empty_path_count := 0
	for unit in world.get_mobile_units():
		if unit.position.distance_to(goal) > 50.0:
			far_count += 1
		if not unit.arrived and unit.path.is_empty():
			empty_path_count += 1
	observer.note("units_far_from_goal", "%d/%d" % [far_count, world.get_mobile_units().size()])
	observer.note("empty_path_units", "%d/%d" % [empty_path_count, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_seal_behind_unit() -> void:
	# Box-in test: drop a full-height forward wall first to invalidate the
	# planned route, give 20 ticks for the cluster to rethink, then drop a
	# matching rear wall so retreat is also gone. Walls are tall (40×420)
	# so they span the full map height — every alternative (top edge, upper
	# detour, lower detour, bottom edge) is killed by a single drop.
	# Same `arrived` caveat as phase 13 — units that give up via
	# _settle_idle_unit are still counted as arrived. Real signal is
	# `units_far_from_goal`: a successful trap leaves every unit far
	# from (610, 210). units_far_from_goal == 0/N means the trap leaked.
	# This is the active variant of phase 5 — phase 5 walls before motion;
	# this phase walls *after* the cluster has moved and committed.
	var world := LabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "14_seal_behind_unit")
	observer.run_steps(30, false)
	world.add_static_obstacle(Vector2(480.0, 210.0), Vector2(40.0, 420.0))
	observer.note("event_30", "forward wall at x=480 (40×420) — target unreachable")
	observer.run_steps(20, false)
	world.add_static_obstacle(Vector2(180.0, 210.0), Vector2(40.0, 420.0))
	observer.note("event_50", "rear wall at x=180 (40×420) — boxed in")
	observer.run_steps(280, true)
	var goal := Vector2(610.0, 210.0)
	var far_count := 0
	for unit in world.get_mobile_units():
		if unit.position.distance_to(goal) > 50.0:
			far_count += 1
	observer.note("units_far_from_goal", "%d/%d" % [far_count, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_gap_close_mid_travel() -> void:
	# Funnel + late closure: a tall wall column at x=520 with a 50 px gap
	# centered at y=210 forces every unit toward that single opening. After
	# 80 ticks (units have committed to the gap and are funnelling through),
	# a third obstacle plugs the gap. Tests how mid-flight replans cope when
	# the planned path tail becomes blocked at the last moment.
	# Expectation: at most a few units slip through before closure; the rest
	# replan and either stop short or look for a long detour.
	var world := LabWorld.new()
	world.setup_default()
	world.add_static_obstacle(Vector2(520.0, 132.0), Vector2(40.0, 105.0))
	world.add_static_obstacle(Vector2(520.0, 287.0), Vector2(40.0, 105.0))
	world.set_group_target(Vector2(610.0, 210.0))
	var observer := PhaseObserver.new(world, "15_gap_close_mid_travel")
	observer.note("event_0", "wall column at x=520 with 50 px gap centered y=210")
	observer.run_steps(80, false)
	world.add_static_obstacle(Vector2(520.0, 210.0), Vector2(40.0, 50.0))
	observer.note("event_80", "gap plug dropped at y=210 — column now solid")
	observer.run_steps(260, true)
	_record(observer.finish())


func _phase_goal_blocked_at_arrival() -> void:
	# Mid-flight goal invalidation: the default target (610, 210) is open
	# until tick 200, then a 60×60 wall is dropped on top of it so the goal
	# point sits inside a static obstacle. add_static_obstacle triggers a
	# replan-all; the make-goal-reachable canonicalization should kick in
	# and split unit.target (player intent, still the original click) from
	# unit.path_target (canonical reachable stop). This is the active
	# (mid-flight) variant of phase 4 — it locks LAB-005 behavior under
	# late binding rather than a goal that was unreachable from t=0.
	var world := LabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "16_goal_blocked_at_arrival")
	var goal := Vector2(610.0, 210.0)
	observer.run_steps(200, false)
	var min_dist_at_drop := INF
	for unit in world.get_mobile_units():
		if not unit.arrived:
			min_dist_at_drop = minf(min_dist_at_drop, unit.position.distance_to(goal))
	world.add_static_obstacle(goal, Vector2(60.0, 60.0))
	observer.note("event_200", "60×60 wall dropped on goal (closest in-flight unit %.1f px away)" % min_dist_at_drop)
	observer.run_steps(220, true)
	var separated := 0
	for unit in world.get_mobile_units():
		if unit.target.distance_to(unit.path_target) > 0.5:
			separated += 1
	observer.note("target_path_target_separated", "%d/%d units" % [separated, world.get_mobile_units().size()])
	_record(observer.finish())


func _phase_alternating_corridor_seal() -> void:
	# Replan-pressure stress: only one of the two y-detours through the
	# default scene is passable at any moment, and which one flips every
	# 30 ticks. Initial state seals the upper detour; each swap removes the
	# current seal and drops the opposite one. Units that committed to the
	# now-closed corridor must reroute every cycle. 30 ticks ≈ one
	# REPLAN_INTERVAL — designed to keep the replan queue saturated.
	# Note: top-edge and bottom-edge routes remain open, so some units may
	# bypass the corridor flip entirely. The interesting observation is
	# total_replans and max_step_usec under the swap pressure.
	var world := LabWorld.new()
	world.setup_default()
	var observer := PhaseObserver.new(world, "17_alternating_corridor_seal")
	var upper_pos := Vector2(340.0, 130.0)
	var lower_pos := Vector2(340.0, 290.0)
	var seal_size := Vector2(40.0, 30.0)
	world.add_static_obstacle(upper_pos, seal_size)
	observer.note("event_0", "upper detour sealed — lower detour open")
	var upper_closed := true
	var swap_count := 0
	for i in range(360):
		if i > 0 and i % 30 == 0:
			if upper_closed:
				world.remove_nearest_editable(upper_pos, 50.0)
				world.add_static_obstacle(lower_pos, seal_size)
				upper_closed = false
			else:
				world.remove_nearest_editable(lower_pos, 50.0)
				world.add_static_obstacle(upper_pos, seal_size)
				upper_closed = true
			swap_count += 1
		observer.before_step()
		world.step(DT)
		observer.after_step()
	observer.note("seal_swaps", str(swap_count))
	observer.note("final_state", "upper_closed=%s" % str(upper_closed))
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
	if phase.ends_with("progressive_seal_all_paths"):
		var prog_far: String = str(notes.get("units_far_from_goal", "0/0"))
		if prog_far.begins_with("0/"):
			hits.append("seal ineffective: every unit reached goal before any corridor closure landed")
	if phase.ends_with("seal_behind_unit"):
		var trap_far: String = str(notes.get("units_far_from_goal", "0/0"))
		if trap_far.begins_with("0/"):
			hits.append("trap leaked: every unit reached goal — forward+rear walls did not isolate the cluster")
	if phase.ends_with("gap_close_mid_travel"):
		var gap_arrived: String = str(r.get("arrived", "0/0"))
		if gap_arrived.begins_with("0/"):
			hits.append("gap closure trapped all units — replan tail invalidation observation (no core blame yet)")
	if phase.ends_with("goal_blocked_at_arrival"):
		var goal_sep: String = str(notes.get("target_path_target_separated", ""))
		if goal_sep.begins_with("0/"):
			hits.append("LAB-005 (mid-flight canonicalization missing — target/path_target not separated after goal walled)")
	if phase.ends_with("alternating_corridor_seal"):
		var alt_replans: int = int(r.get("total_replans", 0))
		if alt_replans < 30:
			hits.append("replan starvation: only %d total replans across 360 ticks of seal swaps" % alt_replans)
	if hits.is_empty():
		return "(no flagged anomalies)"
	return ", ".join(hits)


# ---------------------------------------------------------------------------
# Fuzz mode (random exploration)
#
# Curated phases above cover scenarios the author thought of. Fuzz mode drives
# the lab with random ops and checks invariants — catches the unexpected
# combos the curated set misses. Each iteration starts from setup_default,
# applies random ops over `--ticks` ticks, and aborts on any invariant
# violation with a reproducible (iter, seed) pair.
# ---------------------------------------------------------------------------

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
	print("=== FUZZ MODE BEGIN === seed=%d iterations=%d ticks=%d" % [base_seed, iterations, ticks_per_iter])
	var passed := 0
	for iter in range(iterations):
		var iter_seed: int = base_seed + iter
		var rng := RandomNumberGenerator.new()
		rng.seed = iter_seed
		var result := _fuzz_run_iteration(iter, iter_seed, ticks_per_iter, rng)
		if not str(result.get("violation", "")).is_empty():
			print("FUZZ_VIOLATION: %s" % str(result))
			print("=== FUZZ MODE END === passed=%d violations=1 (early exit at iter %d)" % [passed, iter])
			print("Reproduce: -- --fuzz --seed=%d --iterations=%d --ticks=%d" % [iter_seed, 1, ticks_per_iter])
			get_tree().quit(1)
			return
		print("FUZZ_ITER: %s" % str(result))
		passed += 1
	print("=== FUZZ MODE END === passed=%d violations=0" % passed)
	get_tree().quit(0)


func _fuzz_run_iteration(iter: int, iter_seed: int, max_ticks: int, rng: RandomNumberGenerator) -> Dictionary:
	var world := LabWorld.new()
	world.setup_default()
	var ops_count: Dictionary = {}
	var prev_positions: Dictionary = {}
	for u in world.get_mobile_units():
		prev_positions[u.id] = u.position
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
		for u in world.get_mobile_units():
			var prev: Vector2 = prev_positions.get(u.id, u.position)
			var jump: float = u.position.distance_to(prev)
			if jump > max_jump_px:
				max_jump_px = jump
				max_jump_unit = u.id
				max_jump_at = tick
			prev_positions[u.id] = u.position
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
		"total_replans": world.total_replans,
	}


func _fuzz_random_op(rng: RandomNumberGenerator, world: LabWorld) -> Dictionary:
	var roll := rng.randf()
	if roll < 0.40:
		return {"op": "step"}
	if roll < 0.50:
		var target := Vector2(rng.randf_range(20.0, 700.0), rng.randf_range(20.0, 400.0))
		world.set_group_target(target)
		return {"op": "retarget", "target": str(target)}
	if roll < 0.54:
		var target := Vector2(rng.randf_range(800.0, 1500.0), rng.randf_range(-200.0, 600.0))
		world.set_group_target(target)
		return {"op": "retarget_offmap", "target": str(target)}
	if roll < 0.61:
		var center := Vector2(rng.randf_range(50.0, 670.0), rng.randf_range(50.0, 370.0))
		var size := Vector2(rng.randf_range(30.0, 80.0), rng.randf_range(30.0, 80.0))
		var obs_id := world.add_static_obstacle(center, size)
		return {"op": "add_obstacle", "id": obs_id, "center": str(center), "size": str(size)}
	if roll < 0.68:
		var center := Vector2(rng.randf_range(50.0, 670.0), rng.randf_range(50.0, 370.0))
		var radius := rng.randf_range(10.0, 20.0)
		var blocker_id := world.add_blocker(center, radius)
		return {"op": "add_blocker", "id": blocker_id, "center": str(center), "radius": "%.1f" % radius}
	if roll < 0.82:
		var point := Vector2(rng.randf_range(0.0, 720.0), rng.randf_range(0.0, 420.0))
		var removed := world.remove_nearest_editable(point, 80.0)
		return {"op": "remove", "point": str(point), "removed": removed}
	if roll < 0.88:
		# split_target: command a random subset of mobile units to a separate
		# target. Tests partial-group commands and replan-queue behavior when
		# different units have unrelated paths.
		var ids := world.get_mobile_unit_ids()
		if ids.is_empty():
			return {"op": "step"}
		var subset_size: int = rng.randi_range(1, maxi(1, ids.size() - 1))
		var picked: Array[String] = []
		var pool: Array[String] = ids.duplicate()
		for _i in range(subset_size):
			if pool.is_empty():
				break
			var idx: int = rng.randi_range(0, pool.size() - 1)
			picked.append(pool[idx])
			pool.remove_at(idx)
		var target := Vector2(rng.randf_range(20.0, 700.0), rng.randf_range(20.0, 400.0))
		world.set_units_target(picked, target)
		return {"op": "split_target", "subset_size": picked.size(), "subset": picked, "target": str(target)}
	if roll < 0.92:
		# add_obstacle_tiny: degenerate sub-cell obstacle (cell_size=16). Tests
		# rasterization edge cases — rect smaller than a navcell.
		var center := Vector2(rng.randf_range(50.0, 670.0), rng.randf_range(50.0, 370.0))
		var size := Vector2(rng.randf_range(1.0, 8.0), rng.randf_range(1.0, 8.0))
		var obs_id := world.add_static_obstacle(center, size)
		return {"op": "add_obstacle_tiny", "id": obs_id, "center": str(center), "size": str(size)}
	if roll < 0.95:
		# add_blocker_huge: radius 40-80 is comparable to a quarter of the
		# map. Tests overlap-resolve under a single dominating blocker.
		var center := Vector2(rng.randf_range(100.0, 620.0), rng.randf_range(100.0, 320.0))
		var radius := rng.randf_range(40.0, 80.0)
		var blocker_id := world.add_blocker(center, radius)
		return {"op": "add_blocker_huge", "id": blocker_id, "center": str(center), "radius": "%.1f" % radius}
	if roll < 0.98:
		# retarget_to_unit: chase another unit's current position. Tests
		# moving-target replans (path_target the lab thinks valid moves
		# every replan).
		var ids := world.get_mobile_unit_ids()
		if ids.is_empty():
			return {"op": "step"}
		var picked_id: String = ids[rng.randi_range(0, ids.size() - 1)]
		var picked_unit := world.get_unit_by_id(picked_id)
		if picked_unit == null:
			return {"op": "step"}
		var target: Vector2 = picked_unit.position
		world.set_group_target(target)
		return {"op": "retarget_to_unit", "target_unit": picked_id, "target": str(target)}
	# retarget_to_obstacle: command into an existing obstacle's center.
	# Tests mid-flight make-goal-reachable canonicalization (LAB-005 active
	# variant under fuzz timing, not just phase 4's static setup).
	if world.obstacles.is_empty():
		return {"op": "step"}
	var picked_obs := world.obstacles[rng.randi_range(0, world.obstacles.size() - 1)]
	var obs_center: Vector2 = picked_obs.center
	world.set_group_target(obs_center)
	return {"op": "retarget_to_obstacle", "obstacle_id": picked_obs.id, "target": str(obs_center)}


func _fuzz_dump_world(world: LabWorld, prev_positions: Dictionary) -> Dictionary:
	var obstacles: Array[Dictionary] = []
	for obstacle in world.obstacles:
		obstacles.append({
			"id": obstacle.id,
			"center": str(obstacle.center),
			"size": str(obstacle.size),
		})
	var blockers: Array[Dictionary] = []
	var units: Array[Dictionary] = []
	for unit in world.units:
		var unit_dict := {
			"id": unit.id,
			"pos": str(unit.position),
			"radius": "%.2f" % unit.radius,
			"mobile": unit.mobile,
		}
		if unit.mobile:
			unit_dict["target"] = str(unit.target)
			unit_dict["path_target"] = str(unit.path_target)
			unit_dict["arrived"] = unit.arrived
			unit_dict["has_move_order"] = unit.has_move_order
			unit_dict["path_size"] = unit.path.size()
			unit_dict["prev_pos"] = str(prev_positions.get(unit.id, unit.position))
			units.append(unit_dict)
		else:
			blockers.append(unit_dict)
	return {
		"obstacles": obstacles,
		"obstacle_count": obstacles.size(),
		"blockers": blockers,
		"blocker_count": blockers.size(),
		"mobile_units": units,
	}


func _fuzz_check_invariants(world: LabWorld, prev_positions: Dictionary, tick: int, last_op: Dictionary) -> String:
	var map_x_max: float = world.map_size.x + FUZZ_MAP_MARGIN
	var map_y_max: float = world.map_size.y + FUZZ_MAP_MARGIN
	# Cache obstacle rects once — used for the jump-check exemption below.
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
		var prev: Vector2 = prev_positions.get(unit.id, unit.position)
		var jump: float = unit.position.distance_to(prev)
		if jump > FUZZ_MAX_JUMP_PX:
			# Exempt: unit prev_pos was inside any inflated obstacle rect.
			# This covers (a) obstacle just dropped on the unit and (b) unit
			# still being unwound from a chained component over multiple ticks.
			# In either case the push-out is doing its job — large jump is
			# the geometrically-correct response, not a teleport bug.
			# A teleport with prev_pos in free space is still flagged.
			var inside_obstacle := false
			for rect in obstacle_rects:
				if rect.grow(unit.radius).has_point(prev):
					inside_obstacle = true
					break
			if not inside_obstacle:
				return "jump tick=%d unit=%s jump=%.2f prev=%s curr=%s last_op=%s" % [tick, unit.id, jump, str(prev), str(unit.position), str(last_op)]
	return ""
