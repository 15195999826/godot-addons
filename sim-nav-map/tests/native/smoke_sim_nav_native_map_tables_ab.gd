extends Node

# M2 A/B weld: the native CoreMap + JumpTables must reproduce the GDScript
# SimNavMap + SimNavJumpPointCache byte-for-byte — composed navcell data,
# dirty enumerations, baked grids, all four ray tables, the table-driven jump
# dispatch, and both raster line walks. Covered lifecycles: initial
# rebuild_dirty, rasterize_dirty_obstructions round + incremental band repair
# (structurally asserted incremental), mass-edit repair fallback (structurally
# asserted full reset), a navcells_per_tile=3 / negative-origin fixture whose
# edit round flushes through rebuild_dirty, and no-crash guards on invalid
# native-boundary arguments. Native classes are reached via ClassDB only.

const MAP_W := 165
const MAP_H := 113
const CELL := 8.0
const BLOCK_PATHFINDING := 8  # SimNavObstructionFlags.BLOCK_PATHFINDING
const BLOCK_MOVEMENT := 1

var _failures: Array[String] = []

var _gd_map: SimNavMap = null
var _nmap: Object = null
# tag -> tag parity is asserted at every registration, so shared tags work.
var _tags: Array[int] = []
var _ground_mask := 0
var _large_mask := 0


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - native map+tables A/B byte-identical")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	if not ClassDB.class_exists("SimNavNativeMap") or not ClassDB.class_exists("SimNavNativeJumpPointCache"):
		_failures.append("native classes missing (build native/ first)")
		return
	_run_main_fixture()
	if not _failures.is_empty():
		return
	_run_mini_fixture()
	if not _failures.is_empty():
		return
	_run_invalid_args_probes()


# ── Main fixture: lab-shaped map, rasterize-flush edit round, repair paths ───

