class_name HexBattleSkillScenarioHarness
extends RefCounted
## HexBattle 技能场景测试 harness
##
## 最小化战斗容器，用于 headless skill scenario / smoke 验证。
## _PreviewInstance: 自管 left_team / right_team / recorder, 不走 ATB/AI/procedure。
## - start() 承担全部初始化（地图/角色/投射物/录像）
## - run_with_actions() 只关注：创建场景 → 按时间施法 → 收集 replay/result


## 安全上限，防止技能执行死循环
const MAX_TICKS := 500

## tick 时间步长（与 HexBattleProcedure 一致）
const TICK_INTERVAL := 100.0

## 技能执行完成后的额外等待帧数（等待投射物落地等）
const POST_EXECUTION_TICKS := 10


## 从已编译 AbilityConfig + 场景 dict 跑一次 preview，返回结构化结果
##
## 消费者: addon 内 `tests/example/hex-atb-battle/skill_scenarios/` scenario runner
## 与相关 headless smoke。
##
## scene_config 约定格式:
## [codeblock]
## {
##   "map": { "rows": int, "cols": int } | { "radius": int },
##   "caster": { "class": String, "pos": [q, r], "hp": float?, "atk": float? },
##   "caster_passives": Array[AbilityConfig],
##   "allies":  [{ "class": ..., "pos": [q, r], "hp": float? }, ...],
##   "enemies": [{ "class": ..., "pos": [q, r], "hp": float? }, ...],
##   "target":  { "mode": "auto"|"enemy_index"|"ally_index", "index": int? }
## }
## [/codeblock]
##
## 返回:
## [codeblock]
## {
##   "success": bool,
##   "replay":    Dictionary,       # BattleRecorder.stop_recording 产出
##   "caster_id": String,
##   "ally_ids":  Array[String],    # 不含 caster
##   "enemy_ids": Array[String],
##   "errors":    Array[String],
## }
## [/codeblock]
static func run_with_config(
	ability_config: AbilityConfig,
	scene_config: Dictionary,
	max_ticks: int = MAX_TICKS
) -> Dictionary:
	if ability_config == null:
		return _empty_result(["ability_config is null"])
	# 单步 shim：caster 施放 ability_config,target 来自 scene_config.target(默认 auto)
	var target_cfg: Dictionary = scene_config.get("target", {"mode": "auto"})
	var target_ref := _target_cfg_to_ref(target_cfg)
	var actions: Array[Dictionary] = [{
		"caster": "caster",
		"skill": ability_config,
		"target": target_ref,
	}]
	return run_with_actions(scene_config, actions, max_ticks)


