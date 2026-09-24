## Smoke: 表演 golden —— 固定 seed 的随机战斗录像，不经场景 / view，直接喂 FrontendBattleDirector 按逻辑帧
## step() 推到 playback_ended，把表演层可观察的一切定成指纹：
##   ① 每步翻译出的卡片序列 (frame, kind, actor_id, delay, duration)
##   ② 每步 flush 后每个 actor 的账本 (pos = 含在飞插值、取整到 hex 整数; at = 已落定的格子;
##      target_hp / round(visual_hp) / is_alive / buff ids / shield ids)，只记与上一步不同的行
##   ③ 每步一次性效果按种类的 spawn / remove 计数，以及 actor_died / actor_spawned 的 id
## 每个 seed 一份明文 dump 落 .claude/tmp/presentation-golden/seed_<seed>.txt（重烤时另存 .baked.txt 供差分归因），
## 指纹 = dump 的 sha256，与同目录 presentation_golden.json 逐 seed 比对；录像本身另取一份 sha 帮助归因
## （录像变了 = 逻辑层漂移，不是表演层的锅）。dump 里的生成 id 按 seed 内首现序规范化成「前缀#序号」，
## 进程内多场连跑的 IdGenerator 计数不进指纹。
## 有意的行为变化须先解释再重烤：godot --headless --path . <本场景> -- rebake
##
## 改名阶段：KIND_NAMES 左边换成新 kind，右边的 golden 名不动，指纹不随改名漂；Director / 注册表 / 账本
## 三处私有钩子（_registry / _world / _scheduler）搬家后改指向即可。
extends Node


const GOLDEN_PATH := "res://addons/logic-game-framework/example/hex-atb-battle/tests/frontend/presentation_golden.json"
const DUMP_DIR := "res://.claude/tmp/presentation-golden"
const PASSIVES_PER_ACTOR := 1
## 录像帧数之外再允许这么多步排空动画；超过判 Director 永不 playback_ended。
const DRAIN_STEP_LIMIT := 1000

## seed 集合：651143 与 smoke_random_frontend_main 同款（demo 原规则，3v3 全员进攻位），一局出 10 种卡片；
## 另两个从 hex/random-golden 的覆盖率 seed 里挑，补它出不了的两种：900127 出 cone_debug_overlay、900191 出 bump
## （2026-09-24 在那 10 个 seed 上探针得出，三个合起来把翻译员会产出的 12 种卡片全覆盖）。
## offensive_slots 见 HexRandomDemoWorldGameplayInstance：-1 = demo 原规则，1 = 一位进攻、两位从全池抽。
const RUNS: Array[Dictionary] = [
	{"seed": 651143, "offensive_slots": -1},
	{"seed": 900127, "offensive_slots": 1},
	{"seed": 900191, "offensive_slots": 1},
]

## 卡片种类 → golden 名。指纹只认右边；改名阶段只换左边的键。
const KIND_NAMES := {
	FrontendVisualAction.ActionType.MOVE: "move",
	FrontendVisualAction.ActionType.APPLY_HP_DELTA: "hp_delta",
	FrontendVisualAction.ActionType.FLOATING_TEXT: "floating_text",
	FrontendVisualAction.ActionType.MELEE_STRIKE: "melee_strike",
	FrontendVisualAction.ActionType.PROCEDURAL_VFX: "procedural_vfx",
	FrontendVisualAction.ActionType.DEATH: "death",
	FrontendVisualAction.ActionType.ATTACK_VFX: "attack_vfx",
	FrontendVisualAction.ActionType.PROJECTILE: "projectile",
	FrontendVisualAction.ActionType.APPLY_BUFF_STATE: "buff_state",
	FrontendVisualAction.ActionType.APPLY_SHIELD_STATE: "shield_state",
	FrontendVisualAction.ActionType.BUMP: "bump",
	FrontendVisualAction.ActionType.APPLY_FACING_STATE: "facing_state",
	FrontendVisualAction.ActionType.CONE_DEBUG_OVERLAY: "cone_debug_overlay",
}


## 包一层 Director 自带的注册表：翻译结果原样返回，顺手把每张卡片记下来（只在本 smoke 用）。
class RecordingRegistry extends FrontendVisualizerRegistry:
	var inner: FrontendVisualizerRegistry
	var frame_of: Callable
	var cards: Array[Dictionary] = []

	func _init(p_inner: FrontendVisualizerRegistry, p_frame_of: Callable) -> void:
		inner = p_inner
		frame_of = p_frame_of

	func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
		var actions := inner.translate(event, context)
		var frame: int = frame_of.call()
		for action: FrontendVisualAction in actions:
			cards.append({
				"frame": frame,
				"type": action.type,
				"actor_id": action.actor_id,
				"delay": action.delay,
				"duration": action.duration,
			})
		return actions

	func has_visualizer_for(event_kind: String) -> bool:
		return inner.has_visualizer_for(event_kind)

	func get_visualizers_for(event_kind: String) -> Array[String]:
		return inner.get_visualizers_for(event_kind)


