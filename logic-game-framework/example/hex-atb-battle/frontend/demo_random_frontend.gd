## Hex ATB Random Frontend Demo
##
## 与 demo_frontend.gd 共用同一套 WorldView + BattleAnimator wire, 但创建
## HexRandomDemoWorldGameplayInstance, 每次 Start 随机组装职业、主技能和额外 passive。
extends "res://addons/logic-game-framework/example/hex-atb-battle/frontend/demo_frontend.gd"


const RandomWorldGIScript := preload("res://addons/logic-game-framework/example/hex-atb-battle/logic/hex_random_demo_world_gameplay_instance.gd")


var _seed_input: SpinBox
var _passive_count_input: SpinBox


func _setup_config_ui() -> void:
	super._setup_config_ui()
	var title := get_node_or_null("ConfigUI/VBoxContainer/TitleLabel") as Label
	if title != null:
		title.text = "=== Random Skill Battle ==="
	_start_battle_button.text = "Start Random Skill Battle"

	var vbox := get_node("ConfigUI/VBoxContainer") as VBoxContainer
	_seed_input = _add_spin_control(vbox, "Seed", "Seed (0=random):", 0.0, 999999999.0, 0.0)
	_passive_count_input = _add_spin_control(vbox, "PassiveCount", "Extra Passives:", 0.0, 3.0, 1.0)


func set_random_config(random_seed: int, _team_size: int, passives_per_actor: int) -> void:
	if _seed_input != null:
		_seed_input.value = random_seed
	if _passive_count_input != null:
		_passive_count_input.value = passives_per_actor


func get_random_battle_summary() -> Dictionary:
	if _battle != null and _battle.has_method("get_random_summary"):
		return _battle.call("get_random_summary") as Dictionary
	return {}


func get_random_replay_data() -> Dictionary:
	if _battle != null:
		return _battle.get_replay_data()
	return {}


func _add_spin_control(
	vbox: VBoxContainer,
	control_name: String,
	label_text: String,
	min_value: float,
	max_value: float,
	default_value: float
) -> SpinBox:
	var container := HBoxContainer.new()
	container.name = "%sContainer" % control_name
	var label := Label.new()
	label.name = "%sLabel" % control_name
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(label)
	var input := SpinBox.new()
	input.name = "%sInput" % control_name
	input.min_value = min_value
	input.max_value = max_value
	input.value = default_value
	input.step = 1.0
	container.add_child(input)
	vbox.add_child(container)
	vbox.move_child(container, _start_battle_button.get_index())
	return input


func _on_start_battle_button_pressed() -> void:
	_update_status("Running random battle simulation...")
	_start_battle_button.disabled = true

	_world_view.unbind_world()
	if _battle != null:
		GameWorld.destroy_instance(_battle.id)
	_battle = null

	var map_config := _get_map_config()
	print("[RandomMain] Starting random battle with map config: %s" % map_config)

	_battle = RandomWorldGIScript.new() as HexDemoWorldGameplayInstance
	GameWorld.create_instance(func() -> GameplayInstance: return _battle)
	_battle.battle_finished.connect(_on_battle_finished)
	_battle.battle_final_state_ready.connect(_on_battle_final_state_ready)
	_final_state = {}

	_world_view.bind_world(_battle)

	_battle.start({
		"logging": false,
		"recording": true,
		"console_log": false,
		"file_log": false,
		"map_config": map_config,
		"random_seed": int(_seed_input.value),
		"passives_per_actor": int(_passive_count_input.value),
	})

	var dt := 100.0
	for _i in range(HexBattleProcedure.MAX_TICKS):
		GameWorld.tick_all(dt)
		if not GameWorld.has_running_instances():
			break

	var summary := get_random_battle_summary()
	var resolved_seed := int(summary.get("seed", 0))
	print("[RandomMain] Logic battle completed in %d ticks (seed=%d)" % [_battle.tick_count, resolved_seed])
