## SkillPreviewProcedure - 技能预览战斗过程
##
## BattleProcedure 的 skill_preview 特化：不跑 ATB / AI / 胜负判定，按"多 actor
## 时间轴"模型施法 —— 每个 actor 一条 track, 每条 track 多个 keyframe
## (time_ms / ability_config / target_id)。tick 到达 keyframe.time_ms 时
## grant + activate, "所有 keyframe 已 fire 且无 executing instance 且无飞行
## 投射物"后 +POST_EXECUTION_TICKS 延迟关停。
## ability runtime tick 复用 HexBattleProcedure.tick_actor_ability_runtime；本类只替换
## 正式战斗里的"AI 决策并启动 action"阶段。
##
## 寄生在外部常驻 WorldGI 上 —— 不 GameWorld.destroy()，actor 生命周期归
## world 管，procedure 结束后可再次 start_battle。
##
## 触发语义: keyframe.time_ms <= world.get_logic_time() 即触发。time_ms<=0
## 的 keyframe 在 start() 末尾立即 drain, 让"第 0 帧 activate"在 tick_once
## 推进 logic_time 之前完成 —— 否则会延后 100ms 触发。
##
## 由 SkillPreviewWorldGI._create_battle_procedure 构造；setups 通过
## SkillPreviewWorldGI.queue_preview 预存。
class_name SkillPreviewProcedure
extends BattleProcedure


## 安全上限，防止死循环。
const MAX_TICKS := 500

## 技能 executing 清空后再 tick 的缓冲，等投射物落完 / 延迟伤害触发。
const POST_EXECUTION_TICKS := 10


# ========== 字段 ==========

# 原始 setups 副本，留作日志/诊断。运行时调度走 _pending_keyframes。
var _actor_setups: Array[Dictionary] = []
var _allow_empty_track: bool = false

# 待触发的 keyframe 队列, 按 (time_ms, actor_order, track_order) 升序。
# 每条 = {time_ms: int, actor_id: String, ability_config: AbilityConfig, target_id: String}
var _pending_keyframes: Array[Dictionary] = []
var _post_countdown: int = -1


# ========== 初始化 ==========

func _init(
	world: WorldGameplayInstance,
	participants: Array[Actor],
	actor_setups: Array[Dictionary],
	allow_empty_track: bool = false,
) -> void:
	super._init(world, participants)
	# duplicate(true) 防御调方后续 mutate 数组反向影响 procedure
	_actor_setups = actor_setups.duplicate(true)
	_allow_empty_track = allow_empty_track


# ========== 生命周期 ==========

## 走旧版 start_recording 路径保留 initial_actors / map_config，让
## FrontendBattleAnimator 消费 timeline dict 时 BattleRecord.from_dict 能正常构造。
func _start_recorder() -> void:
	if _recorder == null:
		return
	var world := _get_world() as HexWorldGameplayInstance
	var replay_map_config: Dictionary = {}
	if world != null and world.grid != null:
		replay_map_config = world.grid.to_config_dict()
	var actors: Array[Actor] = []
	for pid in _participant_ids:
		var a := _get_actor(pid)
		if a != null:
			actors.append(a)
	_recorder.start_recording(actors, {
		"positionFormats": {"Character": "hex", "Environment": "hex"},
	}, replay_map_config)


func start() -> void:
	super.start()
	var world := _get_world()
	if world == null:
		mark_finished()
		return

	# 1. Grant passives (一次性, 全部 actor)
	for setup in _actor_setups:
		var actor_id: String = setup.get("actor_id", "") as String
		var actor := world.get_actor(actor_id) as CharacterActor
		if actor == null:
			continue
		for passive_cfg in setup.get("passives", []) as Array:
			if passive_cfg != null and passive_cfg is AbilityConfig:
				actor.ability_set.grant_ability(Ability.new(passive_cfg, actor.get_id()), world)

	# 2. 平铺 keyframe 到 _pending_keyframes, 按 (time_ms, actor_order, track_order) 稳定排序。
	#    actor_order = setup 在 _actor_setups 里的 idx; track_order = keyframe 在 track 里的 idx。
	#    同 time_ms 用 (actor_order, track_order) 决定确定顺序 —— 不同 actor 同 time 是
	#    "确定顺序"而不是"真并发"。
	var flat: Array[Dictionary] = []
	for actor_idx in _actor_setups.size():
		var setup: Dictionary = _actor_setups[actor_idx]
		var actor_id: String = setup.get("actor_id", "") as String
		var track: Array = setup.get("track", []) as Array
		for kf_idx in track.size():
			var kf: Dictionary = track[kf_idx]
			flat.append({
				"time_ms": int(kf.get("time_ms", 0)),
				"actor_id": actor_id,
				"ability_config": kf.get("ability_config"),
				"target_id": String(kf.get("target_id", "")),
				"_actor_order": actor_idx,
				"_track_order": kf_idx,
			})
	flat.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["time_ms"] != b["time_ms"]:
			return a["time_ms"] < b["time_ms"]
		if a["_actor_order"] != b["_actor_order"]:
			return a["_actor_order"] < b["_actor_order"]
		return a["_track_order"] < b["_track_order"]
	)
	_pending_keyframes = flat

	# 3. 立即 drain time_ms<=0 的 keyframe, 让"第 0 帧 activate"在 tick_once 推进
	#    logic_time 之前完成 —— 否则首次 base_tick 后才触发, 实际落在 100ms。
	_fire_due_keyframes(0.0)


