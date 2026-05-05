extends Node


const LAB_SCENE_PATH: String = "res://addons/logic-game-framework/example/rts-pathfinding-lab/frontend/rts_pathfinding_lab.tscn"

var _frames: int = 0
var _scene: Node = null


func _ready() -> void:
	var packed: PackedScene = load(LAB_SCENE_PATH) as PackedScene
	if packed == null:
		print("SMOKE_TEST_RESULT: FAIL - failed to load lab scene")
		get_tree().quit(1)
		return
	_scene = packed.instantiate()
	if _scene == null:
		print("SMOKE_TEST_RESULT: FAIL - failed to instantiate lab scene")
		get_tree().quit(1)
		return
	add_child(_scene)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2:
		var click_pos := Vector2(74.0, 162.0)
		_scene.set("_drag_start", click_pos)
		_scene.call("_finish_selection", click_pos)
		var selected: Array = _scene.get("_selected_unit_ids") as Array
		if selected.size() != 1 or selected[0] != "blue_0":
			print("SMOKE_TEST_RESULT: FAIL - click selection expected [blue_0], got %s" % str(selected))
			get_tree().quit(1)
			return
	if _frames >= 8:
		print("SMOKE_TEST_RESULT: PASS - rts_pathfinding_lab scene loads and ticks")
		get_tree().quit(0)
