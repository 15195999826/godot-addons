## HexAtbBattle Headless Demo 入口脚本
##
## addon 自带的 demo 场景: 无 UI / 无相机 / 无 view, 跑一场 6v6 默认战斗,
## 输出日志 / 录像。Godot 编辑器 F6 或 plugin 菜单「运行 HexATB 测试 (Headless)」。
##
## 真正的项目入口在主仓 scenes/Simulation.tscn (web 桥接)。本场景只是 addon
## 自检 / API 演示。frontend demo 在 addons/.../hex-atb-battle-frontend/
## demo_frontend.tscn (3D + camera + animator)。
extends Node


## 是否启用日志文件输出
@export var enable_logging: bool = true

## 是否启用录像文件输出
@export var enable_recording: bool = true

## 是否在控制台输出日志（Logger 的控制台输出，与 print 独立）
@export var enable_console_log: bool = false


var battle: HexDemoWorldGameplayInstance
var tick_interval: float = 100.0  # 每帧 100ms
var accumulated_time: float = 0.0


func _ready() -> void:
	print("HexAtbBattle Example Starting...")
	GameWorld.init()

	battle = GameWorld.create_instance(func() -> GameplayInstance:
		var b := HexDemoWorldGameplayInstance.new()
		b.start({
			"logging": enable_logging,
			"recording": enable_recording,
			"console_log": enable_console_log,
			"file_log": enable_logging,
		})
		return b
	)
	
	if DisplayServer.get_name() == "headless":
		_run_battle_sync()


func _process(delta: float) -> void:
	if not GameWorld.has_running_instances():
		return
	
	# 累积时间
	accumulated_time += delta * 1000.0  # 转换为毫秒
	
	# 按固定间隔执行 tick
	while accumulated_time >= tick_interval:
		GameWorld.tick_all(tick_interval)
		accumulated_time -= tick_interval


## 同步运行战斗（用于 headless 模式）
func _run_battle_sync() -> void:
	print("\n========== 同步运行战斗 ==========\n")
	
	var dt := 100.0
	for i in range(HexBattleProcedure.MAX_TICKS):
		GameWorld.tick_all(dt)
		if not GameWorld.has_running_instances():
			break
	
	print("\n========== 战斗运行完成 ==========")
	get_tree().quit()


## 手动运行战斗（用于测试）
static func run_battle() -> void:
	print("\n========== 运行 HexAtbBattle 示例 ==========\n")
	GameWorld.init()
	
	var hex_battle := HexDemoWorldGameplayInstance.new()
	hex_battle.start()
	
	var dt := 100.0
	for i in range(HexBattleProcedure.MAX_TICKS):
		hex_battle.tick(dt)
		if hex_battle._ended:
			break
	
	print("\n========== 示例运行完成 ==========")
