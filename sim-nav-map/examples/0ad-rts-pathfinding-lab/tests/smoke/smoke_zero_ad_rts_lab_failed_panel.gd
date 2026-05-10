extends Node

# Asserts the lab demo HUD panel surfaces "failed" units (move_failed=true)
# so a player can tell which units gave up. Pure panel-text contract;
# visuals (red ring + ✕ glyph) are inspected by hand in the editor.


const LAB_SCENE_PATH: String = "res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/frontend/zero_ad_rts_pathfinding_lab.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	if _failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - lab demo failed-units panel surfacing")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SMOKE_TEST_RESULT: FAIL - " + "; ".join(_failures))
	get_tree().quit(1)


func _run() -> void:
	var packed_scene: PackedScene = load(LAB_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_failures.append("failed to load lab scene")
		return
	var instance := packed_scene.instantiate()
	if instance == null:
		_failures.append("failed to instantiate lab scene")
		return
	add_child(instance)
	await get_tree().process_frame

	var world: ZeroAdRtsLabWorld = instance._world as ZeroAdRtsLabWorld
	var hud: Label = instance._hud as Label
	if world == null or hud == null:
		_failures.append("lab scene did not init _world / _hud")
		instance.queue_free()
		return

	# Baseline: no unit has failed; line should be absent.
	for unit in world.units:
		unit.move_failed = false
	instance._update_hud()
	if hud.text.find("failed (") != -1:
		_failures.append("baseline: panel showed 'failed' line with no failed units: '%s'" % hud.text)

	# 1 failed unit: line shows "failed (1): blue_2".
	var first_unit: ZeroAdRtsLabUnit = world.units[0]
	first_unit.move_failed = true
	instance._update_hud()
	var expected_one := "failed (1): %s" % first_unit.id
	if hud.text.find(expected_one) == -1:
		_failures.append("1-failed: panel missing '%s' (got: '%s')" % [expected_one, hud.text])

	# >5 failed: list truncated to first 5 + " +N more".
	for unit in world.units:
		unit.move_failed = unit.mobile  # mark every mobile unit as failed
	var failed_count := 0
	for unit in world.units:
		if unit.move_failed:
			failed_count += 1
	instance._update_hud()
	if failed_count > 5:
		var expected_count := "failed (%d):" % failed_count
		if hud.text.find(expected_count) == -1:
			_failures.append("many-failed: panel missing '%s' (got: '%s')" % [expected_count, hud.text])
		var expected_more := "+%d more" % (failed_count - 5)
		if hud.text.find(expected_more) == -1:
			_failures.append("many-failed: panel missing truncation suffix '%s' (got: '%s')" % [expected_more, hud.text])

	instance.queue_free()