## 多步 action 序列版本。一个 action 描述 "谁在何时施放什么技能打谁"。
##
## 适合:反伤/尸爆等被动触发场景(让 enemy 来施放 Strike 打 caster)、多单位协同场景、
## 时序 combo (caster t=0 + caster t=600 + enemy t=300 等)。
##
## action 字典格式:
## [codeblock]
## {
##   "caster":  "caster" | "ally_<N>" | "enemy_<N>",          # 默认 "caster"
##   "skill":   AbilityConfig,                                 # 必填
##   "target":  "auto" | "caster" | "ally_<N>" | "enemy_<N>",  # 默认 "auto"
##   "time_ms": int,                                           # 默认 0; <=0 在 tick 开始前立即触发
## }
## [/codeblock]
##
## 调度语义: time_ms <= battle.get_logic_time() 触发, 与 SkillPreviewProcedure 对齐;
## time_ms<=0 在 tick 开始前一次性 grant+activate (第 0 帧施法 → 第 1 帧首次 tick 命中)。
## time_ms>0 进 pending 队列, 每帧 battle.tick 后 drain 已到时项 (在那个 tick 的
## frame_events 里能看到 ABILITY_ACTIVATE_EVENT, 对应技能效果落在下一帧或之后)。
##
## 返回结构与 run_with_config 相同。
static func run_with_actions(
	scene_config: Dictionary,
	actions: Array[Dictionary],
	max_ticks: int = MAX_TICKS
) -> Dictionary:
	var errors: Array[String] = []

	GameWorld.init()

	var preview_config := _build_preview_config(scene_config)
	var battle := GameWorld.create_instance(func() -> GameplayInstance:
		var inst := _PreviewInstance.new()
		inst.start(preview_config)
		return inst
	) as _PreviewInstance

	if battle == null:
		GameWorld.destroy()
		return _empty_result(["Failed to create preview battle instance"])

	var caster: CharacterActor = battle.left_team[0]
	var ally_actors: Array[CharacterActor] = []
	var enemy_actors: Array[CharacterActor] = []
	for actor in battle.right_team:
		if actor.get_team_id() == caster.get_team_id():
			ally_actors.append(actor as CharacterActor)
		else:
			enemy_actors.append(actor as CharacterActor)

	# Grant caster 的 passives(只挂 caster,需要挂其他 actor 的被动请用 actor_passives 扩展)
	var passives: Array = scene_config.get("caster_passives", [])
	for passive_config in passives:
		if passive_config is AbilityConfig:
			var passive_ability := Ability.new(passive_config, caster.get_id())
			caster.ability_set.grant_ability(passive_ability, battle)

	# 把 actions 拆成 t<=0 (立即) + 其余 (pending 队列, 按 time_ms+原始 idx 稳定排序)。
	# 每条 pending 项 = {time_ms, action_caster, ability_config, target_id}
	# action_caster 提前解析: 编辑期 actor 数量稳定, 不会中途消失。
	var pending: Array[Dictionary] = []
	for action_idx in actions.size():
		var action: Dictionary = actions[action_idx]
		var caster_ref := str(action.get("caster", "caster"))
		var skill_config := action.get("skill") as AbilityConfig
		var target_ref := str(action.get("target", "auto"))
		var time_ms: int = int(action.get("time_ms", 0))
		if skill_config == null:
			errors.append("action missing skill AbilityConfig: %s" % str(action))
			continue
		var action_caster := _resolve_actor_ref(caster_ref, caster, ally_actors, enemy_actors)
		if action_caster == null:
			errors.append("action caster ref unresolved: %s" % caster_ref)
			continue
		var action_target_id := _resolve_target_ref(
			target_ref, action_caster, caster, ally_actors, enemy_actors, battle.environments
		)
		if time_ms <= 0:
			_fire_action(battle, action_caster, skill_config, action_target_id, 0.0)
		else:
			pending.append({
				"time_ms": time_ms,
				"_idx": action_idx,
				"action_caster": action_caster,
				"ability_config": skill_config,
				"target_id": action_target_id,
			})

	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["time_ms"] != b["time_ms"]:
			return a["time_ms"] < b["time_ms"]
		return a["_idx"] < b["_idx"]
	)

	# Tick 循环 —— 顺序对齐 SkillPreviewProcedure.tick_once:
	#   base_tick 推进 logic_time → fire 已到时 keyframe → ability tick + tick_executions → record。
	# fire 必须在 ability tick 之前, 否则刚 grant 的 ability 要等下帧才跑首次 tick,
	# 与真实 procedure 行为偏差 1 个 execution tick。
	var tick_count := 0
	var post_execution_countdown := -1
	while tick_count < max_ticks:
		tick_count += 1
		battle.tick(TICK_INTERVAL)

		var cur_logic_time := battle.get_logic_time()
		_sync_all_actor_tag_logic_time(battle, cur_logic_time)
		while not pending.is_empty() and float(pending[0]["time_ms"]) <= cur_logic_time:
			var kf: Dictionary = pending.pop_front()
			_fire_action(
				battle,
				kf["action_caster"] as CharacterActor,
				kf["ability_config"] as AbilityConfig,
				kf["target_id"] as String,
				float(kf["time_ms"]),
			)

		for actor in battle.get_all_actors():
			actor.ability_set.tick(TICK_INTERVAL, cur_logic_time)
			actor.ability_set.tick_executions(TICK_INTERVAL, battle)

		var frame_events := GameWorld.event_collector.flush()
		battle.recorder.record_frame(tick_count, frame_events)

		if post_execution_countdown < 0:
			# 判定"结束":
			#   1. 所有 CharacterActor 的 ability 都没有 executing instance(cover DOT/HOT loop)
			#   2. 场上没有飞行中的 projectile(cover 投射物命中前的飞行阶段)
			#   3. pending 队列空 (cover 还没到点的 schedule)
			# 用 battle.get_actors() (registry) 而非 get_all_actors() (staging)
			var still_executing := false
			if not pending.is_empty():
				still_executing = true
			else:
				for actor in battle.get_actors():
					if actor is ProjectileActor:
						if (actor as ProjectileActor).is_flying():
							still_executing = true
							break
						continue
					if not (actor is CharacterActor):
						continue
					for ability in (actor as CharacterActor).ability_set.get_abilities():
						if ability.is_expired():
							continue
						if ability.get_executing_instances().size() > 0:
							still_executing = true
							break
					if still_executing:
						break
			if not still_executing:
				post_execution_countdown = POST_EXECUTION_TICKS
		else:
			post_execution_countdown -= 1
			if post_execution_countdown <= 0:
				break

	var end_reason := "preview_complete" if tick_count < max_ticks else "timeout"
	var replay_data := battle.recorder.stop_recording(end_reason)

	var caster_id := caster.get_id()
	var ally_ids: Array[String] = []
	for a in ally_actors:
		ally_ids.append(a.get_id())
	var enemy_ids: Array[String] = []
	for e in enemy_actors:
		enemy_ids.append(e.get_id())
	var environment_ids: Array[String] = []
	for env in battle.environments:
		environment_ids.append(env.get_id())

	# grant/revoke 不经 event_collector,在 destroy 前抓 ability 状态 + hp 快照
	var final_ability_states: Dictionary = {}
	var final_actor_hps: Dictionary = {}
	for actor in battle.get_all_actors():
		if not (actor is CharacterActor):
			continue
		var c_actor := actor as CharacterActor
		var config_ids: Array[String] = []
		for ability in c_actor.ability_set.get_abilities():
			if not ability.is_expired():
				config_ids.append(ability.config_id)
		final_ability_states[c_actor.get_id()] = config_ids
		final_actor_hps[c_actor.get_id()] = c_actor.attribute_set.hp

	# 死者也加到 final_actor_hps(check_death 会 remove_actor,得从 ally/enemy_ids 补)
	for aid in ally_ids + enemy_ids + [caster_id]:
		if not final_actor_hps.has(aid):
			final_actor_hps[aid] = 0.0

	GameWorld.destroy()

	if tick_count >= max_ticks:
		errors.append("Preview timed out after %d ticks" % max_ticks)

	return {
		"success": errors.is_empty(),
		"replay": replay_data,
		"caster_id": caster_id,
		"ally_ids": ally_ids,
		"enemy_ids": enemy_ids,
		"environment_ids": environment_ids,
		"final_ability_states": final_ability_states,
		"final_actor_hps": final_actor_hps,
		"errors": errors,
	}


