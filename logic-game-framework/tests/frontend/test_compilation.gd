## 编译测试脚本 - 验证所有类都能正确加载
extends Node

func _ready() -> void:
	print("\n========== Compilation Test ==========\n")
	
	# 测试 1: GridLayout
	print("Test 1: GridLayout...")
	var layout: GridLayout = GridLayout.new()
	var pixel_pos: Vector2 = layout.coord_to_pixel(Vector2i(0, 0))
	var coord: Vector2i = layout.pixel_to_coord(pixel_pos)
	print("  ✓ GridLayout works")
	
	# 测试 2: VisualizerRegistry
	print("Test 2: FrontendVisualizerRegistry...")
	var registry: FrontendVisualizerRegistry = FrontendVisualizerRegistry.new()
	print("  ✓ VisualizerRegistry works")
	
	# 测试 3: DefaultRegistry
	print("Test 3: FrontendDefaultRegistry...")
	var default_registry: FrontendVisualizerRegistry = FrontendDefaultRegistry.create()
	print("  ✓ DefaultRegistry works")
	
	# 测试 4: ActionScheduler
	print("Test 4: FrontendActionScheduler...")
	var scheduler: FrontendActionScheduler = FrontendActionScheduler.new()
	print("  ✓ ActionScheduler works")
	
	# 测试 5: RenderWorld
	print("Test 5: FrontendRenderWorld...")
	var world: FrontendRenderWorld = FrontendRenderWorld.new()
	print("  ✓ RenderWorld works")
	
	# 测试 6: BattleDirector
	print("Test 6: FrontendBattleDirector...")
	var director: FrontendBattleDirector = FrontendBattleDirector.new()
	print("  ✓ BattleDirector works")
	
	# 测试 7: BattleReplayScene
	print("Test 7: FrontendBattleReplayScene...")
	var scene: FrontendBattleReplayScene = FrontendBattleReplayScene.new()
	print("  ✓ BattleReplayScene works")
	
	# 测试 8: ReplayControls
	print("Test 8: FrontendReplayControls...")
	var controls: FrontendReplayControls = FrontendReplayControls.new()
	print("  ✓ ReplayControls works")
	
	print("\n========== All Tests Passed! ==========\n")
	get_tree().quit()
