extends Node

# CORE-014: Genuine-overlap escape must be strict binary (0 A.D. TestRaySquare)
# — a stay-or-deeper guard strands the unit because per-frame motion candidates
# whose tangent geometry briefly heads inward all get blocked.
#
# Bug reproduced here:
#   - From 0ad-rts-pathfinding-lab tick 3742, log 2026-05-10T19-35-04.
#   - blue_1 at (491.67, 200.28), goal (486, 33). blue_3 stationary at
#     (472, 191) — distance 21.75, GENUINE overlap (Euclidean < 22).
#   - Short path picked SW corner (481.5, 164.5) of blue_2 as first waypoint
#     (a sane northwest detour around blue_3).
#   - Motion's per-frame ~1.6 px candidate toward that waypoint lands at
#     (491.23, 198.74). distance(candidate, blue_3) = 20.73 — closer to
#     blue_3 by 1 px than start was, because the path runs tangent through
#     blue_3's NE quadrant before clearing west.
#   - Before fix: the genuine-overlap branch had an added stay-or-deeper guard
#     `if target_dist <= start_dist + 0.0001: return true`. Every per-frame
#     candidate hit it (20.73 < 21.75) → motion blocked → max_failed_movements.
#     This guard was lab-self-invented and violated 0 A.D.'s strict binary
#     (Geometry.cpp:280-281: `a inside → return false` regardless of b).
#
# 0 A.D. expected (Geometry.cpp:280-281 TestRaySquare):
#   ```
#   if (-hw <= au && au <= hw && -hh <= av && av <= hh)
#       return false; // a is inside
#   ```
#   No examination of 'b' once 'a' is inside. The pushing system + reactive
#   blocked recovery separate genuinely overlapping units across many frames;
#   single-frame LOS does not need to "protect" against drift.
#
# Fix (sim_nav_line_of_sight.gd _unit_shape_blocks_segment): the
# `start_dist < collision_threshold` branch returns false unconditionally.
# The lab-side line_validation smoke and CORE-012 stay test were updated to
# reflect this — their stay-or-deeper assertions were the same lab invention.
#
# Before fix: per-frame candidate from real overlap, tangent-deeper toward
# blue_3, blocked. FAIL.
# After fix: candidate accepted; unit makes progress through tangent path
# while push system handles the actual separation. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_014_overlap_escape_must_be_strict_binary.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-014 overlap escape strict binary (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-014 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var blue_3 := SimNavObstructionShapeUnit.new()
	blue_3.entity_id = "blue_3"
	blue_3.center = Vector2(472.0, 191.0)
	blue_3.clearance = 11.0
	blue_3.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
	blue_3.moving = false

	# Genuine overlap (Euclidean 21.75 < collision 22) escaping toward NW.
	# Mid-frame candidate has dist 20.73 — slightly DEEPER than start.
	# 0 A.D. binary: a inside → unblock regardless.
	var start := Vector2(491.670532226563, 200.28401184082)
	var candidate := Vector2(491.234, 198.745)
	var blocked := SimNavLineOfSight.shape_blocks_segment(start, candidate, blue_3, 11.0)
	if blocked:
		var sd := start.distance_to(blue_3.center)
		var td := candidate.distance_to(blue_3.center)
		_failures.append(
			"per-frame candidate %s->%s wrongly blocked from genuine overlap; start_dist=%.3f cand_dist=%.3f (cand 1 px closer than start, but 0 A.D. binary allows escape regardless of direction)"
			% [str(start), str(candidate), sd, td]
		)

	# Full segment to first waypoint (blue_2's SW corner) must also pass.
	var sw_corner := Vector2(481.5, 164.5)
	var full_blocked := SimNavLineOfSight.shape_blocks_segment(start, sw_corner, blue_3, 11.0)
	if full_blocked:
		_failures.append("full overlap escape segment %s->%s wrongly blocked" % [str(start), str(sw_corner)])

	# Pure stay-inside / deeper-inside also must NOT block under 0 A.D. binary.
	# (lab smoke previously asserted this should block — that was the lab
	# self-invented guard, not 0 A.D. behaviour.)
	var stay_blocked := SimNavLineOfSight.shape_blocks_segment(
		Vector2(465.0, 191.0), Vector2(472.0, 191.0), blue_3, 11.0
	)
	if stay_blocked:
		_failures.append("stay-deeper from genuine overlap should NOT block (binary inside rule)")

	# But entering from outside MUST still block (binary inside rule applies
	# only when 'a' is already inside).
	var enter_blocked := SimNavLineOfSight.shape_blocks_segment(
		Vector2(450.0, 191.0), Vector2(472.0, 191.0), blue_3, 11.0
	)
	if not enter_blocked:
		_failures.append("entering obstacle from outside %s->%s must still block" % [str(Vector2(450.0, 191.0)), str(Vector2(472.0, 191.0))])