func _run_main_fixture() -> void:
	_gd_map = SimNavMap.new(MAP_W, MAP_H, CELL, Vector2.ZERO, 1)
	_nmap = ClassDB.instantiate("SimNavNativeMap")
	_nmap.call("setup", MAP_W, MAP_H, CELL, Vector2.ZERO, 1)
	_tags = []

	_ground_mask = _register_class("ground", 12.0, true, 1)
	_large_mask = _register_class("large", 20.0, true, 2)
	if _ground_mask == 0 or _large_mask == 0:
		return

	_gd_map.set_bounds(12.0, 12.0, MAP_W * CELL - 12.0, MAP_H * CELL - 12.0)
	_nmap.call("set_bounds", 12.0, 12.0, MAP_W * CELL - 12.0, MAP_H * CELL - 12.0)

	for i in range(30):
		_set_terrain(Vector2i(20 + i, 15 + i), 1)
	for i in range(20):
		_set_terrain(Vector2i(40 + i, 80), 2)
	_set_terrain(Vector2i(90, 20), 3)

	_add_static(Vector2(200, 200), 120, 40, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(480, 300), 60, 220, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(700, 500), 90, 90, 0.35, BLOCK_PATHFINDING)
	_add_static(Vector2(900, 250), 140, 50, -1.2, BLOCK_PATHFINDING)
	_add_static(Vector2(300, 650), 200, 30, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(1000, 700), 80, 80, 0.0, BLOCK_MOVEMENT)
	_add_static(Vector2(600, 120), 50, 50, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(630, 140), 50, 50, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(30, 30), 80, 80, 0.0, BLOCK_PATHFINDING)

	for x in range(50, 60):
		_gd_map.or_navcell_data(Vector2i(x, 5), _ground_mask)
		_nmap.call("or_navcell_data", Vector2i(x, 5), _ground_mask)

	_gd_map.rebuild_dirty()
	_nmap.call("rebuild_dirty")

	_compare_map_state("initial rebuild_dirty")
	_compare_center_world_samples()

	var gd_ground := SimNavJumpPointCache.new()
	gd_ground.reset(_gd_map, _ground_mask)
	var gd_large := SimNavJumpPointCache.new()
	gd_large.reset(_gd_map, _large_mask)
	var n_ground: Object = ClassDB.instantiate("SimNavNativeJumpPointCache")
	n_ground.call("reset", _nmap, _ground_mask)
	var n_large: Object = ClassDB.instantiate("SimNavNativeJumpPointCache")
	n_large.call("reset", _nmap, _large_mask)

	_compare_tables("ground initial", gd_ground, n_ground)
	_compare_tables("large initial", gd_large, n_large)
	_sweep_jump_points("ground initial", gd_ground, n_ground, 3)
	_sweep_lines("ground initial", gd_ground, n_ground, 500)
	_sweep_lines("large initial", gd_large, n_large, 250)

	_gd_map.clear_dirty_navcells()
	_nmap.call("clear_dirty_navcells")

	# ── Incremental edit round (facade-flush shaped) ─────────────────────────
	_gd_map.move_obstruction(_tags[0], Vector2(240, 220), 0.0)
	_nmap.call("move_obstruction", _tags[0], Vector2(240, 220), 0.0)
	_gd_map.remove_obstruction(_tags[7])
	_nmap.call("remove_obstruction", _tags[7])
	_add_static(Vector2(760, 640), 100, 36, 0.0, BLOCK_PATHFINDING)
	_set_terrain(Vector2i(25, 20), 0)
	_set_terrain(Vector2i(90, 60), 2)
	_gd_map.or_navcell_data(Vector2i(70, 10), _large_mask)
	_nmap.call("or_navcell_data", Vector2i(70, 10), _large_mask)
	var gd_changed := _gd_map.rasterize_dirty_obstructions()
	var n_changed := int(_nmap.call("rasterize_dirty_obstructions"))
	if gd_changed != n_changed:
		_failures.append("rasterize changed-count mismatch (gd=%d native=%d)" % [gd_changed, n_changed])
	_compare_map_state("after rasterize_dirty_obstructions")

	gd_ground.repair_dirty_cells(_gd_map.collect_dirty_navcells())
	gd_large.repair_dirty_cells(_gd_map.collect_dirty_navcells())
	n_ground.call("repair_for_map_dirty")
	n_large.call("repair_for_map_dirty")

	# Structural: the small edit round must ride the incremental band repair
	# on BOTH implementations (a silent full-reset fallback would hide repair
	# bugs).
	if gd_ground.repair_count != 1 or gd_ground.full_reset_count != 1:
		_failures.append("gd ground cache did not take the incremental path (repairs=%d resets=%d)" % [gd_ground.repair_count, gd_ground.full_reset_count])
	if int(n_ground.call("repair_count")) != 1 or int(n_ground.call("full_reset_count")) != 1:
		_failures.append("native ground cache did not take the incremental path (repairs=%d resets=%d)" % [int(n_ground.call("repair_count")), int(n_ground.call("full_reset_count"))])

	# Native repair == native full rebuild (the GDScript twin of this weld is
	# smoke_sim_nav_jump_table_repair).
	var n_fresh: Object = ClassDB.instantiate("SimNavNativeJumpPointCache")
	n_fresh.call("reset", _nmap, _ground_mask)
	if not bool(n_fresh.call("tables_equal", n_ground)):
		_failures.append("native repaired tables != native full rebuild (ground)")

	_compare_tables("ground repaired", gd_ground, n_ground)
	_compare_tables("large repaired", gd_large, n_large)

	_gd_map.clear_dirty_navcells()
	_nmap.call("clear_dirty_navcells")

	_sweep_jump_points("ground repaired", gd_ground, n_ground, 5)
	_sweep_lines("ground repaired", gd_ground, n_ground, 250)

	# ── Mass edit: the repair band condition must fall back to a full reset.
	# A diagonal spread dirties ~every row and column (the fallback condition
	# counts unique rows/cols, not cell count), without paying thousands of
	# terrain-window recomputes on the GDScript twin.
	for i in range(MAP_H):
		var cell := Vector2i((i * 2) % MAP_W, i)
		_gd_map.or_navcell_data(cell, _ground_mask)
		_nmap.call("or_navcell_data", cell, _ground_mask)
	_compare_map_state("after mass diagonal edit")

	gd_ground.repair_dirty_cells(_gd_map.collect_dirty_navcells())
	n_ground.call("repair_for_map_dirty")
	if gd_ground.full_reset_count != 2 or gd_ground.repair_count != 1:
		_failures.append("gd ground cache did not take the fallback reset (repairs=%d resets=%d)" % [gd_ground.repair_count, gd_ground.full_reset_count])
	if int(n_ground.call("full_reset_count")) != 2 or int(n_ground.call("repair_count")) != 1:
		_failures.append("native ground cache did not take the fallback reset (repairs=%d resets=%d)" % [int(n_ground.call("repair_count")), int(n_ground.call("full_reset_count"))])
	_compare_tables("ground after fallback reset", gd_ground, n_ground)

	_gd_map.clear_dirty_navcells()
	_nmap.call("clear_dirty_navcells")
	_sweep_lines("ground after fallback", gd_ground, n_ground, 200)


