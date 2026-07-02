extends Node

# M4 trajectory weld: Dota2LabMotionEngine with use_native_solver must
# reproduce the GDScript Phase A/B math bit-for-bit over long runs — unit
# positions, facing, steer-side locks, speed factors, order states and
# terminal events, on BOTH pair-pass paths (brute-force <=16 and hashed).
# Both sides run GDScript wrappers/planning (already welded in M3) so the
# only variable is the solver. Also prints the 100-unit tick perf numbers.

const TICK_DELTA := 1.0 / 30.0

var _failures: Array[String] = []


func _ready() -> void:
	_run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - native motion solver trajectories bit-identical")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - %s" % "; ".join(_failures.slice(0, 5)))
	get_tree().quit(1)


func _run() -> void:
	if not ClassDB.class_exists("SimNavNativeMotionSolver"):
		_failures.append("SimNavNativeMotionSolver missing (build native/ first)")
		return
	_run_pair("brute<=16", _brute_spec(), 600)
	if not _failures.is_empty():
		return
	_run_pair("hashed x40", _hashed_spec(), 600)
	if not _failures.is_empty():
		return
	# Threshold boundary: exactly 16 stays brute, 17 flips to hashed.
	_run_pair("brute=16", _threshold_spec(16), 200)
	_run_pair("hashed=17", _threshold_spec(17), 200)
	# Steering disabled is its own Phase A code path.
	_run_pair("steering-off", _brute_spec(), 200, false)
	# All idle + zero units must not crash and must stay identical.
	_run_pair("idle", _brute_spec(), 30)
	_run_pair("empty", [], 3)
	if not _failures.is_empty():
		return
	_perf_phase()


# ── Fixtures ─────────────────────────────────────────────────────────────────

func _obstacles() -> Array[Dota2LabObstacle]:
	var result: Array[Dota2LabObstacle] = [
		Dota2LabObstacle.new("wall-a", Vector2(500, 350), Vector2(140, 60)),
		Dota2LabObstacle.new("wall-b", Vector2(800, 550), Vector2(70, 220)),
		Dota2LabObstacle.new("wall-c", Vector2(320, 640), Vector2(180, 40)),
		# Rotated OBB: exercises the _rotated() projection path in the solve.
		Dota2LabObstacle.new("wall-r", Vector2(1050, 380), Vector2(120, 46), 0.5),
	]
	return result


# spec: Array of [id, pos, radius, speed, mobile]
func _brute_spec() -> Array:
	var spec: Array = []
	for i in range(10):
		spec.append(["u%02d" % i, Vector2(100 + (i % 5) * 34, 200 + (i / 5) * 40), 12.0, 90.0, true])
	spec.append(["blk-a", Vector2(640, 430), 16.0, 0.0, false])
	spec.append(["blk-b", Vector2(660, 470), 16.0, 0.0, false])
	# Perfectly coincident centers: exercises the id-order tie-break split.
	spec.append(["twin-a", Vector2(900, 620), 11.0, 92.0, true])
	spec.append(["twin-b", Vector2(900, 620), 11.0, 92.0, true])
	return spec


func _threshold_spec(count: int) -> Array:
	var spec: Array = []
	for i in range(count):
		spec.append(["t%02d" % i, Vector2(140 + (i % 8) * 30, 260 + (i / 8) * 34), 11.0, 90.0, true])
	return spec


func _hashed_spec() -> Array:
	var spec: Array = []
	for i in range(20):
		spec.append(["east%02d" % i, Vector2(120 + (i % 4) * 30, 300 + (i / 4) * 30), 10.0 + (i % 3), 85.0 + (i % 5) * 3.0, true])
	for i in range(20):
		spec.append(["west%02d" % i, Vector2(1180 - (i % 4) * 30, 320 + (i / 4) * 30), 10.0 + (i % 2) * 2.0, 88.0 + (i % 4) * 2.0, true])
	return spec


