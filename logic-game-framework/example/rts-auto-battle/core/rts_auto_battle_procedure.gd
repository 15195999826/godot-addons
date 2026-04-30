## RtsAutoBattleProcedure - RTS 自动战斗过程
##
## BattleProcedure 的 RTS 特化: 连续 tick(默认 50ms/帧)推进 cooldown / 寻路 / AI;
## 一方全灭判胜负, MAX_TICKS 安全上限防死循环。
##
## 与 HexBattleProcedure 的差异:
## - 没有 ATB 累积; cooldown 直接随 tick_interval 在 actor 上递减
## - 没有"施法施放"显式段; basic attack 由 AI 在 cooldown 到 0 时即时触发
## - 不广播投射物事件(M0 无投射物 entity)
class_name RtsAutoBattleProcedure
extends BattleProcedure


## 安全上限。默认 1000 ticks, 配合 50ms tick_interval = 50s 真实时间。
## 战斗未在此期间内分出胜负即判 timeout(smoke 记 FAIL)。
const MAX_TICKS := 1000

## 默认连续 tick 间隔(毫秒)。50ms = 20Hz, 平衡寻路精度与 cpu 开销。
const RTS_TICK_INTERVAL_MS := 50.0


# ========== 字段 ==========

var left_team: Array[RtsBattleActor] = []
var right_team: Array[RtsBattleActor] = []

var _world_instance: RtsWorldGameplayInstance = null
var _result: String = ""
var _per_tick_callback: Callable = Callable()


# ========== 初始化 ==========

## opts 键:
##   - tick_interval_ms: float    每帧毫秒(默认 RTS_TICK_INTERVAL_MS)
##   - per_tick: Callable         每 tick 末尾回调(actor: 推进自身 cooldown / AI / 寻路同步)
##                                签名: func(procedure: RtsAutoBattleProcedure, dt_seconds: float)
func _init(
	world: RtsWorldGameplayInstance,
	left: Array[RtsBattleActor],
	right: Array[RtsBattleActor],
	opts: Dictionary = {},
) -> void:
	var all_actors: Array[Actor] = []
	for a in left:
		all_actors.append(a)
	for a in right:
		all_actors.append(a)
	super._init(world, all_actors)
	_world_instance = world
	left_team = left
	right_team = right
	_tick_interval = float(opts.get("tick_interval_ms", RTS_TICK_INTERVAL_MS))
	if opts.has("per_tick"):
		_per_tick_callback = opts.get("per_tick", Callable()) as Callable


# ========== 生命周期 ==========

func tick_once() -> void:
	if _finished:
		return
	_current_tick += 1

	var world := _world_instance
	if world != null:
		world.base_tick(_tick_interval)

	# 让 AbilitySet 内部 cooldown / buff duration 推进(若 actor 持 ability_set)。
	# RtsCharacterActor 在 M0.3 后会持 ability_set; M0.2 阶段 actor 可能为 null。
	for actor in get_alive_actors():
		var ability_set := _safe_get_ability_set(actor)
		if ability_set != null:
			ability_set.tick(_tick_interval, get_logic_time())

	# 项目层 tick(AI 决策、寻路同步、attack_cooldown 推进)
	# dt 以秒为单位传出, 业务层用秒做 cooldown 算术更直观。
	if _per_tick_callback.is_valid():
		_per_tick_callback.call(self, _tick_interval / 1000.0)

	record_current_frame_events()

	if _current_tick >= MAX_TICKS:
		_result = "timeout"
		mark_finished()
	else:
		_check_battle_end()


func finish(result: String = "") -> Dictionary:
	var effective := result if result != "" else _result
	if effective == "":
		effective = "battle_complete"
	return super.finish(effective)


# ========== 查询 ==========

func get_all_actors() -> Array[RtsBattleActor]:
	var result: Array[RtsBattleActor] = []
	result.append_array(left_team)
	result.append_array(right_team)
	return result


func get_alive_actors() -> Array[RtsBattleActor]:
	var result: Array[RtsBattleActor] = []
	for actor in get_all_actors():
		if not actor.is_dead():
			result.append(actor)
	return result


func get_result() -> String:
	return _result


# ========== 胜负判定 ==========

func _check_battle_end() -> bool:
	var left_alive := 0
	var right_alive := 0
	for actor in left_team:
		if not actor.is_dead():
			left_alive += 1
	for actor in right_team:
		if not actor.is_dead():
			right_alive += 1

	if left_alive == 0 and right_alive == 0:
		_result = "draw"
		mark_finished()
		return true
	if left_alive == 0:
		_result = "right_win"
		mark_finished()
		return true
	if right_alive == 0:
		_result = "left_win"
		mark_finished()
		return true
	return false


# ========== 内部 ==========

## RtsBattleActor 基类不强制持 ability_set; 子类(RtsCharacterActor)有时才走 AbilitySet 路径。
## 用 has_method 探测避免 M0.2 阶段空 actor 崩溃。
func _safe_get_ability_set(actor: RtsBattleActor) -> AbilitySet:
	if actor == null:
		return null
	if actor.has_method("get_ability_set"):
		return actor.call("get_ability_set") as AbilitySet
	return null