## Grant ability 给 action_caster + receive ABILITY_ACTIVATE_EVENT。
## logic_time 写 keyframe 自身的 time_ms (deterministic intent), 与
## SkillPreviewProcedure._fire_due_keyframes 对齐。
static func _fire_action(
	battle: _PreviewInstance,
	action_caster: CharacterActor,
	ability_config: AbilityConfig,
	target_id: String,
	keyframe_time_ms: float,
) -> void:
	var ability := Ability.new(ability_config, action_caster.get_id())
	action_caster.ability_set.grant_ability(ability, battle)
	var activate_event := {
		"kind": GameEvent.ABILITY_ACTIVATE_EVENT,
		"abilityInstanceId": ability.id,
		"sourceId": action_caster.get_id(),
		"logicTime": keyframe_time_ms,
	}
	if target_id != "":
		activate_event["target_actor_id"] = target_id
	action_caster.ability_set.receive_event(activate_event, battle)


static func _sync_all_actor_tag_logic_time(battle: _PreviewInstance, now_ms: float) -> void:
	for actor in battle.get_all_actors():
		actor.ability_set.tag_container.tick(0.0, now_ms)


static func _empty_result(errs: Array) -> Dictionary:
	var typed_errs: Array[String] = []
	for e in errs:
		typed_errs.append(str(e))
	return {
		"success": false,
		"replay": {},
		"caster_id": "",
		"ally_ids": [] as Array[String],
		"enemy_ids": [] as Array[String],
		"environment_ids": [] as Array[String],
		"final_ability_states": {},
		"final_actor_hps": {},
		"errors": typed_errs,
	}