func tick_once() -> void:
	if _finished:
		return
	_current_tick += 1

	var world := _get_world() as HexWorldGameplayInstance
	if world != null:
		world.base_tick(_tick_interval)

	var cur_logic_time := world.get_logic_time() if world != null else float(_current_tick) * _tick_interval

	if world != null:
		world.broadcast_projectile_events()

	# 先 fire 已到时的 keyframe; activate event 在本帧内被 ability_set 接收, 接着的 tick_executions
	# 也会处理刚被 grant 的 ability。这样 t=0 keyframe 不会比"显式 grant" baseline 慢一帧。
	# 但 fire 前必须先把 tag_container 的 logic_time 同步到本帧, 否则 cooldown 到期边界会
	# 用上一帧时间做条件检查, 然后同帧稍后才过期。
	_sync_participant_tag_logic_time(cur_logic_time)
	_fire_due_keyframes(cur_logic_time)

	# 跑正式 hex battle 的 ability runtime tick；preview 只负责上面的 keyframe 调度。
	var any_ability_executing := false
	for actor in _get_alive_participants():
		if HexBattleProcedure.tick_actor_ability_runtime(actor, _tick_interval, cur_logic_time, world):
			any_ability_executing = true

	record_current_frame_events()

	if _current_tick >= MAX_TICKS:
		mark_finished()
		return

	# 结束判定: 待触发 keyframe 全部 fired + 无 executing + 无飞行投射物
	if _post_countdown < 0:
		var no_more_pending := _pending_keyframes.is_empty()
		var idle := no_more_pending and not any_ability_executing and not _any_projectile_flying(world)
		if idle:
			_post_countdown = POST_EXECUTION_TICKS
	else:
		_post_countdown -= 1
		if _post_countdown <= 0:
			mark_finished()


# ========== Virtual hooks ==========

func _mark_in_combat(actor_id: String, active: bool) -> void:
	var world := _get_world()
	if world == null:
		return
	var actor := world.get_actor(actor_id)
	if actor == null or not (actor is CharacterActor):
		return
	var cchar := actor as CharacterActor
	if cchar.ability_set == null:
		return
	if active:
		cchar.ability_set.add_loose_tag("in_combat")
	else:
		cchar.ability_set.remove_loose_tag("in_combat")


# ========== 内部工具 ==========

## drain 队首所有 time_ms <= now_ms 的 keyframe, 各自 grant + activate。
## 事件 logicTime 写 keyframe.time_ms (deterministic intent), 不写 now_ms;
## 例: keyframe time_ms=850, 实际在 now=900ms tick 触发, 事件 logicTime 仍记 850。
##
## 同 actor 同 ability_config 多 keyframe 复用同一 Ability instance: 第二次 fire 时
## find_ability_by_config_id 命中已 grant 的 instance 直接发 ABILITY_ACTIVATE_EVENT,
## 不再 Ability.new + grant_ability。这样:
## 1. cooldown tag (cooldown:<config_id>) 是 ability_set 级 owner-scoped, 多 instance
##    会互相干扰; 复用后 cooldown 行为与单 instance 一致, 严格遵守。
## 2. 不会重复 emit ABILITY_GRANTED_EVENT, 避免误触发监听 GRANTED_SELF 的 passive。
## UI 层已禁止把同 skill 排在间隔 < occupy 的窗口, procedure 不再二次拦截。
func _fire_due_keyframes(now_ms: float) -> void:
	var world := _get_world()
	while not _pending_keyframes.is_empty() and float(_pending_keyframes[0]["time_ms"]) <= now_ms:
		var kf: Dictionary = _pending_keyframes.pop_front()
		var actor_id: String = kf["actor_id"] as String
		var actor := _get_actor(actor_id) as CharacterActor
		if actor == null or actor.is_dead():
			continue
		var ability_cfg: AbilityConfig = kf["ability_config"]
		if ability_cfg == null:
			continue
		var ability := actor.ability_set.find_ability_by_config_id(ability_cfg.config_id)
		if ability == null:
			ability = Ability.new(ability_cfg, actor.get_id())
			actor.ability_set.grant_ability(ability, world)
		var event := {
			"kind": GameEvent.ABILITY_ACTIVATE_EVENT,
			"abilityInstanceId": ability.id,
			"sourceId": actor.get_id(),
			"logicTime": float(kf["time_ms"]),
		}
		var target_id: String = kf["target_id"] as String
		if target_id != "":
			event["target_actor_id"] = target_id
		actor.ability_set.receive_event(event, world)


func _sync_participant_tag_logic_time(now_ms: float) -> void:
	for actor in _get_alive_participants():
		actor.ability_set.tag_container.tick(0.0, now_ms)


func _get_alive_participants() -> Array[CharacterActor]:
	var result: Array[CharacterActor] = []
	for pid in _participant_ids:
		var actor := _get_actor(pid)
		if actor is CharacterActor and not (actor as CharacterActor).is_dead():
			result.append(actor as CharacterActor)
	return result


## 扫 world.get_actors() 里是否有飞行中的投射物。
func _any_projectile_flying(world: HexWorldGameplayInstance) -> bool:
	if world == null:
		return false
	for actor in world.get_actors():
		if actor is ProjectileActor and (actor as ProjectileActor).is_flying():
			return true
	return false
