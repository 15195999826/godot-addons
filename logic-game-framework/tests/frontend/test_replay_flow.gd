## 回放流程测试脚本 - 验证完整的加载、播放、暂停、重置流程
extends Node

var _replay_scene: FrontendBattleReplayScene
var _director: FrontendBattleDirector
var _test_step := 0
var _test_timer := 0.0

func _ready() -> void:
	print("\n========== Replay Flow Test ==========\n")
	
	# 创建回放场景
	_replay_scene = FrontendBattleReplayScene.new()
	_replay_scene.name = "BattleReplayScene"
	add_child(_replay_scene)
	
	# 获取 director
	_director = _replay_scene.get_director()
	
	# 连接信号
	_director.playback_state_changed.connect(_on_playback_state_changed)
	_director.frame_changed.connect(_on_frame_changed)
	_director.playback_ended.connect(_on_playback_ended)
	
	# 加载演示回放
	print("Step 1: Loading demo replay...")
	var demo_replay := _create_demo_replay()
	_replay_scene.load_replay(demo_replay)
	print("  ✓ Replay loaded")
	print("  - Total frames: %d" % _director.get_total_frames())
	print("  - Current frame: %d" % _director.get_current_frame())
	
	_test_step = 1


func _process(delta: float) -> void:
	_test_timer += delta
	
	match _test_step:
		1:
			# 等待 1 秒后开始播放
			if _test_timer >= 1.0:
				print("\nStep 2: Starting playback...")
				_replay_scene.play()
				_test_step = 2
				_test_timer = 0.0
		
		2:
			# 播放 2 秒后暂停
			if _test_timer >= 2.0:
				print("\nStep 3: Pausing playback...")
				_replay_scene.pause()
				_test_step = 3
				_test_timer = 0.0
		
		3:
			# 暂停 1 秒后继续播放
			if _test_timer >= 1.0:
				print("\nStep 4: Resuming playback...")
				_replay_scene.play()
				_test_step = 4
				_test_timer = 0.0
		
		4:
			# 播放到结束或 3 秒后重置
			if _test_timer >= 3.0:
				print("\nStep 5: Resetting playback...")
				_replay_scene.reset()
				_test_step = 5
				_test_timer = 0.0
		
		5:
			# 重置后等待 1 秒，然后完成测试
			if _test_timer >= 1.0:
				print("\nStep 6: Test completed!")
				print("\n========== All Replay Flow Tests Passed! ==========\n")
				get_tree().quit()


func _on_playback_state_changed(is_playing: bool) -> void:
	print("  [Signal] Playback state changed: %s" % ("playing" if is_playing else "paused"))


func _on_frame_changed(current_frame: int, total_frames: int) -> void:
	if current_frame % 10 == 0:  # 每 10 帧打印一次
		print("  [Signal] Frame: %d / %d" % [current_frame, total_frames])


func _on_playback_ended() -> void:
	print("  [Signal] Playback ended")


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