# ── Mini fixture: navcells_per_tile=3, negative origin, rebuild_dirty flush ──

func _run_mini_fixture() -> void:
	_gd_map = SimNavMap.new(60, 45, CELL, Vector2(-64.0, 32.0), 3)
	_nmap = ClassDB.instantiate("SimNavNativeMap")
	_nmap.call("setup", 60, 45, CELL, Vector2(-64.0, 32.0), 3)
	_tags = []

	_ground_mask = _register_class("ground", 12.0, true, 1)
	if _ground_mask == 0:
		return

	_set_terrain(Vector2i(3, 4), 1)
	_set_terrain(Vector2i(10, 2), 1)
	_set_terrain(Vector2i(6, 7), 2)

	# Straddles the west edge: exercises negative world coords and negative
	# spatial-index cells.
	_add_static(Vector2(-40.0, 120.0), 90, 60, 0.0, BLOCK_PATHFINDING)
	_add_static(Vector2(150.0, 200.0), 70, 30, 0.8, BLOCK_PATHFINDING)
	_add_static(Vector2(300.0, 300.0), 40, 40, 0.0, BLOCK_PATHFINDING)

	_gd_map.rebuild_dirty()
	_nmap.call("rebuild_dirty")
	_compare_map_state("mini initial")
	_compare_center_world_samples()

	var gd_cache := SimNavJumpPointCache.new()
	gd_cache.reset(_gd_map, _ground_mask)
	var n_cache: Object = ClassDB.instantiate("SimNavNativeJumpPointCache")
	n_cache.call("reset", _nmap, _ground_mask)
	_compare_tables("mini initial", gd_cache, n_cache)
	_sweep_jump_points("mini initial", gd_cache, n_cache, 2)
	_sweep_lines("mini initial", gd_cache, n_cache, 250)

	_gd_map.clear_dirty_navcells()
	_nmap.call("clear_dirty_navcells")

	# Edit round flushed through rebuild_dirty (the other flush lifecycle).
	_gd_map.move_obstruction(_tags[0], Vector2(-20.0, 150.0), 0.1)
	_nmap.call("move_obstruction", _tags[0], Vector2(-20.0, 150.0), 0.1)
	_gd_map.remove_obstruction(_tags[2])
	_nmap.call("remove_obstruction", _tags[2])
	_add_static(Vector2(220.0, 120.0), 55, 25, 0.0, BLOCK_PATHFINDING)
	_set_terrain(Vector2i(3, 4), 0)
	_gd_map.rebuild_dirty()
	_nmap.call("rebuild_dirty")
	_compare_map_state("mini after rebuild_dirty")

	gd_cache.repair_dirty_cells(_gd_map.collect_dirty_navcells())
	n_cache.call("repair_for_map_dirty")
	_compare_tables("mini repaired", gd_cache, n_cache)
	_gd_map.clear_dirty_navcells()
	_nmap.call("clear_dirty_navcells")
	_sweep_lines("mini repaired", gd_cache, n_cache, 200)


# ── Invalid native-boundary args must not crash ──────────────────────────────

func _run_invalid_args_probes() -> void:
	print("[m2-ab] invalid-args probes: expected native errors follow")
	var fresh_cache: Object = ClassDB.instantiate("SimNavNativeJumpPointCache")
	var before_reset := Vector2i(fresh_cache.call("jump_point", Vector2i(1, 1), Vector2i(1, 0), Vector2i(5, 5)))
	if before_reset != Vector2i(1, 1):
		_failures.append("pre-reset jump_point should return start (got %s)" % before_reset)
	fresh_cache.call("repair_for_map_dirty")  # unbound: error, no crash

	var n_cache: Object = ClassDB.instantiate("SimNavNativeJumpPointCache")
	n_cache.call("reset", _nmap, _ground_mask)
	var bad_dir := Vector2i(n_cache.call("jump_point", Vector2i(2, 2), Vector2i(2, 0), Vector2i(5, 5)))
	if bad_dir != Vector2i(2, 2):
		_failures.append("invalid-direction jump_point should return start (got %s)" % bad_dir)
	var oob_start := Vector2i(n_cache.call("jump_point", Vector2i(-3, 9999), Vector2i(1, 0), Vector2i(5, 5)))
	if oob_start != Vector2i(-3, 9999):
		_failures.append("oob-start jump_point should return start (got %s)" % oob_start)

	if bool(_nmap.call("remove_obstruction", 1 << 40)):
		_failures.append("remove_obstruction with out-of-domain tag should return false")

	var bad_map: Object = ClassDB.instantiate("SimNavNativeMap")
	bad_map.call("setup", -5, 10, 8.0, Vector2.ZERO, 1)
	if int(bad_map.call("get_width")) != 0:
		_failures.append("negative-size setup should be rejected")
	bad_map.call("setup", 10, 10, 0.0, Vector2.ZERO, 1)
	if int(bad_map.call("get_width")) != 0:
		_failures.append("zero navcell_size setup should be rejected")
	print("[m2-ab] invalid-args probes done")