func _make_units(spec: Array) -> Array[Dota2LabUnit]:
	var units: Array[Dota2LabUnit] = []
	for entry in spec:
		units.append(Dota2LabUnit.new(entry[0], "", entry[1], entry[2], entry[3], entry[4]))
	return units


func _orders_for(label: String, units: Array[Dota2LabUnit]) -> Array:
	# [tick, unit_index, goal] — mirrored command streams on both sides.
	var orders: Array = []
	if label == "idle" or label == "empty":
		return orders
	if label.begins_with("brute") or label == "steering-off":
		for i in range(mini(10, units.size())):
			orders.append([0, i, Vector2(1150, 250 + i * 45)])
		for i in range(mini(5, units.size())):
			orders.append([150, i, Vector2(200, 700 - i * 30)])
		if units.size() > 7:
			orders.append([300, 7, Vector2(120, 160)])
		# Twins drive to the same goal so they contend all the way.
		for i in range(units.size()):
			if units[i].id.begins_with("twin"):
				orders.append([0, i, Vector2(1050, 620)])
		if label.begins_with("brute="):
			for i in range(units.size()):
				orders.append([0, i, Vector2(1200 - (i % 8) * 30, 640 - (i / 8) * 30)])
	elif label.begins_with("hashed=") :
		for i in range(units.size()):
			orders.append([0, i, Vector2(1200 - (i % 8) * 30, 640 - (i / 8) * 30)])
	else:
		for i in range(units.size()):
			var goal := Vector2(1180, 300 + (i % 20) * 28) if units[i].id.begins_with("east") else Vector2(140, 320 + (i % 20) * 28)
			orders.append([0, i, goal])
		for i in range(0, units.size(), 3):
			orders.append([200, i, Vector2(660, 200 + (i * 13) % 500)])
	return orders


# ── A/B run ──────────────────────────────────────────────────────────────────

func _run_pair(label: String, spec: Array, ticks: int, steering_enabled: bool = true) -> void:
	var gd_wrapper := Dota2LabPathfinderWrapper.new()
	gd_wrapper.rebuild_context(_obstacles())
	var gd_engine := Dota2LabMotionEngine.new()
	gd_engine.contact_steering_enabled = steering_enabled
	var gd_units := _make_units(spec)

	var n_wrapper := Dota2LabPathfinderWrapper.new()
	n_wrapper.rebuild_context(_obstacles())
	var n_engine := Dota2LabMotionEngine.new()
	n_engine.use_native_solver = true
	n_engine.contact_steering_enabled = steering_enabled
	var n_units := _make_units(spec)

	var gd_orders := _orders_for(label, gd_units)
	var n_orders := _orders_for(label, n_units)

	for tick in range(ticks):
		for order in gd_orders:
			if int(order[0]) == tick:
				gd_engine.issue_move(gd_units[int(order[1])], order[2], gd_wrapper, tick)
		for order in n_orders:
			if int(order[0]) == tick:
				n_engine.issue_move(n_units[int(order[1])], order[2], n_wrapper, tick)
		var gd_events := gd_engine.step(gd_units, gd_wrapper, TICK_DELTA, tick)
		var n_events := n_engine.step(n_units, n_wrapper, TICK_DELTA, tick)
		if not _compare_tick(label, tick, gd_units, n_units, gd_events, n_events):
			return
	# Terminal sanity: identical order outcomes on both sides.
	for i in range(gd_units.size()):
		var gd_snapshot := gd_units[i].last_order_snapshot()
		var n_snapshot := n_units[i].last_order_snapshot()
		if gd_snapshot.get("status") != n_snapshot.get("status") or gd_snapshot.get("reason") != n_snapshot.get("reason"):
			_failures.append("%s: unit %d last-order outcome differs (gd=%s/%s native=%s/%s)" % [
				label, i, gd_snapshot.get("status"), gd_snapshot.get("reason"), n_snapshot.get("status"), n_snapshot.get("reason")])
			return
	print("[m4-ab] %s: %d ticks bit-identical (%d units)" % [label, ticks, gd_units.size()])