## 把 scene_config.target dict 转成 action target_ref 字符串
static func _target_cfg_to_ref(target_cfg: Dictionary) -> String:
	var mode: String = target_cfg.get("mode", "auto")
	match mode:
		"enemy_index":
			return "enemy_%d" % int(target_cfg.get("index", 0))
		"ally_index":
			return "ally_%d" % int(target_cfg.get("index", 0))
		"environment_index":
			return "environment_%d" % int(target_cfg.get("index", 0))
		_:
			return "auto"


## 解析 actor ref ("caster" / "ally_N" / "enemy_N") → 具体 CharacterActor
static func _resolve_actor_ref(
	ref: String,
	caster: CharacterActor,
	ally_actors: Array[CharacterActor],
	enemy_actors: Array[CharacterActor]
) -> CharacterActor:
	if ref == "caster":
		return caster
	if ref.begins_with("ally_"):
		var idx := int(ref.substr(5))
		if idx >= 0 and idx < ally_actors.size():
			return ally_actors[idx]
	if ref.begins_with("enemy_"):
		var idx := int(ref.substr(6))
		if idx >= 0 and idx < enemy_actors.size():
			return enemy_actors[idx]
	return null


## 解析 target ref → actor id 字符串("auto" 相对于 action 施法者找最近敌人)
##
## environments 参数: 让 smoke / scenario 能用 "environment_N" 引用墙等环境物作为 target;
## 仅 smoke 路径用, 生产代码 (AI / 玩家 cast) 走 can_use_skill_on() 自己挑目标。
static func _resolve_target_ref(
	ref: String,
	action_caster: CharacterActor,
	scene_caster: CharacterActor,
	ally_actors: Array[CharacterActor],
	enemy_actors: Array[CharacterActor],
	environments: Array[EnvironmentActor]
) -> String:
	if ref == "auto":
		# action_caster 的敌方列表 = 所有非同队
		var candidates: Array[CharacterActor] = []
		for a in [scene_caster] + ally_actors + enemy_actors:
			if a.get_team_id() != action_caster.get_team_id():
				candidates.append(a)
		var best: CharacterActor = null
		var best_dist: int = 999999
		for c in candidates:
			var dist := action_caster.hex_position.distance_to(c.hex_position)
			if dist < best_dist:
				best_dist = dist
				best = c
		return best.get_id() if best != null else ""
	if ref.begins_with("environment_"):
		var env_idx := int(ref.substr(12))
		if env_idx >= 0 and env_idx < environments.size():
			return environments[env_idx].get_id()
		return ""
	var resolved := _resolve_actor_ref(ref, scene_caster, ally_actors, enemy_actors)
	return resolved.get_id() if resolved != null else ""


