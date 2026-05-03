## RTS pathfinding baseline smoke (M3 0AD migration M0.1)
##
## 目标: 跑一份 master 当前状态的 30s 战斗, 产出 git-tracked baseline:
##   1. user://0ad-baseline-master.csv  — path_trace_v2 24 字段 trace, 每 tick 每 alive
##      actor 一行 (后续 M5/M7 跑同 smoke 应 bit-identical 这文件)
##   2. user://0ad-baseline-master.replay.json — procedure.finish() 返回的 record dict
##      序列化 (含 timeline events + player_commands + rng_seed; 用 LGF 既有 ReplayPlayer
##      可重放, 等 M5/M7 验证寻路改写 bit-identical 用)
##
## Setup (跟 smoke_castle_war_minimal 类比的简化版):
##   - map 500×500, RtsBattleMap (中央障碍 cells (200..300, 200..300))
##   - 4v4 (2 melee + 2 ranged 每队), 出生跟 smoke_rts_auto_battle 一致
##   - 双方各 1 crystal_tower (远端) 让胜负判定走 crystal_tower 模式
##   - 跑固定 MAX_TICKS = 900 (= 30 Hz × 30s) 但 procedure 自然结束也 break — 让 trace
##     行数 = "战斗到自然结束 + 死单位剔除后的 alive_actor 行" (不强求 900 行/单位)
##   - rng_seed 固定 42 (与 smoke_replay_bit_identical 一致 — replay 互通)
##
## 关键不变量 (后续 milestone 验证):
##   - 同 seed + 无玩家命令 → trace CSV bit-identical
##   - replay JSON 通过 ReplayPlayer 能重放出同样 actor 轨迹
##
## 输出 (按 CLAUDE.md 约定):
##   SMOKE_TEST_RESULT: PASS - <ticks>/<rows>/<events> 信息行
##   exit_code = 0
##
## 决策来源: M3-0AD-pathfinding-migration / M0-footprint-split.md §M0.1 + AC7
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

const TICK_INTERVAL_MS: float = 1000.0 / 30.0  # 30 Hz fixed-tick (与 RtsAutoBattleProcedure.RTS_TICK_INTERVAL_MS 一致)
const MAX_TICKS: int = 900  # 30 Hz × 30s
const RNG_SEED: int = 42

const TRACE_PATH: String = "user://0ad-baseline-master.csv"
const REPLAY_PATH: String = "user://0ad-baseline-master.replay.json"


# ========== Runtime ==========

var _world: RtsWorldGameplayInstance = null
var _procedure: RtsAutoBattleProcedure = null
var _battle_map: RtsBattleMap = null
var _trace: PathTraceV2Writer = null

var _agents: Dictionary = {}        # actor_id → RtsNavAgent
var _controllers: Dictionary = {}   # actor_id → RtsUnitController