var _director: FrontendBattleDirector
var _recorder: RecordingRegistry
## 本步一次性效果计数：kind -> [spawn, remove]
var _fx: Dictionary = {}
var _died: Array[String] = []
var _spawned: Array[String] = []
var _ended := false
## 本 seed 的 id 规范化表：真实 id -> 「前缀#序号」
var _id_map: Dictionary = {}
var _id_counts: Dictionary = {}


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	var rebake := OS.get_cmdline_user_args().has("rebake")
	var status := _run(rebake)
	GameWorld.shutdown()
	if status == "":
		print("SMOKE_TEST_RESULT: PASS - presentation golden unchanged over %d seeds" % RUNS.size())
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_RESULT: FAIL - %s" % status)
		get_tree().quit(1)


func _run(rebake: bool) -> String:
	var golden := _load_golden()
	if not rebake and golden.is_empty():
		return "golden missing or unreadable: %s (run with -- rebake)" % GOLDEN_PATH
	var expected_runs: Dictionary = golden.get("runs", {})
	var baked := {}
	var failures: Array[String] = []
	for run in RUNS:
		var seed_value := int(run["seed"])
		var offensive := int(run["offensive_slots"])
		var outcome := _run_seed(seed_value, offensive, rebake)
		if outcome.has("error"):
			return "seed %d: %s" % [seed_value, str(outcome["error"])]
		var row: Dictionary = outcome["row"]
		baked[str(seed_value)] = row
		if rebake:
			continue
		var expected: Dictionary = expected_runs.get(str(seed_value), {})
		if expected.is_empty():
			failures.append("seed %d has no golden entry" % seed_value)
		elif int(expected.get("offensive_slots", -2)) != offensive:
			failures.append("seed %d golden offensive_slots=%s but RUNS says %d" % [
				seed_value, str(expected.get("offensive_slots")), offensive])
		elif str(expected.get("sha256", "")) != str(row["sha256"]):
			failures.append(_describe_drift(seed_value, expected, row, outcome["dump_path"]))
	if rebake:
		_save_golden({
			"generated_by": "smoke_presentation_golden.gd",
			"passives_per_actor": PASSIVES_PER_ACTOR,
			"runs": baked,
		})
		print("REBAKED %d seeds -> %s" % [baked.size(), GOLDEN_PATH])
	return "; ".join(failures)


## 跑一个 seed：逻辑战斗 → 录像 → Director 逐帧 step → dump / 指纹。返回 {row, dump_path} 或 {error}。
func _run_seed(seed_value: int, offensive: int, rebake: bool) -> Dictionary:
	var replay := _play_logic_battle(seed_value, offensive)
	if replay.is_empty():
		return {"error": "produced no replay"}
	var record := PlaybackData.BattleRecord.from_dict(replay)
	if record.timeline.is_empty():
		return {"error": "replay has an empty timeline"}
	var record_sha := _record_fingerprint(replay)
	var step_ms := float(record.meta.tick_interval)

	_reset_observers()
	_director = FrontendBattleDirector.new()
	_director.name = "Director_%d" % seed_value
	add_child(_director)
	_recorder = RecordingRegistry.new(_director._registry, _director.get_current_frame)
	_director._registry = _recorder
	_connect_observers()
	_director.load_playback(record)

	var lines: PackedStringArray = []
	lines.append("seed=%d offensive_slots=%d passives=%d step_ms=%s record_frames=%d result=%s" % [
		seed_value, offensive, PASSIVES_PER_ACTOR, _num(step_ms), record.meta.total_frames, record.meta.result,
	])
	var prev := {}
	lines.append("step 0 frame=0 (loaded)")
	_append_state(lines, prev)

	var steps := 0
	var limit := record.meta.total_frames + DRAIN_STEP_LIMIT
	while not _ended:
		if steps >= limit:
			return {"error": "director never reached playback_ended after %d steps (frame %d/%d, %d active actions)" % [
				steps, _director.get_current_frame(), _director.get_total_frames(), _director._scheduler.get_action_count(),
			]}
		_fx.clear()
		_died.clear()
		_spawned.clear()
		var card_start := _recorder.cards.size()
		_director.step(step_ms)
		steps += 1
		lines.append("step %d frame=%d" % [steps, _director.get_current_frame()])
		for i in range(card_start, _recorder.cards.size()):
			lines.append(_format_card(_recorder.cards[i]))
		_append_state(lines, prev)
		_append_fx(lines)

	if _director.get_current_frame() != record.meta.total_frames:
		return {"error": "ended at frame %d but record has %d frames" % [_director.get_current_frame(), record.meta.total_frames]}

	var kinds := {}
	for card in _recorder.cards:
		kinds[KIND_NAMES[card["type"]]] = true
	var kind_list: Array = kinds.keys()
	kind_list.sort()

	var dump := "\n".join(lines) + "\n"
	var sha := dump.sha256_text()
	var row := {
		"offensive_slots": offensive,
		"step_ms": step_ms,
		"record_frames": record.meta.total_frames,
		"record_sha256": record_sha,
		"steps": steps,
		"cards": _recorder.cards.size(),
		"actors": prev.size(),
		"kinds": kind_list,
		"sha256": sha,
		"fingerprint": ("0x" + sha.substr(0, 8)).hex_to_int(),
	}
	var dump_path := _write_dump(seed_value, dump, ".txt")
	if rebake:
		_write_dump(seed_value, dump, ".baked.txt")
	print("PRESENTATION_GOLDEN seed=%d offensive=%d frames=%d steps=%d cards=%d actors=%d fingerprint=%d sha=%s kinds=%s" % [
		seed_value, offensive, row["record_frames"], steps, row["cards"], row["actors"], row["fingerprint"],
		sha.substr(0, 12), ",".join(PackedStringArray(kind_list)),
	])

	remove_child(_director)
	_director.free()
	_director = null
	_recorder = null
	return {"row": row, "dump_path": dump_path}


