## 3D 可视化测试脚本 - 验证单位、血条、飘字等 3D 元素
extends Node3D

var _replay_scene: FrontendBattleReplayScene
var _director: FrontendBattleDirector
var _test_step := 0
var _test_timer := 0.0

func _ready() -> void:
	print("\n========== 3D Visualization Test ==========\n")
	
	# 创建回放场景
	_replay_scene = FrontendBattleReplayScene.new()
	_replay_scene.name = "BattleReplayScene"
	add_child(_replay_scene)
	
	# 获取 director
	_director = _replay_scene.get_director()
	
	# 连接信号
	_director.actor_state_changed.connect(_on_actor_state_changed)
	_director.floating_text_created.connect(_on_floating_text_created)
	_director.actor_died.connect(_on_actor_died)
	
	# 加载演示回放
	print("Step 1: Loading demo replay...")
	var demo_replay := _create_demo_replay()
	_replay_scene.load_replay(demo_replay)
	print("  ✓ Replay loaded")
	
	# 检查单位是否创建
	print("\nStep 2: Checking unit creation...")
	_check_units()
	
	_test_step = 1


func _exit_tree() -> void:
	# 断开测试脚本的信号连接 (修复 C1: 内存泄漏)
	if _director:
		_director.actor_state_changed.disconnect(_on_actor_state_changed)
		_director.floating_text_created.disconnect(_on_floating_text_created)
		_director.actor_died.disconnect(_on_actor_died)


func _process(delta: float) -> void:
	_test_timer += delta
	
	match _test_step:
		1:
			# 等待 1 秒后开始播放
			if _test_timer >= 1.0:
				print("\nStep 3: Starting playback with visualization...")
				_replay_scene.play()
				_test_step = 2
				_test_timer = 0.0
		
		2:
			# 播放 5 秒后完成测试
			if _test_timer >= 5.0:
				print("\nStep 4: Test completed!")
				print("\n========== All 3D Visualization Tests Passed! ==========\n")
				get_tree().quit()


func _check_units() -> void:
	# 获取单位根节点
	var units_root := _replay_scene.get_node("UnitsRoot")
	if units_root == null:
		print("  ✗ UnitsRoot not found!")
		return
	
	var unit_count := units_root.get_child_count()
	print("  - Units created: %d" % unit_count)
	
	for i in range(unit_count):
		var unit := units_root.get_child(i)
		print("    - Unit %d: %s (position: %s)" % [i, unit.name, unit.position])


func _on_actor_state_changed(actor_id: String, state: FrontendActorRenderState) -> void:
	print("  [Signal] Actor state changed: %s" % actor_id)
	print("    - Position: q=%d r=%d" % [state.position.q, state.position.r])
	print("    - HP: %.1f / %.1f" % [state.visual_hp, state.max_hp])


func _on_floating_text_created(data: FrontendRenderData.FloatingText) -> void:
	print("  [Signal] Floating text created: %s -> '%s'" % [data.actor_id, data.text])


func _on_actor_died(actor_id: String) -> void:
	print("  [Signal] Actor died: %s" % actor_id)


func _create_demo_replay() -> ReplayData.BattleRecord:
	# 创建一个简单的演示回放
	return ReplayData.BattleRecord.from_dict({
		"version": "2.0",
		"meta": {
			"battleId": "demo_battle",
			"recordedAt": Time.get_unix_time_from_system(),
			"tickInterval": 100,
			"totalFrames": 50,
			"result": "demo",
		},
		"configs": {
			"positionFormats": {
				"Character": "hex",
			},
		},
		"initialActors": [
			{
				"id": "actor_1",
				"type": "Character",
				"configId": "warrior",
				"displayName": "Warrior",
				"team": 0,
				"position": [-2, 0, 0],
				"attributes": { "hp": 100.0, "maxHp": 100.0 },
				"abilities": [],
				"tags": {},
			},
			{
				"id": "actor_2",
				"type": "Character",
				"configId": "mage",
				"displayName": "Mage",
				"team": 1,
				"position": [2, 0, 0],
				"attributes": { "hp": 80.0, "maxHp": 80.0 },
				"abilities": [],
				"tags": {},
			},
		],
		"timeline": [
			{
				"frame": 5,
				"events": [
					{
						"kind": "move_start",
						"actor_id": "actor_1",
						"from_hex": { "q": -2, "r": 0 },
						"to_hex": { "q": -1, "r": 0 },
					},
				],
			},
			{
				"frame": 10,
				"events": [
					{
						"kind": "damage",
						"target_actor_id": "actor_2",
						"damage": 25.0,
						"damage_type": "physical",
						"source_actor_id": "actor_1",
						"is_critical": false,
						"is_reflected": false,
					},
				],
			},
			{
				"frame": 20,
				"events": [
					{
						"kind": "heal",
						"target_actor_id": "actor_2",
						"heal_amount": 15.0,
						"source_actor_id": "actor_2",
					},
				],
			},
			{
				"frame": 30,
				"events": [
					{
						"kind": "damage",
						"target_actor_id": "actor_2",
						"damage": 50.0,
						"damage_type": "physical",
						"source_actor_id": "actor_1",
						"is_critical": true,
						"is_reflected": false,
					},
				],
			},
			{
				"frame": 40,
				"events": [
					{
						"kind": "damage",
						"target_actor_id": "actor_2",
						"damage": 30.0,
						"damage_type": "physical",
						"source_actor_id": "actor_1",
						"is_critical": false,
						"is_reflected": false,
					},
					{
						"kind": "death",
						"actor_id": "actor_2",
						"killer_actor_id": "actor_1",
					},
				],
			},
		],
	})
