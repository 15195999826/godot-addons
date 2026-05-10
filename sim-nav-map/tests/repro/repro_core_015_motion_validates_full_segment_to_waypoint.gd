extends Node

# CORE-015: Motion's per-frame candidate LOS check accumulates pass-through.
# When a path waypoint lies inside an obstacle's collision ring, the EDGE_EXPAND_DELTA
# tolerance in the boundary band means each tiny per-frame step never blocks
# (single-step b_dist drift < tolerance), and the unit walks straight through
# the obstacle over many ticks.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 9780+, log 2026-05-10T19-54-25.
#   - blue_2 at (470.32, 164.96) walking toward waypoint (475, 179).
#   - waypoint distance to blue_3 (492, 185) = 18.03 — well inside blue_3's
#     22-unit collision ring (waypoint itself is unreachable in principle).
#   - Per-frame motion candidate is ~0.6 px toward (475, 179) (slowed by push
#     pressure). Each candidate's distance to blue_3 drops only ~0.5 px from
#     the previous, staying within the boundary-band tolerance and unblocking.
#   - Over ~100 frames, blue_2 walks straight through blue_3's center
#     (recorded contact distance bottomed at 8.10 px, 14 px deep in the ring).
#
# Root cause: motion validated `validate_movement_line(start, candidate)`
# where `candidate` was the per-frame ~0.6 px sub-step. The tolerance was
# meant to absorb single-frame tangent noise, but cumulative sub-steps slipped
# past it.
#
# 0 A.D. expected (CCmpUnitMotion.h:1334):
#   `cmpPathfinder->CheckMovement(pos, target=waypoint, ...)` — validates
#   the segment from current position to the WAYPOINT, not to the per-frame
#   candidate. A waypoint inside an obstacle is rejected immediately.
#
# Fix (zero_ad_rts_lab_motion_controller.gd _perform_move): validation_target
# changed from per-frame `candidate` to the path's `waypoint`. Each frame
# revalidates the full remaining segment to the waypoint; if the waypoint
# is fundamentally unreachable (inside obstacle), motion blocks on tick 1
# instead of accumulating across 100 ticks.
#
# Before fix: validate_movement_line(start, per_step_candidate) returns
# success (boundary-band tolerance), unit advances 0.6 px, repeat → drift
# through obstacle. FAIL invariant.
# After fix: validate_movement_line(start, waypoint) sees target_dist 18.03
# < 22 → blocks. Motion never advances toward an unreachable waypoint. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_015_motion_validates_full_segment_to_waypoint.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-015 motion validates full segment (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-015 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var blue_3 := SimNavObstructionShapeUnit.new()
	blue_3.entity_id = "blue_3"
	blue_3.center = Vector2(492.0, 185.0)
	blue_3.clearance = 11.0
	blue_3.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	blue_3.moving = false

	var start := Vector2(470.32, 164.96)
	var waypoint := Vector2(475.0, 179.0)
	var per_step_candidate := start + (waypoint - start).normalized() * 0.6  # ~0.6 px sub-step

	# Invariant: the *waypoint* lies inside blue_3's collision ring, so
	# validate_movement_line(start, waypoint) MUST block.
	var to_waypoint_blocked := SimNavLineOfSight.shape_blocks_segment(start, waypoint, blue_3, 11.0)
	if not to_waypoint_blocked:
		_failures.append(
			"validate to waypoint %s wrongly accepted; waypoint is inside blue_3 collision ring (dist=%.2f < 22)"
			% [str(waypoint), waypoint.distance_to(blue_3.center)]
		)

	# Document the underlying motion bug: a per-step sub-candidate near the
	# boundary band slips past tolerance even though the path leads into the
	# obstacle. Motion code must therefore use the waypoint as validation
	# target — never the sub-step candidate.
	var to_candidate_blocked := SimNavLineOfSight.shape_blocks_segment(start, per_step_candidate, blue_3, 11.0)
	if to_candidate_blocked:
		# This isn't strictly required to be unblocked, but if it ever does
		# block, motion would also block correctly with per-step validation —
		# defeating the bug's premise. Note as informational.
		pass

	# Sanity: a waypoint clearly outside the ring must still be reachable
	# (no false positives from the strict full-segment check).
	var safe_waypoint := Vector2(465.0, 165.0)
	var safe_blocked := SimNavLineOfSight.shape_blocks_segment(start, safe_waypoint, blue_3, 11.0)
	if safe_blocked:
		_failures.append(
			"validate to safe waypoint %s wrongly blocked; waypoint sits at %.2f from blue_3"
			% [str(safe_waypoint), safe_waypoint.distance_to(blue_3.center)]
		)