func _ready() -> void:
	GameWorld.init()

	# IdGenerator reset 让 actor_id 从 1 起 — 多次跑 baseline 时 trace 内 unit_id 字符串
	# 也对齐 (与 smoke_replay_bit_identical 同思路)
	IdGenerator.reset_id_counter()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_battle_map.grid)

	# 4v4 unit roster (同 smoke_rts_auto_battle): 2 melee + 2 ranged 每队
	var roster: Array[Config.UnitClass] = [
		Config.UnitClass.MELEE,
		Config.UnitClass.MELEE,
		Config.UnitClass.RANGED,
		Config.UnitClass.RANGED,
	]
	var left_actors: Array[RtsBattleActor] = []
	var right_actors: Array[RtsBattleActor] = []
	for i in range(roster.size()):
		var left_pos: Vector2 = RtsBattleMap.sample_team_spawn(0, i, roster.size())
		var right_pos: Vector2 = RtsBattleMap.sample_team_spawn(1, i, roster.size())
		left_actors.append(_spawn_unit(roster[i], 0, left_pos))
		right_actors.append(_spawn_unit(roster[i], 1, right_pos))

	# 双方各 1 crystal_tower (远端 — y=80 上方; 不影响 4v4 主战线接敌, 但提供 building trace 行)
	# 留 y=80 让 ct 落在 sample_team_spawn 顶 slot 之上 (slot 0=80) — 实际单位起点 80, ct 放更上方
	var left_ct: RtsBuildingActor = RtsBuildings.create_crystal_tower()
	left_ct.set_team_id(0)
	_world.add_actor(left_ct)
	left_ct.position_2d = Vector2(50.0, 30.0)
	left_actors.append(left_ct)

	var right_ct: RtsBuildingActor = RtsBuildings.create_crystal_tower()
	right_ct.set_team_id(1)
	_world.add_actor(right_ct)
	right_ct.position_2d = Vector2(450.0, 30.0)
	right_actors.append(right_ct)

	# Team configs: 双方都没 build_zone / 起手资源 (此 baseline 不放兵营, 不下玩家命令)
	var team_configs: Dictionary[int, RtsTeamConfig] = {
		0: RtsTeamConfig.create(0, "left_faction", {}, Rect2()),
		1: RtsTeamConfig.create(1, "right_faction", {}, Rect2()),
	}

	_procedure = _world.start_rts_battle(left_actors, right_actors, {
		"tick_interval_ms": TICK_INTERVAL_MS,
		"unit_runtimes": _controllers,
		"rng_seed": RNG_SEED,
		"team_configs": team_configs,
	})

	# Trace writer 初始化
	_trace = PathTraceV2Writer.new()
	if not _trace.open(TRACE_PATH):
		_fail("failed to open trace file: %s" % TRACE_PATH)
		return
	_trace.write_header()

	# 主循环: 每 tick 跑 procedure → write_row. 战斗自然结束 (should_end) 也立刻 break,
	# 让 trace 行数稳定 = ticks_run × alive_actors_per_tick.
	var ticks_run: int = 0
	for tick_i in range(MAX_TICKS):
		_procedure.tick_once()
		ticks_run = _procedure.get_current_tick()
		_trace.write_row(_world, ticks_run)
		if _procedure.should_end():
			break

	var record: Dictionary = _procedure.finish()
	_trace.close()

	# Dump replay JSON
	if not _save_replay_json(record):
		_fail("failed to save replay JSON: %s" % REPLAY_PATH)
		return

	# 报告
	var trace_rows: int = _trace.get_row_count()
	var timeline: Array = record.get("timeline", []) as Array
	var event_count: int = 0
	for frame in timeline:
		var f: Dictionary = frame as Dictionary
		event_count += (f.get("events", []) as Array).size()

	var trace_real_path: String = ProjectSettings.globalize_path(TRACE_PATH)
	var replay_real_path: String = ProjectSettings.globalize_path(REPLAY_PATH)
	print("baseline smoke: ticks=%d trace_rows=%d events=%d result=%s" % [
		ticks_run, trace_rows, event_count, _procedure.get_result(),
	])
	print("  trace:  %s" % trace_real_path)
	print("  replay: %s" % replay_real_path)

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - %d ticks, trace=%d rows, replay events=%d" % [
		ticks_run, trace_rows, event_count,
	])
	get_tree().quit(0)


# ========== Helpers ==========

func _spawn_unit(unit_class: int, team_id: int, pos: Vector2) -> RtsUnitActor:
	var unit := RtsUnitActor.new(unit_class)
	unit.set_team_id(team_id)
	_world.add_actor(unit)
	unit.position_2d = pos

	var agent := RtsNavAgent.new()
	_battle_map.add_child(agent)
	agent.bind_actor(unit, _battle_map.grid)
	_agents[unit.get_id()] = agent

	var strategy: RtsAIStrategy = RtsAIStrategyFactory.get_strategy(unit_class)
	var controller := RtsUnitController.new(unit, agent, strategy)
	_controllers[unit.get_id()] = controller

	return unit


## 把 procedure.finish() 返回的 record dict 序列化为 JSON 落盘.
##
## record dict 含: timeline (Array[Dictionary{frame, events}]) + player_commands (Array) +
## rng_seed (int) + base BattleProcedure.finish() 注入的字段.
##
## HexCoord (frontend visualizer 不会读, replay 比对仅做字段级 diff) 用 to_dict() 序列化前
## 转换 — 但 RTS event 字段里的 HexCoord (footprint cells 等) 在 timeline 里出现时,
## JSON.stringify 会把 HexCoord 序列化为 "<HexCoord:#xxx>" instance ID, 等 ReplayPlayer
## 重放仅消费 actor_id / position 等基础字段, 不依赖此字段重建 — 故 M0 阶段 OK.
##
## 返回 true 表示落盘成功; false 表示 file open 失败.
func _save_replay_json(record: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(REPLAY_PATH, FileAccess.WRITE)
	if f == null:
		return false
	# 用 JSON.stringify 默认 indent="" 紧凑模式 (省 baseline 文件 size; future diff 工具会
	# parse JSON 不依赖空白)
	var json_text: String = JSON.stringify(record)
	f.store_string(json_text)
	f.close()
	return true


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	if _trace != null:
		_trace.close()
	get_tree().quit(1)