# ── Twin drivers (apply to both stacks in identical order) ───────────────────

func _register_class(class_name_id: String, clearance: float, affects: bool, terrain_mask: int) -> int:
	var config := SimNavPassabilityClassConfig.new()
	config.class_name_id = class_name_id
	config.clearance = clearance
	config.affects_pathfinding = affects
	config.terrain_mask = terrain_mask
	var gd_mask := _gd_map.register_passability_class(config)
	var n_mask := int(_nmap.call("register_passability_class", class_name_id, clearance, affects, terrain_mask))
	if gd_mask != n_mask:
		_failures.append("passability mask mismatch for %s (gd=%d native=%d)" % [class_name_id, gd_mask, n_mask])
		return 0
	return gd_mask


func _set_terrain(tile: Vector2i, value: int) -> void:
	_gd_map.set_terrain_tile_data(tile, value)
	_nmap.call("set_terrain_tile_data", tile, value)


func _add_static(center: Vector2, width: float, height: float, rotation_rad: float, flags: int) -> void:
	var shape := SimNavObstructionShapeStatic.new()
	shape.entity_id = str(_tags.size() + 1)
	shape.center = center
	shape.width = width
	shape.height = height
	shape.rotation_rad = rotation_rad
	shape.flags = flags
	var gd_tag := _gd_map.add_static_obstruction(shape)
	var n_tag := int(_nmap.call("add_static_obstruction", str(_tags.size() + 1), center, width, height, rotation_rad, flags))
	if gd_tag != n_tag:
		_failures.append("obstruction tag mismatch (gd=%d native=%d)" % [gd_tag, n_tag])
	_tags.append(gd_tag)


# ── Comparators ──────────────────────────────────────────────────────────────

func _compare_map_state(label: String) -> void:
	var map_w := _gd_map.width
	var gd_composed := _gd_map.composed_navcell_data()
	var n_composed: PackedInt32Array = _nmap.call("composed_navcell_data")
	if gd_composed != n_composed:
		var diff := _first_diff(gd_composed, n_composed)
		@warning_ignore("integer_division")
		var diff_y: int = diff / map_w
		_failures.append("%s: composed navcell data differs (first diff idx=%d cell=(%d,%d) gd=%d native=%d, total=%d)" % [
			label, diff, diff % map_w, diff_y, gd_composed[diff], n_composed[diff], _count_diffs(gd_composed, n_composed)])
	var gd_dirty := _gd_map.collect_dirty_navcells()
	var n_dirty := _unpack_cells(_nmap.call("collect_dirty_navcells_packed"))
	if gd_dirty != n_dirty:
		_failures.append("%s: dirty navcell list differs (gd=%d cells, native=%d cells)" % [label, gd_dirty.size(), n_dirty.size()])
	if _gd_map.dirty_navcell_revision() != int(_nmap.call("dirty_navcell_revision")):
		_failures.append("%s: dirty revision differs (gd=%d native=%d)" % [label, _gd_map.dirty_navcell_revision(), int(_nmap.call("dirty_navcell_revision"))])


func _compare_center_world_samples() -> void:
	for y in range(0, _gd_map.height, 7):
		for x in range(0, _gd_map.width, 7):
			var coord := Vector2i(x, y)
			var gd_center := _gd_map.navcell_center_world(coord)
			var n_center: Vector2 = _nmap.call("navcell_center_world", coord)
			if gd_center != n_center:
				_failures.append("navcell_center_world differs at %s (gd=%s native=%s)" % [coord, gd_center, n_center])
				return
			var world := gd_center + Vector2(1.7, -2.3)
			if _gd_map.world_to_navcell(world) != Vector2i(_nmap.call("world_to_navcell", world)):
				_failures.append("world_to_navcell differs at %s" % world)
				return