func _describe_drift(seed_value: int, expected: Dictionary, row: Dictionary, dump_path: String) -> String:
	var logic_note := "record unchanged (presentation-side drift)"
	if str(expected.get("record_sha256", "")) != str(row["record_sha256"]):
		logic_note = "RECORD ITSELF CHANGED (logic-side drift, check hex/random-golden first)"
	return "seed %d presentation fingerprint drift: %s; frames %s->%s, steps %s->%s, cards %s->%s, actors %s->%s; diff %s against %s" % [
		seed_value, logic_note,
		str(expected.get("record_frames")), str(row["record_frames"]),
		str(expected.get("steps")), str(row["steps"]),
		str(expected.get("cards")), str(row["cards"]),
		str(expected.get("actors")), str(row["actors"]),
		dump_path, _dump_path(seed_value, ".baked.txt"),
	]


# ========== 逻辑战斗 ==========

## 与 demo_random_frontend 同一份地图配置（9×9 / size 1 / FLAT 是 demo UI 的默认值，与 GI 自带默认 size 10 不同——
## 投射物 duration 由世界距离算，地图尺寸进指纹）。只取内存里的录像，不落文件。
func _play_logic_battle(seed_value: int, offensive: int) -> Dictionary:
	GameWorld.shutdown()
	var map_config := GridMapConfig.new()
	map_config.grid_type = GridMapConfig.GridType.HEX
	map_config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
	map_config.rows = 9
	map_config.columns = 9
	map_config.size = 1.0
	map_config.orientation = GridMapConfig.Orientation.FLAT

	var battle := HexRandomDemoWorldGameplayInstance.new()
	GameWorld.create_instance(battle)
	battle.start({
		"logging": false,
		"recording": true,
		"console_log": false,
		"file_log": false,
		"save_replay": false,
		"map_config": map_config,
		"random_seed": seed_value,
		"passives_per_actor": PASSIVES_PER_ACTOR,
		"offensive_slots": offensive,
	})
	for _i in range(HexBattleProcedure.MAX_TICKS + 1):
		GameWorld.tick_all(100.0)
		if not GameWorld.has_running_instances():
			break
	var replay := battle.get_replay_data()
	GameWorld.shutdown()
	return replay


## 录像 dict 去掉 wall-clock 字段后的 sha，只用来归因（录像变了 ≠ 表演层变了）。
## 不做 id 规范化：同一进程内的 seed 顺序固定，RUNS 变动时本字段随之变属预期。
func _record_fingerprint(replay: Dictionary) -> String:
	var doc := replay.duplicate()
	var meta: Dictionary = (replay.get("meta", {}) as Dictionary).duplicate()
	meta.erase("recorded_at")
	doc["meta"] = meta
	return JSON.stringify(doc).sha256_text()


# ========== 观察 ==========

func _reset_observers() -> void:
	_fx.clear()
	_died.clear()
	_spawned.clear()
	_ended = false
	_id_map.clear()
	_id_counts.clear()


