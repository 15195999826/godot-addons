extends Node

# Budget weld for the capability-envelope performance promises
# (sim-nav-map/docs/capability-envelope.md). Wall-clock thresholds sit at
# roughly 2-3x the dev-machine measurements — they are regression tripwires
# for asymptotic slips (a lost fast path or a reborn O(N^2) blows through
# them instantly), not exact promise replays; structural assertions carry
# the rest.
#
# Envelope promise          measured    tripwire here
#   cross-map plan  < 1ms     ~0.8ms      3ms avg over 16 distinct starts
#   first plan after rebuild  ~0.9ms      3ms   (prewarm regression -> ~11ms)
#   terrain flush   < 5ms     ~3.5ms      10ms  (add + expiry, repair path)
#   100-unit tick   < 5ms     ~3.8ms      10ms avg spread march
#                                               (O(N^2) regression -> ~20ms)


const PLAN_TRIPWIRE_USEC := 3000
const FLUSH_TRIPWIRE_USEC := 10000
const TICK_100_TRIPWIRE_USEC := 10000

var _failures: Array[String] = []


func _ready() -> void:
	_test_plan_cost_and_prewarm()
	_test_terrain_flush_budget_and_repair_path()
	_test_100_unit_tick_budget()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - dota2 lab perf budget")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures))
	get_tree().quit(1)


func _test_plan_cost_and_prewarm() -> void:
	var world := Dota2LabWorld.new()
	var pf := world.pathfinder

	# Prewarm contract: the very first plan after a rebuild runs at warm cost
	# (bake + tables were paid inside rebuild_context).
	var t_first := Time.get_ticks_usec()
	var first := pf.plan_path(Vector2(120.0, 400.0), Vector2(1160.0, 450.0))
	var first_usec := int(Time.get_ticks_usec() - t_first)
	if first.status != "success":
		_failures.append("plan: first plan failed (%s)" % first.status)
	if first_usec > PLAN_TRIPWIRE_USEC:
		_failures.append("plan: first plan after rebuild %d usec > %d (prewarm regressed?)" % [
			first_usec, PLAN_TRIPWIRE_USEC])

	# Warm cross-map planning, 16 distinct starts (repeated-identical queries
	# would read fake-fast).
	var total := 0
	for ix in range(4):
		for iy in range(4):
			var start := Vector2(100.0 + 50.0 * ix, 370.0 + 50.0 * iy)
			var t0 := Time.get_ticks_usec()
			var result := pf.plan_path(start, Vector2(1160.0, 450.0))
			total += int(Time.get_ticks_usec() - t0)
			if result.status != "success":
				_failures.append("plan: warm plan from %s failed (%s)" % [start, result.status])
	var avg := total / 16
	if avg > PLAN_TRIPWIRE_USEC:
		_failures.append("plan: warm cross-map avg %d usec > %d" % [avg, PLAN_TRIPWIRE_USEC])


func _test_terrain_flush_budget_and_repair_path() -> void:
	var world := Dota2LabWorld.new()
	var pf := world.pathfinder
	pf.plan_path(Vector2(120.0, 400.0), Vector2(1160.0, 450.0))
	var cache: SimNavJumpPointCache = pf.long_pathfinder._jump_point_cache(pf.pass_mask)
	var repairs_before := cache.repair_count

	# Fissure lands: dirty flush must take the incremental repair path and
	# stay inside the budget; expiry pays the same.
	for i in range(16):
		pf.nav_map.or_navcell_data(Vector2i(60 + i, 40 + (i >> 2)), pf.pass_mask)
	var t0 := Time.get_ticks_usec()
	pf.facade.recompute_dirty([pf.pass_mask])
	var add_usec := int(Time.get_ticks_usec() - t0)
	for i in range(16):
		pf.nav_map.and_navcell_data(Vector2i(60 + i, 40 + (i >> 2)), pf.pass_mask)
	var t1 := Time.get_ticks_usec()
	pf.facade.recompute_dirty([pf.pass_mask])
	var expire_usec := int(Time.get_ticks_usec() - t1)

	if add_usec > FLUSH_TRIPWIRE_USEC:
		_failures.append("flush: wall add %d usec > %d" % [add_usec, FLUSH_TRIPWIRE_USEC])
	if expire_usec > FLUSH_TRIPWIRE_USEC:
		_failures.append("flush: wall expiry %d usec > %d" % [expire_usec, FLUSH_TRIPWIRE_USEC])
	if cache.repair_count != repairs_before + 2:
		_failures.append("flush: expected 2 incremental repairs, cache did %d (full reset fallback?)" % [
			cache.repair_count - repairs_before])
	var after := pf.plan_path(Vector2(120.0, 400.0), Vector2(1160.0, 450.0))
	if after.status != "success":
		_failures.append("flush: post-expiry plan failed (%s)" % after.status)


func _test_100_unit_tick_budget() -> void:
	var world := Dota2LabWorld.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in range(92):
		var col := i % 12
		@warning_ignore("integer_division")
		var row: int = i / 12
		world.units.append(Dota2LabUnit.new(
			"extra_%d" % i, "mid",
			Vector2(
				80.0 + 30.0 * col + rng.randf_range(-5.0, 5.0),
				200.0 + 30.0 * row + rng.randf_range(-5.0, 5.0)
			),
			11.0, 110.0, true
		))
	var delta := 1.0 / 60.0
	var goals: Array[Vector2] = [
		Vector2(1160.0, 160.0), Vector2(1160.0, 740.0),
		Vector2(660.0, 120.0), Vector2(660.0, 800.0),
	]
	var ids := world.get_mobile_unit_ids()
	for group in range(4):
		var group_ids: Array[String] = []
		for k in range(ids.size()):
			if k % 4 == group:
				group_ids.append(ids[k])
		world.issue_move_ids(group_ids, goals[group])
	# Let the plan queue drain and the march settle into steady state.
	for i in range(110):
		world.step(delta)
	var total := 0
	for i in range(120):
		var t0 := Time.get_ticks_usec()
		world.step(delta)
		total += int(Time.get_ticks_usec() - t0)
	var avg := total / 120
	if avg > TICK_100_TRIPWIRE_USEC:
		_failures.append("100 units: spread-march tick avg %d usec > %d" % [avg, TICK_100_TRIPWIRE_USEC])
