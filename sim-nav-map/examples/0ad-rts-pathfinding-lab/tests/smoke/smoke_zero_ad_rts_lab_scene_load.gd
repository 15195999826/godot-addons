extends Node


func _ready() -> void:
	var packed_scene: PackedScene = load("res://addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/frontend/zero_ad_rts_pathfinding_lab.tscn") as PackedScene
	if packed_scene == null:
		_fail("scene-load: failed to load packed scene")
		return
	var instance := packed_scene.instantiate()
	if instance == null:
		_fail("scene-load: failed to instantiate packed scene")
		return
	add_child(instance)
	await get_tree().process_frame
	if not instance.has_method("_draw"):
		_fail("scene-load: frontend script missing draw method")
		return
	var world: ZeroAdRtsLabWorld = instance.get("_world") as ZeroAdRtsLabWorld
	if world == null:
		_fail("scene-load: frontend world missing")
		return
	if int(world.get_metrics().get("active_count", 0)) <= 0:
		_fail("scene-load: startup should issue the default group move")
		return
	var queued := int(world.get_metrics().get("long_path_requests", 0))
	if queued <= 0:
		_fail("scene-load: startup default move should enqueue long paths")
		return
	print("SMOKE_TEST_RESULT: PASS - 0ad rts lab scene load")
	get_tree().quit(0)


func _fail(message: String) -> void:
	var output := "SMOKE_TEST_RESULT: FAIL - %s" % message
	printerr(output)
	print(output)
	get_tree().quit(1)