func _compare_tables(label: String, gd_cache: SimNavJumpPointCache, n_cache: Object) -> void:
	var map_w := _gd_map.width
	var pairs := [
		["baked", gd_cache._baked, n_cache.call("baked_grid")],
		["east", gd_cache._ray_east, n_cache.call("ray_table_east")],
		["west", gd_cache._ray_west, n_cache.call("ray_table_west")],
		["south", gd_cache._ray_south, n_cache.call("ray_table_south")],
		["north", gd_cache._ray_north, n_cache.call("ray_table_north")],
	]
	for pair in pairs:
		var table_name := str(pair[0])
		var gd_table := pair[1] as PackedInt32Array
		var n_table := pair[2] as PackedInt32Array
		if gd_table != n_table:
			var diff := _first_diff(gd_table, n_table)
			@warning_ignore("integer_division")
			var diff_y: int = diff / map_w
			_failures.append("%s: %s table differs (first diff idx=%d cell=(%d,%d) gd=%d native=%d, total=%d)" % [
				label, table_name, diff, diff % map_w, diff_y, gd_table[diff], n_table[diff], _count_diffs(gd_table, n_table)])


func _sweep_jump_points(label: String, gd_cache: SimNavJumpPointCache, n_cache: Object, stride: int) -> void:
	var goal_cell := Vector2i(_gd_map.width - 15, _gd_map.height - 13)
	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var checked := 0
	for y in range(0, _gd_map.height, stride):
		for x in range(0, _gd_map.width, stride):
			var start := Vector2i(x, y)
			if not _gd_map.is_passable_navcell(start, _ground_mask):
				continue
			for direction in directions:
				var gd_jump := gd_cache.jump_point(start, direction, goal_cell)
				var n_jump := Vector2i(n_cache.call("jump_point", start, direction, goal_cell))
				checked += 1
				if gd_jump != n_jump:
					_failures.append("%s: jump_point differs at %s dir %s (gd=%s native=%s)" % [label, start, direction, gd_jump, n_jump])
					return
	print("[m2-ab] %s: %d jump_point probes identical" % [label, checked])


func _sweep_lines(label: String, gd_cache: SimNavJumpPointCache, n_cache: Object, segment_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260702
	var world_min := _gd_map.origin - Vector2(40.0, 40.0)
	var world_max := _gd_map.origin + Vector2(_gd_map.width, _gd_map.height) * _gd_map.navcell_size + Vector2(40.0, 40.0)
	var move_mismatch := 0
	var seg_mismatch := 0
	for i in range(segment_count):
		var a := Vector2(rng.randf_range(world_min.x, world_max.x), rng.randf_range(world_min.y, world_max.y))
		var b := Vector2(rng.randf_range(world_min.x, world_max.x), rng.randf_range(world_min.y, world_max.y))
		if i % 5 == 0:
			b.y = a.y  # axis-aligned batch
		if i % 17 == 0:
			b = a  # degenerate same-point
		if gd_cache.movement_line_clear(a, b) != bool(n_cache.call("movement_line_clear", a, b)):
			move_mismatch += 1
		if gd_cache.segment_clear(a, b) != bool(n_cache.call("segment_clear", a, b)):
			seg_mismatch += 1
	if move_mismatch > 0:
		_failures.append("%s: movement_line_clear mismatches: %d / %d" % [label, move_mismatch, segment_count])
	if seg_mismatch > 0:
		_failures.append("%s: segment_clear mismatches: %d / %d" % [label, seg_mismatch, segment_count])
	if move_mismatch == 0 and seg_mismatch == 0:
		print("[m2-ab] %s: %d segment probes identical" % [label, segment_count])


# ── Small helpers ────────────────────────────────────────────────────────────

func _unpack_cells(packed: PackedInt32Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	@warning_ignore("integer_division")
	var count: int = packed.size() / 2
	for i in range(count):
		cells.append(Vector2i(packed[i * 2], packed[i * 2 + 1]))
	return cells


func _first_diff(a: PackedInt32Array, b: PackedInt32Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i in range(a.size()):
		if a[i] != b[i]:
			return i
	return -1


func _count_diffs(a: PackedInt32Array, b: PackedInt32Array) -> int:
	var count := 0
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			count += 1
	return count
