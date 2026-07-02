extends Node

# Equality weld for the boolean movement-line fast path:
# facade.movement_line_clear(...) must equal
# validate_movement_line(...).is_success() for every segment — the two share
# the shape stage but keep hand-locked twin raster walks, so this smoke is
# what stops them drifting. Covers out-of-bounds endpoints, impassable
# starts (escape rule), grid-line tie endpoints, pass_mask == 0, filter
# variants, queries after an incremental dirty repair, and a facade wired
# without a long pathfinder (slow-raster fallback branch).


var _failures: Array[String] = []
var _checked := 0


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - sim-nav-map movement line fast path (%d segments)" % _checked)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures.slice(0, 5)))
	get_tree().quit(1)


func _run() -> void:
	var nav_map := SimNavMap.new(60, 40, 8.0, Vector2.ZERO, 4)
	var ground := SimNavPassabilityClassConfig.new()
	ground.class_name_id = "ground"
	ground.clearance = 6.0
	ground.affects_pathfinding = true
	var mask := nav_map.register_passability_class(ground)
	# Static obstruction shapes (exercise the exact-geometry stage) plus raw
	# navcell walls (exercise the raster stage alone).
	var block := SimNavObstructionShapeStatic.new()
	block.entity_id = "block_a"
	block.center = Vector2(200.0, 160.0)
	block.width = 48.0
	block.height = 32.0
	block.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
	nav_map.add_static_obstruction(block)
	for y in range(10, 30):
		nav_map.or_navcell_data(Vector2i(40, y), mask)
	nav_map.rebuild_dirty()
	nav_map.clear_dirty_navcells()

	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	long_pathfinder.prewarm_jump_point_cache(mask)
	var facade := SimNavPathfinderFacade.new(nav_map, null, long_pathfinder)
	var bare_facade := SimNavPathfinderFacade.new(nav_map, null, null)

	var static_only := SimNavObstructionFilter.all()
	static_only.include_units = false
	var no_statics := SimNavObstructionFilter.all()
	no_statics.include_static = false
	var filters: Array = [null, static_only, no_statics]

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260702
	for i in range(300):
		var a := Vector2(rng.randf_range(-24.0, 500.0), rng.randf_range(-24.0, 340.0))
		var b := Vector2(rng.randf_range(-24.0, 500.0), rng.randf_range(-24.0, 340.0))
		_check(facade, a, b, 6.0, mask, filters[i % filters.size()], "random")

	# Escape rule: starts on impassable navcells (inside the wall column and
	# the static's clearance band), walking out and walking deeper.
	var wall_start := Vector2(324.0, 120.0)
	_check(facade, wall_start, Vector2(420.0, 120.0), 6.0, mask, static_only, "escape out")
	_check(facade, wall_start, Vector2(324.0, 12.0), 6.0, mask, static_only, "escape along")
	_check(facade, Vector2(200.0, 160.0), Vector2(60.0, 60.0), 6.0, mask, static_only, "escape from static")
	_check(facade, wall_start, wall_start + Vector2(1.0, 0.0), 6.0, mask, static_only, "impassable same cell")

	# Grid-line tie endpoints and axis-aligned segments.
	_check(facade, Vector2(96.0, 96.0), Vector2(96.0, 240.0), 6.0, mask, static_only, "grid line vertical")
	_check(facade, Vector2(64.0, 128.0), Vector2(400.0, 128.0), 6.0, mask, static_only, "axis horizontal")
	_check(facade, Vector2(80.0, 80.0), Vector2(80.0, 80.0), 6.0, mask, static_only, "zero length")

	# pass_mask == 0 skips the raster stage in both paths.
	_check(facade, Vector2(60.0, 60.0), Vector2(300.0, 300.0), 6.0, 0, static_only, "mask zero")

	# Slow-raster fallback branch: facade without a long pathfinder.
	for i in range(60):
		var a := Vector2(rng.randf_range(-24.0, 500.0), rng.randf_range(-24.0, 340.0))
		var b := Vector2(rng.randf_range(-24.0, 500.0), rng.randf_range(-24.0, 340.0))
		_check(bare_facade, a, b, 6.0, mask, static_only, "no-long fallback")

	# Dynamic terrain change: repair through the facade flush, then re-verify.
	for x in range(10, 26):
		nav_map.or_navcell_data(Vector2i(x, 20), mask)
	facade.recompute_dirty([mask])
	for i in range(100):
		var a := Vector2(rng.randf_range(-24.0, 500.0), rng.randf_range(-24.0, 340.0))
		var b := Vector2(rng.randf_range(-24.0, 500.0), rng.randf_range(-24.0, 340.0))
		_check(facade, a, b, 6.0, mask, filters[i % filters.size()], "post repair")


func _check(
	facade: SimNavPathfinderFacade,
	a: Vector2,
	b: Vector2,
	clearance: float,
	mask: int,
	filter: SimNavObstructionFilter,
	label: String
) -> void:
	_checked += 1
	var fast := facade.movement_line_clear(a, b, clearance, mask, filter)
	var slow := facade.validate_movement_line(a, b, clearance, mask, filter).is_success()
	if fast != slow:
		_failures.append("%s: %s -> %s fast=%s slow=%s" % [label, a, b, fast, slow])
