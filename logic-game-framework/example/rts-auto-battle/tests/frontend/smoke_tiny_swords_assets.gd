extends Node


const SHOWCASE_SCENE_PATH: String = "res://addons/logic-game-framework/example/rts-auto-battle/frontend/asset_showcase/rts_tiny_swords_showcase.tscn"


func _ready() -> void:
	var scene: PackedScene = load(SHOWCASE_SCENE_PATH) as PackedScene
	if scene == null:
		_fail("showcase scene failed to load")
		return

	var showcase := scene.instantiate()
	add_child(showcase)
	await get_tree().process_frame

	if not _expect_node(showcase, "Units/BlueWorker", "AnimatedSprite2D"):
		return
	if not _expect_node(showcase, "Units/RedMelee", "AnimatedSprite2D"):
		return
	if not _expect_node(showcase, "Units/BlueMeleeAttack", "AnimatedSprite2D"):
		return
	if not _expect_node(showcase, "Buildings/BlueCastle", "Sprite2D"):
		return
	if not _expect_node(showcase, "Buildings/RedHouse", "Sprite2D"):
		return
	if not _expect_node(showcase, "Resources/GoldResource", "Sprite2D"):
		return

	var worker := showcase.get_node("Units/BlueWorker") as AnimatedSprite2D
	if worker.sprite_frames == null or not worker.sprite_frames.has_animation("run"):
		_fail("worker run animation missing")
		return
	if worker.sprite_frames.get_frame_count("run") <= 0:
		_fail("worker run animation has no frames")
		return

	var attack := showcase.get_node("Units/BlueMeleeAttack") as AnimatedSprite2D
	if attack.sprite_frames == null or not attack.sprite_frames.has_animation("attack"):
		_fail("melee attack animation missing")
		return

	print("SMOKE_TEST_RESULT: PASS - tiny swords asset showcase loaded")
	get_tree().quit(0)


func _expect_node(root: Node, path: NodePath, expected_class: String) -> bool:
	var node := root.get_node_or_null(path)
	if node == null:
		_fail("missing node: %s" % str(path))
		return false
	if not node.is_class(expected_class):
		_fail("node has wrong type: %s" % str(path))
		return false
	return true


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