static func _build_preview_config(scene_config: Dictionary) -> Dictionary:
	var map_cfg: Dictionary = scene_config.get("map", {"rows": 5, "cols": 5})
	var grid_config := GridMapConfig.new()
	grid_config.grid_type = GridMapConfig.GridType.HEX
	grid_config.size = map_cfg.get("size", 10.0) as float
	# 读 orientation, 默认 FLAT。接受 string ("flat"/"pointy") 或 enum int。
	var orient_val: Variant = map_cfg.get("orientation", "flat")
	if orient_val is String:
		grid_config.orientation = (
			GridMapConfig.Orientation.POINTY if (orient_val as String) == "pointy"
			else GridMapConfig.Orientation.FLAT
		)
	else:
		grid_config.orientation = int(orient_val) as GridMapConfig.Orientation
	if map_cfg.has("radius"):
		grid_config.draw_mode = GridMapConfig.DrawMode.RADIUS
		grid_config.radius = map_cfg.get("radius") as int
	else:
		grid_config.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		grid_config.rows = map_cfg.get("rows", 5) as int
		grid_config.columns = map_cfg.get("cols", map_cfg.get("columns", 5)) as int

	var caster_src: Dictionary = scene_config.get("caster", {})
	var caster_cfg := _actor_src_to_preview_cfg(caster_src)

	var dummies_cfg: Array = []
	var allies: Array = scene_config.get("allies", [])
	for i in range(allies.size()):
		var cfg := _actor_src_to_preview_cfg(allies[i] as Dictionary)
		cfg["team"] = "A"  # 与 caster 同队
		cfg["id"] = "ally_%d" % i
		dummies_cfg.append(cfg)
	var enemies: Array = scene_config.get("enemies", [])
	for i in range(enemies.size()):
		var cfg := _actor_src_to_preview_cfg(enemies[i] as Dictionary)
		cfg["team"] = "B"
		cfg["id"] = "enemy_%d" % i
		dummies_cfg.append(cfg)

	# 环境物 (M1: stone_wall 起步)。scenario 格式: [{"type": "stone_wall", "pos": [q, r]}]
	var environment_cfgs: Array = []
	var env_src: Array = scene_config.get("environment", [])
	for env_entry in env_src:
		if not (env_entry is Dictionary):
			continue
		var entry: Dictionary = env_entry
		var pos_val: Variant = entry.get("pos", [0, 0])
		var q := 0
		var r := 0
		if pos_val is Array and (pos_val as Array).size() >= 2:
			q = (pos_val as Array)[0] as int
			r = (pos_val as Array)[1] as int
		environment_cfgs.append({
			"type": entry.get("type", "stone_wall"),
			"pos": {"q": q, "r": r},
		})

	return {
		"map_config": grid_config,
		"caster": caster_cfg,
		"dummies": dummies_cfg,
		"environment": environment_cfgs,
	}


static func _actor_src_to_preview_cfg(src: Dictionary) -> Dictionary:
	var pos_val: Variant = src.get("pos", [0, 0])
	var q := 0
	var r := 0
	if pos_val is Array and (pos_val as Array).size() >= 2:
		q = (pos_val as Array)[0] as int
		r = (pos_val as Array)[1] as int
	var attrs: Dictionary = {}
	if src.has("hp"):
		attrs["hp"] = src.get("hp")
		attrs["max_hp"] = src.get("hp")
	if src.has("atk"):
		attrs["atk"] = src.get("atk")
	return {
		"class": src.get("class", "WARRIOR"),
		"position": {"q": q, "r": r},
		"attributes": attrs,
	}


# ========== 内部 Battle Instance ==========

