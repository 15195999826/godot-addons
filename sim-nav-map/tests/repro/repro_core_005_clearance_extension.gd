extends Node

# CORE-005: CLEARANCE_EXTENSION_RADIUS not implemented
#
# Bug reproduced here:
#   - sim_nav_map.gd:404-421 rasterizes static obstructions using only the
#     pass class's clearance, no +1 navcell extension.
#   - 0 A.D. (Pathfinding.h:157-160) extends clearance by 1 navcell during
#     long-path rasterization to guarantee long-path is more conservative
#     than short-path. Without it the long-vs-short invariant is broken.
#
# Repro: 16×16 grid, navcell_size=8. Pass class clearance=0. Place a 1-cell
#     OBB centered at navcell (7,7). The body covers exactly that one cell.
#     Per the +1 extension, the navcells immediately adjacent — including
#     (8,7), (6,7), (7,8), (7,6) — should be impassable too (within 1
#     navcell of the body).
#
# At HEAD: only (7,7) is impassable; (8,7) etc. are passable. FAIL.
# After fix: (8,7) and the other adjacent navcells become impassable. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_005_clearance_extension.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-005 clearance extension radius (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-005 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(16, 16, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)

	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "single_cell_wall"
	blocker.center = Vector2(60.0, 60.0)
	blocker.width = 8.0
	blocker.height = 8.0
	blocker.rotation_rad = 0.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(blocker)
	nav_map.rebuild_dirty()

	var body_cell := Vector2i(7, 7)
	if nav_map.is_passable_navcell(body_cell, pass_mask):
		_failures.append(
			"setup error: body navcell %s should already be impassable at HEAD (rasterization broken)"
			% str(body_cell)
		)
		return

	var adjacent_cells: Array[Vector2i] = [
		Vector2i(8, 7),
		Vector2i(6, 7),
		Vector2i(7, 8),
		Vector2i(7, 6),
	]
	for cell in adjacent_cells:
		if nav_map.is_passable_navcell(cell, pass_mask):
			_failures.append(
				"navcell %s (1 navcell from OBB body) is passable; expected impassable per CLEARANCE_EXTENSION_RADIUS"
				% str(cell)
			)