func _connect_observers() -> void:
	_director.floating_text_created.connect(func(_data: Variant) -> void: _count("floating_text", 0))
	_director.attack_vfx_created.connect(func(_data: Variant) -> void: _count("attack_vfx", 0))
	_director.attack_vfx_removed.connect(func(_id: String) -> void: _count("attack_vfx", 1))
	_director.projectile_created.connect(func(_data: Variant) -> void: _count("projectile", 0))
	_director.projectile_removed.connect(func(_id: String) -> void: _count("projectile", 1))
	_director.cone_debug_overlay_created.connect(func(_data: Variant) -> void: _count("cone_debug_overlay", 0))
	_director.actor_died.connect(func(actor_id: String) -> void: _died.append(_canon_id(actor_id)))
	_director.actor_spawned.connect(func(actor_id: String, _state: Variant) -> void: _spawned.append(_canon_id(actor_id)))
	_director.playback_ended.connect(func() -> void: _ended = true)


func _count(kind: String, slot: int) -> void:
	if not _fx.has(kind):
		_fx[kind] = [0, 0]
	_fx[kind][slot] += 1


## 生成 id（demo_0:Character_3 / demo_0:Environment_84 / ability_52）按首现序规范化成「前缀#序号」，
## 前缀取最后一段去掉尾部 _<数字>；没有数字尾巴的 id 原样返回。
func _canon_id(id: String) -> String:
	if id.is_empty():
		return id
	if _id_map.has(id):
		return _id_map[id]
	var last := id.substr(id.rfind(":") + 1)
	var underscore := last.rfind("_")
	if underscore < 0 or not last.substr(underscore + 1).is_valid_int():
		return id
	var prefix := last.substr(0, underscore)
	var next: int = int(_id_counts.get(prefix, 0)) + 1
	_id_counts[prefix] = next
	var canon := "%s#%d" % [prefix, next]
	_id_map[id] = canon
	return canon


func _format_card(card: Dictionary) -> String:
	return "card f=%d %s actor=%s delay=%s dur=%s" % [
		card["frame"], KIND_NAMES[card["type"]], _canon_id(card["actor_id"]), _num(card["delay"]), _num(card["duration"]),
	]


## 每个 actor 一行；只在与上一步不同的时候写（首步全写），是全量序列的等价编码。
func _append_state(lines: PackedStringArray, prev: Dictionary) -> void:
	var snapshot := _director.get_actors_snapshot()
	var context: FrontendVisualizerContext = _director._world.as_context()
	for id_variant in snapshot.keys():
		var actor_id := str(id_variant)
		var state: FrontendActorRenderState = snapshot[actor_id]
		var hex := context.get_actor_hex_position(actor_id)
		var buff_ids: Array[String] = []
		for buff: FrontendBuffSummary in state.buffs:
			buff_ids.append(_canon_id(buff.id))
		var shield_ids: Array[String] = []
		for shield: FrontendShieldSummary in state.shields:
			shield_ids.append(_canon_id(shield.id))
		var line := "actor %s pos=(%d,%d) at=(%d,%d) hp=%s vhp=%d alive=%d buffs=[%s] shields=[%s]" % [
			_canon_id(actor_id), hex.q, hex.r, state.position.q, state.position.r,
			_num(state.target_hp), roundi(state.visual_hp), 1 if state.is_alive else 0,
			",".join(buff_ids), ",".join(shield_ids),
		]
		if prev.get(actor_id, "") != line:
			lines.append(line)
			prev[actor_id] = line


func _append_fx(lines: PackedStringArray) -> void:
	var parts: PackedStringArray = []
	var kinds := _fx.keys()
	kinds.sort()
	for kind_variant in kinds:
		var kind := str(kind_variant)
		var counts: Array = _fx[kind]
		if counts[0] > 0:
			parts.append("+%s=%d" % [kind, counts[0]])
		if counts[1] > 0:
			parts.append("-%s=%d" % [kind, counts[1]])
	if not _died.is_empty():
		parts.append("died=[%s]" % ",".join(_died))
	if not _spawned.is_empty():
		parts.append("spawned=[%s]" % ",".join(_spawned))
	if not parts.is_empty():
		lines.append("fx " + " ".join(parts))


func _num(value: float) -> String:
	return "%.2f" % value


# ========== 文件 ==========

func _dump_path(seed_value: int, suffix: String) -> String:
	return ProjectSettings.globalize_path(DUMP_DIR).path_join("seed_%d%s" % [seed_value, suffix])


func _write_dump(seed_value: int, dump: String, suffix: String) -> String:
	var dir := ProjectSettings.globalize_path(DUMP_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := _dump_path(seed_value, suffix)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write dump: %s" % path)
		return path
	file.store_string(dump)
	file.close()
	return path


func _load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _save_golden(doc: Dictionary) -> void:
	var file := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write golden: %s" % GOLDEN_PATH)
		return
	file.store_string(JSON.stringify(doc, "\t"))
	file.store_string("\n")
	file.close()
