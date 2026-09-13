## Smoke: 随机战斗 golden —— 固定 seed 的 headless 随机战斗（HexRandomDemoWorldGameplayInstance），
## 对归一化后的录像事件流 + loadout 摘要取 sha256 与 golden 比对，并断言这组 seed 合起来把 manifest 里的每个
## config 都真实跑到：主动技能（active_use + skill tag）要有 execution_activated，随机池被动要被装载过，
## 其余 config（buff / 图腾 / 火焰地块 / 内建被动）要有 execution / trigger / grant 任一证据。
##
## 归一化只吃两样：wall-clock 字段（recorded_at）与 *_id 键下的生成 id（按 key 排序遍历、首次出现序号化，
## 进程内多场连跑的 IdGenerator 计数不影响指纹）；其余逐字段进指纹——数值、顺序、时机、触发、胜负任一漂移都红。
## 有意的行为变化须先解释再重烤：godot --headless --path . <本场景> -- rebake
extends Node


const GOLDEN_PATH := "res://addons/logic-game-framework/example/hex-atb-battle/tests/battle/random_battle_golden.json"
const PASSIVES_PER_ACTOR := 1
## seed 集合是在 50 个 seed 的差分 dump 上按覆盖率贪心选出的 set cover。offensive_slots -1 = demo 原规则
## （3v3 全员进攻位），1 = 一位进攻、两位从全池抽——治疗 / 护盾 / 结界 / 涌动 / 姿态 / 图腾 / 净化 / 换位只在后者进场。
const RUNS: Array[Dictionary] = [
	{"seed": 571031, "offensive_slots": -1},
	{"seed": 671159, "offensive_slots": -1},
	{"seed": 900083, "offensive_slots": 1},
	{"seed": 900097, "offensive_slots": 1},
	{"seed": 900113, "offensive_slots": 1},
	{"seed": 900127, "offensive_slots": 1},
	{"seed": 900131, "offensive_slots": 1},
	{"seed": 900191, "offensive_slots": 1},
	{"seed": 900211, "offensive_slots": 1},
	{"seed": 900223, "offensive_slots": 1},
]
## 录像开始前就由 demo 世界挂给全员的 buff：每场都在，但录不到 grant，覆盖率不苛求它。
const PRE_RECORDING_GRANTS: Array[String] = ["buff_inspire"]
const VOLATILE_KEYS: Array[String] = ["recorded_at"]

var _id_regex := RegEx.new()


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	_id_regex.compile("^(?:[A-Za-z_]+_\\d+:)?[A-Za-z_]+_\\d+$")
	var rebake := OS.get_cmdline_user_args().has("rebake")
	var status := _run(rebake)
	GameWorld.shutdown()
	if status == "":
		print("SMOKE_TEST_RESULT: PASS - random battle golden unchanged over %d seeds, every manifest config exercised" % RUNS.size())
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_RESULT: FAIL - %s" % status)
		get_tree().quit(1)


func _run(rebake: bool) -> String:
	var golden := _load_golden()
	if not rebake and golden.is_empty():
		return "golden missing or unreadable: %s (run with -- rebake)" % GOLDEN_PATH
	var evidence := {"loaded": {}, "executed": {}, "triggered": {}, "granted": {}}
	var baked := {}
	var failures: Array[String] = []
	for run in RUNS:
		var seed_value := int(run["seed"])
		var offensive := int(run["offensive_slots"])
		var outcome := _play(seed_value, offensive)
		var replay: Dictionary = outcome["replay"]
		var summary: Dictionary = outcome["summary"]
		if replay.is_empty():
			return "seed %d produced no replay" % seed_value
		_collect_evidence(replay, summary, evidence)
		var digest := _fingerprint(replay, summary)
		var meta: Dictionary = replay.get("meta", {})
		var row := {
			"offensive_slots": offensive,
			"sha256": digest,
			"result": str(meta.get("result", "")),
			"frames": int(meta.get("total_frames", 0)),
			"events": _count_events(replay),
		}
		baked[str(seed_value)] = row
		print("RANDOM_GOLDEN seed=%d offensive=%d result=%s frames=%d events=%d sha=%s" % [
			seed_value, offensive, row["result"], row["frames"], row["events"], digest.substr(0, 12)])
		if rebake:
			continue
		var expected: Dictionary = (golden.get("runs", {}) as Dictionary).get(str(seed_value), {})
		if expected.is_empty():
			failures.append("seed %d has no golden entry" % seed_value)
		elif int(expected.get("offensive_slots", -2)) != offensive:
			failures.append("seed %d golden offensive_slots=%s but RUNS says %d" % [
				seed_value, str(expected.get("offensive_slots")), offensive])
		elif str(expected.get("sha256", "")) != digest:
			failures.append("seed %d fingerprint drift (result %s→%s, frames %s→%s, events %s→%s)" % [
				seed_value, str(expected.get("result")), row["result"], str(expected.get("frames")), row["frames"],
				str(expected.get("events")), row["events"]])
	var missing := _missing_coverage(evidence)
	if not missing.is_empty():
		failures.append("manifest configs without evidence: %s" % ", ".join(missing))
	if rebake:
		_save_golden({
			"generated_by": "smoke_random_battle_golden.gd",
			"passives_per_actor": PASSIVES_PER_ACTOR,
			"runs": baked,
		})
		print("REBAKED %d seeds -> %s" % [baked.size(), GOLDEN_PATH])
	return "; ".join(failures)