## Headless scenario 用轻量 world instance: 自拼 grid/projectile/actor/recorder,
## 不走 procedure 的 ATB/AI/队伍流程。
class _PreviewInstance extends HexWorldGameplayInstance:

	## Harness 外部直接读 battle.left_team[0] / battle.right_team。
	var left_team: Array[CharacterActor] = []
	var right_team: Array[CharacterActor] = []

	## 环境物 actor (StoneWall 等), 与 character 分开 staging,
	## 用于 scenario 断言"墙没受影响"等。
	var environments: Array[EnvironmentActor] = []

	## 不走 procedure 路径, 自管。
	var recorder: BattleRecorder = null

	var _projectile_system: ProjectileSystem = null

	func _init() -> void:
		super._init(IdGenerator.generate("preview"))
		type = "skill_preview"

	## 承担全部初始化：地图/投射物/timeline/角色/录像
	func start(config: Dictionary = {}) -> void:
		_state = "running"

		# 地图
		var grid_config: GridMapConfig = config.get("map_config")
		if grid_config != null:
			UGridMap.configure(grid_config)

		# 投射物系统
		var collision_detector := MobaCollisionDetector.new()
		_projectile_system = ProjectileSystem.new(
			collision_detector, GameWorld.event_collector, false
		)
		add_system(_projectile_system)

		# Timeline 注册
		HexBattleAllSkills.register_all_timelines()

		# 创建角色 → 放入 left_team / right_team
		var caster_cfg: Dictionary = config.get("caster", {})
		var dummies_cfg: Array = config.get("dummies", [])

		var caster := _create_actor(caster_cfg, 0, "caster")
		left_team = [caster]

		for i in range(dummies_cfg.size()):
			var dcfg: Dictionary = dummies_cfg[i]
			var team_int := 1 if dcfg.get("team", "B") == "B" else 0
			var did: String = dcfg.get("id", "dummy_%d" % (i + 1))
			var dummy := _create_actor(dcfg, team_int, did)
			right_team.append(dummy)

		# 环境物 (M1: StoneWall 起步)。格式: [{"type": "stone_wall", "pos": {"q": 2, "r": 0}}]
		var env_cfgs: Array = config.get("environment", [])
		for ecfg_var in env_cfgs:
			if not (ecfg_var is Dictionary):
				continue
			var env_actor := _create_environment(ecfg_var as Dictionary)
			if env_actor != null:
				environments.append(env_actor)

		# 录像
		recorder = BattleRecorder.new({
			"battleId": id,
			"tickInterval": int(HexBattleSkillScenarioHarness.TICK_INTERVAL),
		})
		var replay_map_config: Dictionary = {}
		if UGridMap.model != null:
			replay_map_config = UGridMap.model.to_config_dict()
		var all_actors: Array[Actor] = []
		for c in left_team:
			all_actors.append(c)
		for c in right_team:
			all_actors.append(c)
		for e in environments:
			all_actors.append(e)
		recorder.start_recording(all_actors, {
			"positionFormats": { "Character": "hex", "Environment": "hex" }
		}, replay_map_config)

	## 创建环境物 actor 并放入 grid。M1 仅支持 stone_wall。
	## cfg 格式: {"type": "stone_wall", "pos": {"q": q, "r": r}}
	func _create_environment(cfg: Dictionary) -> EnvironmentActor:
		var env_type: String = cfg.get("type", "")
		if env_type != HexBattleStoneWall.KIND:
			push_warning("[SkillScenarioHarness] 未知 environment type: %s" % env_type)
			return null
		var env_actor := HexBattleStoneWall.create()
		add_actor(env_actor)
		var pos: Dictionary = cfg.get("pos", {})
		var coord := HexCoord.new(pos.get("q", 0) as int, pos.get("r", 0) as int)
		var placed := UGridMap.model != null and UGridMap.model.place_occupant(coord, env_actor)
		if not placed:
			remove_actor(env_actor.get_id())
			push_warning("[SkillScenarioHarness] environment 放置失败: %s @ (%d, %d)" % [
				env_type, coord.q, coord.r
			])
			return null
		env_actor.hex_position = coord.duplicate()
		return env_actor


	func _create_actor(cfg: Dictionary, team_id: int, id_hint: String) -> CharacterActor:
		var class_str: String = cfg.get("class", "WARRIOR")
		var char_class := HexBattleClassConfig.string_to_class(class_str)
		var actor := CharacterActor.new(char_class)
		actor._display_name = cfg.get("displayName", id_hint)
		add_actor(actor)
		actor.set_team_id(team_id)
		# 属性
		var attrs: Dictionary = cfg.get("attributes", {})
		var max_hp: float = attrs.get("maxHp", attrs.get("max_hp", 100.0)) as float
		actor.attribute_set.set_max_hp_base(max_hp)
		actor.attribute_set.set_hp_base(attrs.get("hp", max_hp) as float)
		if attrs.has("atk"):
			actor.attribute_set.set_atk_base(attrs.get("atk") as float)
		# 位置
		var pos: Dictionary = cfg.get("position", {})
		var coord := HexCoord.new(pos.get("q", 0) as int, pos.get("r", 0) as int)
		UGridMap.model.place_occupant(coord, actor)
		actor.hex_position = coord.duplicate()
		return actor

	## projectile_hit 必须从 event_collector 广播出去, 否则 Fireball/PreciseShot
	## 的 ActivateInstanceConfig(trigger=PROJECTILE_HIT_EVENT) 收不到事件。
	func tick(dt: float) -> void:
		base_tick(dt)
		broadcast_projectile_events()

	## 走 left_team + right_team staging, 不走 actor registry。
	func get_all_actors() -> Array[CharacterActor]:
		var result: Array[CharacterActor] = []
		result.append_array(left_team)
		result.append_array(right_team)
		return result

	func get_alive_actors() -> Array[CharacterActor]:
		var result: Array[CharacterActor] = []
		for actor in get_all_actors():
			if not actor.is_dead():
				result.append(actor)
		return result