func _compare_tick(label: String, tick: int, gd_units: Array[Dota2LabUnit], n_units: Array[Dota2LabUnit], gd_events: Array[Dictionary], n_events: Array[Dictionary]) -> bool:
	for i in range(gd_units.size()):
		var gd_unit := gd_units[i]
		var n_unit := n_units[i]
		if gd_unit.position != n_unit.position:
			_failures.append("%s tick %d unit %d (%s): position diverged gd=%s native=%s (delta=%s)" % [
				label, tick, i, gd_unit.id, gd_unit.position, n_unit.position, gd_unit.position - n_unit.position])
			return false
		if gd_unit.facing_angle_rad != n_unit.facing_angle_rad:
			_failures.append("%s tick %d unit %d: facing diverged gd=%.17f native=%.17f" % [label, tick, i, gd_unit.facing_angle_rad, n_unit.facing_angle_rad])
			return false
		if gd_unit.steer_side != n_unit.steer_side:
			_failures.append("%s tick %d unit %d: steer_side diverged gd=%s native=%s" % [label, tick, i, gd_unit.steer_side, n_unit.steer_side])
			return false
		if gd_unit.last_speed_factor != n_unit.last_speed_factor or gd_unit.last_turn_delta_rad != n_unit.last_turn_delta_rad:
			_failures.append("%s tick %d unit %d: speed factor / turn delta diverged" % [label, tick, i])
			return false
		if gd_unit.state != n_unit.state or gd_unit.pending_plan_ticket != n_unit.pending_plan_ticket:
			_failures.append("%s tick %d unit %d: state/ticket diverged (gd=%s/%d native=%s/%d)" % [
				label, tick, i, gd_unit.state, gd_unit.pending_plan_ticket, n_unit.state, n_unit.pending_plan_ticket])
			return false
	if gd_events.size() != n_events.size():
		_failures.append("%s tick %d: event count differs (gd=%d native=%d)" % [label, tick, gd_events.size(), n_events.size()])
		return false
	for e in range(gd_events.size()):
		if gd_events[e].get("kind") != n_events[e].get("kind") or gd_events[e].get("unit_id") != n_events[e].get("unit_id") \
				or gd_events[e].get("reason") != n_events[e].get("reason"):
			_failures.append("%s tick %d: event %d differs (gd=%s native=%s)" % [label, tick, e, gd_events[e], n_events[e]])
			return false
	return true


# ── Perf (printed, not asserted) ─────────────────────────────────────────────

func _perf_phase() -> void:
	var spec: Array = []
	for i in range(100):
		spec.append(["p%03d" % i, Vector2(80 + (i % 10) * 26, 120 + (i / 10) * 26), 10.0, 90.0, true])

	# Three configs: pure GDScript, native solver only (GDScript wrapper), and
	# the full native backend (wrapper + solver) — the last one is the
	# capability-envelope configuration.
	var timings: Array[float] = []
	for config in [[false, false], [false, true], [true, true]]:
		var wrapper := Dota2LabPathfinderWrapper.new()
		wrapper.use_native = config[0]
		wrapper.rebuild_context(_obstacles())
		var engine := Dota2LabMotionEngine.new()
		engine.use_native_solver = config[1]
		var units := _make_units(spec)
		for i in range(units.size()):
			engine.issue_move(units[i], Vector2(1240 - (i % 10) * 26, 780 - (i / 10) * 22), wrapper, 0)
		# Warm-up ticks let plans land and the march spread out (steady state).
		for tick in range(30):
			engine.step(units, wrapper, TICK_DELTA, tick)
		var start_usec := Time.get_ticks_usec()
		for tick in range(30, 330):
			engine.step(units, wrapper, TICK_DELTA, tick)
		timings.append((Time.get_ticks_usec() - start_usec) / 300.0 / 1000.0)
	print("[m4-perf] 100-unit dispersed march tick: gd %.3f ms | native solver %.3f ms | full native %.3f ms | %.1fx end-to-end" % [
		timings[0], timings[1], timings[2], timings[0] / maxf(0.0001, timings[2])])