## 跑一场：logic only，不写日志 / 不落录像文件，只取内存里的录像与 loadout 摘要。
func _play(seed_value: int, offensive: int) -> Dictionary:
	GameWorld.shutdown()
	var battle := HexRandomDemoWorldGameplayInstance.new()
	GameWorld.create_instance(battle)
	battle.start({
		"random_seed": seed_value,
		"passives_per_actor": PASSIVES_PER_ACTOR,
		"offensive_slots": offensive,
		"logging": false,
		"recording": true,
		"save_replay": false,
	})
	for _i in range(HexBattleProcedure.MAX_TICKS + 1):
		GameWorld.tick_all(100.0)
		if not GameWorld.has_running_instances():
			break
	var replay := battle.get_replay_data()
	var summary := battle.get_random_summary()
	GameWorld.shutdown()
	return {"replay": replay, "summary": summary}


# ========== 覆盖率 ==========

func _collect_evidence(replay: Dictionary, summary: Dictionary, evidence: Dictionary) -> void:
	for actor in summary.get("actors", []):
		evidence["loaded"][str(actor.get("active_skill", ""))] = true
		for passive in actor.get("passives", []):
			evidence["loaded"][str(passive)] = true
	for frame in replay.get("timeline", []):
		for ev in frame.get("events", []):
			var kind := str(ev.get("kind", ""))
			if kind == "execution_activated":
				evidence["executed"][str(ev.get("ability_config_id", ""))] = true
			elif kind == "ability_triggered":
				evidence["triggered"][str(ev.get("ability_config_id", ""))] = true
			elif kind == "ability_granted":
				_collect_config_ids(ev, evidence["granted"])


## ability_granted 的 payload 嵌着序列化的 ability：递归收所有 config_id。
func _collect_config_ids(value: Variant, into: Dictionary) -> void:
	if value is Dictionary:
		var dict := value as Dictionary
		if dict.has("config_id"):
			into[str(dict["config_id"])] = true
		for child in dict.values():
			_collect_config_ids(child, into)
	elif value is Array:
		for child in value:
			_collect_config_ids(child, into)


func _missing_coverage(evidence: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for cfg in HexBattleAllSkills.all_abilities():
		var cid := cfg.config_id
		if PRE_RECORDING_GRANTS.has(cid):
			continue
		var has_active_use := not cfg.get_active_use_configs().is_empty()
		if has_active_use and cfg.ability_tags.has("skill"):
			if not evidence["executed"].has(cid):
				missing.append(cid + "(no execution)")
		elif _is_random_passive(cfg):
			if not evidence["loaded"].has(cid):
				missing.append(cid + "(never loaded)")
		elif not (evidence["executed"].has(cid) or evidence["triggered"].has(cid) or evidence["granted"].has(cid)):
			missing.append(cid + "(no evidence)")
	return missing


## 与 HexRandomDemoWorldGameplayInstance._is_passive_loadout_config 同一条过滤（随机被动池）。
func _is_random_passive(cfg: AbilityConfig) -> bool:
	if not cfg.get_active_use_configs().is_empty():
		return false
	if not cfg.ability_tags.has("passive"):
		return false
	for tag in ["intrinsic", "totem", "fire_tile", "lifetime"]:
		if cfg.ability_tags.has(tag):
			return false
	return true


# ========== 指纹 ==========

func _fingerprint(replay: Dictionary, summary: Dictionary) -> String:
	var doc := {"replay": replay, "summary": summary}
	var mapping := {}
	_collect_ids(doc, mapping, "")
	return JSON.stringify(_canon(doc, mapping, "")).sha256_text()


func _count_events(replay: Dictionary) -> int:
	var total := 0
	for frame in replay.get("timeline", []):
		total += (frame.get("events", []) as Array).size()
	return total


## 生成 id 只认 *_id / id 键下的值（ability_52、execution_75、demo_0:Character_3、battle_74 …），
## 按 key 排序遍历、首次出现序号化成「前缀#序号」；config id / kind / tag 这类语义串不动。
func _collect_ids(value: Variant, mapping: Dictionary, key: String) -> void:
	if value is Dictionary:
		var dict := value as Dictionary
		var keys := dict.keys()
		keys.sort()
		for k in keys:
			if VOLATILE_KEYS.has(str(k)):
				continue
			_collect_ids(dict[k], mapping, str(k))
	elif value is Array:
		for child in value:
			_collect_ids(child, mapping, key)
	elif value is String and _is_id_key(key) and not mapping.has(value) and _id_regex.search(value) != null:
		var prefix := _id_prefix(value)
		var count := 0
		for canon_id in mapping.values():
			if str(canon_id).begins_with(prefix + "#"):
				count += 1
		mapping[value] = "%s#%d" % [prefix, count + 1]


func _canon(value: Variant, mapping: Dictionary, key: String) -> Variant:
	if value is Dictionary:
		var dict := value as Dictionary
		var out := {}
		var keys := dict.keys()
		keys.sort()
		for k in keys:
			if VOLATILE_KEYS.has(str(k)):
				continue
			out[k] = _canon(dict[k], mapping, str(k))
		return out
	if value is Array:
		var arr := []
		for child in value:
			arr.append(_canon(child, mapping, key))
		return arr
	if value is String and _is_id_key(key) and mapping.has(value):
		return mapping[value]
	return value


func _is_id_key(key: String) -> bool:
	return key == "id" or key.ends_with("_id") or key.ends_with("_ids")


func _id_prefix(id: String) -> String:
	var prefixes: Array[String] = []
	for part in id.split(":"):
		prefixes.append(part.substr(0, part.rfind("_")))
	return ":".join(prefixes)


# ========== golden 文件 ==========

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
