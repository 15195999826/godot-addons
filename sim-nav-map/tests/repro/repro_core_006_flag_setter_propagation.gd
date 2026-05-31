extends Node

# CORE-006: Per-tag flag mutation API incomplete (dirty propagation missing)
#
# Bug reproduced here:
#   - sim_nav_obstruction_manager.gd:69-88 only exposes set_unit_moving_flag()
#     and set_control_group(). Direct mutation of `shape.flags` does NOT mark
#     the affected navcells dirty.
#   - SimNavMap.rebuild_dirty() does a full re-rasterization, so the eventual
#     navcell state is correct — but consumers that rely on dirty bits
#     (hierarchical recompute_dirty, jump-point cache, AI dirty export) miss
#     the change. They don't know which cells were affected.
#
# Repro: add a static OBB with BLOCK_PATHFINDING. rebuild_dirty + clear all
#     dirty bits → clean baseline. Mutate `shape.flags = 0` directly. Inspect
#     dirty state: the OBB body region should be marked dirty so an
#     incremental consumer can re-evaluate it.
#
# At HEAD: no dirty bits set after direct mutation. FAIL.
# After fix:
#   - set_static_flags / set_unit_flags marks affected navcells dirty.
#   - direct flag mutation no longer remains silently invisible while the
#     public flags field exists (property setter / debug guard / callsite guard).
# The body region is dirty. PASS.
#
# Run: godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_006_flag_setter_propagation.tscn


var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - CORE-006 flag mutation dirty propagation (no longer reproduces)")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - CORE-006 reproduces: %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(16, 16, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 0.0
	ground.affects_pathfinding = true
	var pass_mask := nav_map.register_passability_class(ground)

	var blocker := SimNavObstructionShapeStatic.new()
	blocker.entity_id = "togglable_wall"
	blocker.center = Vector2(60.0, 60.0)
	blocker.width = 8.0
	blocker.height = 8.0
	blocker.rotation_rad = 0.0
	blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	var tag := nav_map.add_static_obstruction(blocker)
	nav_map.rebuild_dirty()

	# Establish a clean baseline: rasterization done, no pending dirty cells.
	nav_map.clear_dirty_navcells()
	nav_map.clear_dirty_obstruction_navcells()
	if nav_map.has_dirty_navcells() or nav_map.has_dirty_obstruction_navcells():
		_failures.append("setup error: dirty state should be clean after explicit clear")
		return

	var manager := SimNavObstructionManager.new(nav_map)
	if manager.has_method("set_static_flags"):
		manager.call("set_static_flags", tag, 0)
		_assert_has_dirty(nav_map, "set_static_flags(0)")
		nav_map.rebuild_dirty()
		nav_map.clear_dirty_navcells()
		nav_map.clear_dirty_obstruction_navcells()
		blocker.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
		_assert_has_dirty(nav_map, "direct mutation (shape.flags = BLOCK_PATHFINDING)")
	else:
		# Bug-exposure path: direct mutation of shape.flags. Should but does
		# not mark affected navcells dirty.
		blocker.flags = 0
		_assert_has_dirty(nav_map, "direct mutation (shape.flags = 0)")

func _assert_has_dirty(nav_map: SimNavMap, path_label: String) -> void:
	var has_dirty := nav_map.has_dirty_navcells() or nav_map.has_dirty_obstruction_navcells()
	if not has_dirty:
		_failures.append(
			"after %s, no navcells were marked dirty — incremental consumers (hierarchical / jump cache / AI export) cannot detect the flag change"
			% path_label
		)
