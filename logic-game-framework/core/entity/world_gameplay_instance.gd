## WorldGameplayInstance - 世界 Instance（整局游戏一个 session）
##
## 从"战斗 owns 世界"切换为"世界 owns 战斗"。World 长期持有 actor / grid / systems,
## 战斗是 procedure(短命 RefCounted)。Signal 由显式 mutation API 触发, 服务于
## frontend 非战斗期的 view lifecycle 同步;战斗期间视觉靠 BattleAnimator 消费
## event_timeline 回放, 不消费这些 signal。
##
## 详见 docs/README.md（World owns Battle + 响应式前端 节）
class_name WorldGameplayInstance
extends GameplayInstance

# ========== 常量 ==========

## 每个 world tick 推进多少 battle tick。
##
## 默认 INT_MAX: 战斗在一个 world tick 内跑完(退化到 blocking 语义)。
## 未来若单场战斗过长导致卡顿, 调小此值让战斗横跨多个 world tick。
const BATTLE_TICKS_PER_WORLD_FRAME: int = 9223372036854775807


# ========== Signal ==========
#
# 仅在"非战斗期间"广播(actor 进/出世界、NPC 移动、buff 过期等)。
# 战斗期间 frontend 由 BattleAnimator 消费 event_timeline 回放视觉, 不订阅这些 signal。
# 战斗期 actor 属性变化直接改内存, 不走显式 mutation API, 所以不触发 signal。

signal actor_added(actor_id: String)
signal actor_removed(actor_id: String)
signal actor_position_changed(actor_id: String, old_coord: HexCoord, new_coord: HexCoord)
signal grid_configured(config: GridMapConfig)
signal grid_cell_changed(coord: HexCoord, change_type: String)
signal battle_finished(timeline: Dictionary)


# ========== 字段 ==========

var grid: GridMapModel = null

var _active_battle: BattleProcedure = null


# ========== 初始化 ==========

func _init(id_value: String = "") -> void:
	super._init(id_value if id_value != "" else IdGenerator.generate("world"))
	type = "world"


# ========== 显式 mutation API ==========

## 可选 after_id_assigned 回调在 ID 分配 / registry 写入之后、actor_added signal 之前执行。
## 用于 spawn path 在外部观察者 snapshot actor 前完成 position / team / abilities 初始化。
func add_actor(actor: Actor, after_id_assigned: Callable = Callable()) -> Actor:
	var added := super.add_actor(actor)
	if added != null:
		if after_id_assigned.is_valid():
			after_id_assigned.call(added)
		actor_added.emit(added.get_id())
	return added


func remove_actor(actor_id: String) -> bool:
	var removed := super.remove_actor(actor_id)
	if removed:
		actor_removed.emit(actor_id)
	return removed


## 配置网格。子类可覆盖以接入具体的 grid backend(如 UGridMap autoload)。
## 必须最后 emit grid_configured 以保证 signal 只由显式 mutation 触发。
func configure_grid(config: GridMapConfig) -> void:
	grid = GridMapModel.new()
	grid.initialize(config)
	grid_configured.emit(config)


# ========== 战斗调度 ==========

## 拍摄开战时刻的世界快照（录像范围内的 registry actor + 地图配置 + 坐标格式声明）,
## 供 BattleProcedure 注入 recorder, 作为回放的起点。范围默认全体 actor 而非仅参战者
## —— 环境物/障碍物也是回放要摆的台面; 中途 spawn 的走 ActorSpawned 事件。
func capture_world_snapshot() -> PlaybackData.WorldSnapshot:
	var snap := PlaybackData.WorldSnapshot.new()
	for actor in get_recordable_actors():
		snap.actors.append(PlaybackData.ActorInitData.create(actor))
	if grid != null:
		snap.map_config = grid.to_config_dict()
	snap.position_formats = _get_position_formats()
	return snap


## 战斗录像范围内的 actor（快照 + 变化订阅共用同一集合）。
func get_recordable_actors() -> Array[Actor]:
	var result: Array[Actor] = []
	for actor in get_actors():
		if should_record_actor(actor):
			result.append(actor)
	return result


## 该 actor 是否属于战斗录像范围（快照 / 变化订阅 / 中途补录三处同语义）。
## 常驻世界子类 override 排除与战斗无关的 registry 常客（如 overworld 玩家/NPC）,
## 否则回放器会为它们建战斗视觉替身。
func should_record_actor(_actor: Actor) -> bool:
	return true


## 坐标格式声明钩子: 回放器用它解释各 actor 的 position 数组（如 {"Character": "hex"}）。
## 坐标系语义是子类知识, 基类不假设。
func _get_position_formats() -> Dictionary:
	return {}


## 开启一场战斗。procedure 由子类工厂 _create_battle_procedure 返回。
## 调方监听 battle_finished signal 获取最终 timeline。
func start_battle(participants: Array[Actor]) -> BattleProcedure:
	Log.assert_crash(_active_battle == null, "WorldGameplayInstance", "MVP: 同时只允许一场战斗")
	_active_battle = _create_battle_procedure(participants)
	_active_battle.start()
	return _active_battle


## 工厂钩子:子类覆盖以返回具体的 BattleProcedure 子类(如 HexBattleProcedure)。
func _create_battle_procedure(participants: Array[Actor]) -> BattleProcedure:
	return BattleProcedure.new(self, participants)


func has_active_battle() -> bool:
	return _active_battle != null


func get_active_battle() -> BattleProcedure:
	return _active_battle


# ========== Tick ==========

## 世界 tick。有未完成战斗时本帧独占给战斗(不跑世界 system);
## 无战斗时走 base_tick 跑 systems。分帧吞吐由 BATTLE_TICKS_PER_WORLD_FRAME 控制。
## emit 之前先 null 掉 _active_battle, 让 handler 里再 start_battle() 的重入安全通过 assert。
func tick(dt: float) -> void:
	if _active_battle == null:
		base_tick(dt)
		return
	var remaining := BATTLE_TICKS_PER_WORLD_FRAME
	while remaining > 0:
		_active_battle.tick_once()
		if _active_battle.should_end():
			var timeline := _active_battle.finish()
			_active_battle = null
			battle_finished.emit(timeline)
			return
		remaining -= 1
