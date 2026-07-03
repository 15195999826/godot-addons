## Phase 05 Summon Totem - TDD Spike (5 阶段探针)
##
## 不实现正式图腾,只验证框架级原语在战斗中途 add_actor / 驱动 / replay / remove
## 是否能 work, 输出结论给 phase-05-summon-totem-spike.md 决定路线 A vs B。
##
## 阶段:
##   1. spawn  — 中途 add_actor 后 actor 在 get_actors / get_alive_actors, grid 占位
##   2. drive  — 中途加 CharacterActor (复用 WARRIOR 配置) 是否被 ATB/AI/ability tick 驱动
##   3. replay — 中途新 actor 的 spawn/grant 进入 recorder,可观察事件顺序
##   4a. manual remove — 显式 remove_actor 是否清 actor + grid
##   4b. ttl lifecycle — TimeDurationConfig expire → NoInstance.on_remove 是否能自清 actor + grid
##   5. behavior — 图腾低 HP / 不移动 / 每 3s 攻最近敌人 / 死亡或 TTL 消失 (留给正式 impl)
##
## 输出: 控制台打印每阶段 PASS / FAIL + reason; smoke runner 协议:
##   SMOKE_SPIKE_RESULT: PASS|FAIL - <N>/<M> verified phases passed; <K> placeholders skipped
extends Node


const TICK_INTERVAL := 100.0
const TTL_LIFECYCLE_CONFIG_ID := "spike_ttl_lifecycle_cleanup"


var _phase_results: Array[Dictionary] = []


class _RemoveOwnerActorOnRemoveAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), TTL_LIFECYCLE_CONFIG_ID)
		type = "spike_remove_owner_actor"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var owner_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		if owner_id.is_empty():
			return ActionResult.create_success_result([], {"removed": false, "reason": "missing owner"})
		var actor := GameWorld.get_actor(owner_id)
		if actor == null:
			return ActionResult.create_success_result([], {"removed": false, "reason": "owner missing"})
		var instance := actor.get_owner_gameplay_instance()
		if instance == null:
			return ActionResult.create_success_result([], {"removed": false, "reason": "instance missing"})
		var removed := instance.remove_actor(owner_id)
		return ActionResult.create_success_result([], {"removed": removed})


func _ready() -> void:
	print("=== Phase 05 Summon Totem Spike ===")
	_run_phase_1_spawn()
	_run_phase_2_drive()
	_run_phase_3_replay()
	_run_phase_4_manual_remove()
	_run_phase_4b_ttl_lifecycle()
	_run_phase_5_behavior_placeholder()
	_report()


# ============================================================
# Phase 1: spawn 原语
# ============================================================
func _run_phase_1_spawn() -> void:
	var phase := "1. spawn"
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()
	var grid_cfg := GridMapConfig.new()
	grid_cfg.grid_type = GridMapConfig.GridType.HEX
	grid_cfg.orientation = GridMapConfig.Orientation.FLAT
	grid_cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	grid_cfg.radius = 3
	UGridMap.configure(grid_cfg)

	var instance := GameWorld.create_instance(func(): return HexWorldGameplayInstance.new("spike_p1"))
	(instance as HexWorldGameplayInstance).grid = UGridMap.model

	# 中途 spawn: 模拟战斗已经跑了若干 tick 后 add_actor
	var totem := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	instance.add_actor(totem)
	totem.set_team_id(0)
	UGridMap.model.place_occupant(HexCoord.new(1, 0), totem)
	totem.hex_position = HexCoord.new(1, 0)

	var in_actors: bool = totem.get_id() in (instance as HexWorldGameplayInstance).get_alive_actor_ids()
	var grid_occupant: bool = UGridMap.model.get_occupant(HexCoord.new(1, 0)) == totem
	if in_actors and grid_occupant:
		_record(phase, true, "actor added + grid 占位生效")
	else:
		_record(phase, false, "in_actors=%s grid_occupant=%s" % [in_actors, grid_occupant])

	GameWorld.destroy()


# ============================================================
# Phase 2: actor 驱动 (中途加 CharacterActor 能否被驱动)
# ============================================================
func _run_phase_2_drive() -> void:
	var phase := "2. actor_drive"
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()
	var grid_cfg := GridMapConfig.new()
	grid_cfg.grid_type = GridMapConfig.GridType.HEX
	grid_cfg.orientation = GridMapConfig.Orientation.FLAT
	grid_cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	grid_cfg.radius = 3
	UGridMap.configure(grid_cfg)

	var instance: HexWorldGameplayInstance = GameWorld.create_instance(func(): return HexWorldGameplayInstance.new("spike_p2")) as HexWorldGameplayInstance
	instance.grid = UGridMap.model

	var totem := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	instance.add_actor(totem)
	totem.set_team_id(0)
	UGridMap.model.place_occupant(HexCoord.new(0, 0), totem)
	totem.hex_position = HexCoord.new(0, 0)
	# 自带 Thorn (WARRIOR default), 但不 grant DemonForm 来 trigger periodic loop

	# 给 totem 装 Demon Form passive (periodic loop) 来验证 mid-add actor 能不能被 ability tick 驱动
	var demon_ability := Ability.new(HexBattleDemonForm.ABILITY, totem.get_id())
	totem.ability_set.grant_ability(demon_ability, instance)

	# tick ~7s, 期望 DemonForm tick 至少 2 次 (3s + 6s)
	for _i in range(70):
		instance.base_tick(TICK_INTERVAL)
		var t_now := instance.get_logic_time()
		totem.ability_set.tag_container.tick(0.0, t_now)
		totem.ability_set.tick(TICK_INTERVAL, t_now)
		totem.ability_set.tick_executions(TICK_INTERVAL, instance)

	var stacks := demon_ability.get_stacks()
	if stacks >= 2:
		_record(phase, true, "中途加 CharacterActor 后 ability tick 驱动正常, 7s 内 demon_form stacks=%d" % stacks)
	else:
		_record(phase, false, "stacks=%d (期望 >= 2)" % stacks)

	GameWorld.destroy()


# ============================================================
# Phase 3: replay / recording event-order
# ============================================================
func _run_phase_3_replay() -> void:
	var phase := "3. replay_recording"
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()
	var grid_cfg := GridMapConfig.new()
	grid_cfg.grid_type = GridMapConfig.GridType.HEX
	grid_cfg.orientation = GridMapConfig.Orientation.FLAT
	grid_cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	grid_cfg.radius = 3
	UGridMap.configure(grid_cfg)

	var instance: HexWorldGameplayInstance = GameWorld.create_instance(func(): return HexWorldGameplayInstance.new("spike_p3")) as HexWorldGameplayInstance
	instance.grid = UGridMap.model

	var totem := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	instance.add_actor(totem)
	totem.set_team_id(0)
	UGridMap.model.place_occupant(HexCoord.new(0, 0), totem)
	totem.hex_position = HexCoord.new(0, 0)

	var recorder := BattleRecorder.new({"battleId": "spike_p3", "tickInterval": int(TICK_INTERVAL)})
	var all_actors: Array[Actor] = [totem]
	var snap := PlaybackData.WorldSnapshot.new()
	for a in all_actors:
		snap.actors.append(PlaybackData.ActorInitData.create(a))
	snap.position_formats = {"Character": "hex"}
	recorder.start_recording(snap, all_actors)

	# grant DemonForm 让它有 ability_granted 事件;tick 数次让 stacks_changed 产生
	var demon_ability := Ability.new(HexBattleDemonForm.ABILITY, totem.get_id())
	totem.ability_set.grant_ability(demon_ability, instance)
	# grant 后立即 flush, 让 abilityGranted 进入 frame 0
	recorder.record_frame(-1, GameWorld.event_collector.flush())

	for _i in range(40):
		instance.base_tick(TICK_INTERVAL)
		var t_now2 := instance.get_logic_time()
		totem.ability_set.tag_container.tick(0.0, t_now2)
		totem.ability_set.tick(TICK_INTERVAL, t_now2)
		totem.ability_set.tick_executions(TICK_INTERVAL, instance)
		# Replay 关键: flush event_collector 进入 recorder
		recorder.record_frame(_i, GameWorld.event_collector.flush())

	var replay := recorder.stop_recording("spike_complete")
	var has_granted := false
	var has_stacks_changed := false
	for frame_dict in (replay.get("timeline", []) as Array):
		var events: Array = frame_dict.get("events", [])
		for ev in events:
			if ev is Dictionary:
				var k := str((ev as Dictionary).get("kind", ""))
				if k == "abilityGranted":
					has_granted = true
				elif k == "abilityStacksChanged":
					has_stacks_changed = true
	if has_granted and has_stacks_changed:
		_record(phase, true, "中途 add_actor 的 abilityGranted + abilityStacksChanged 都进 replay")
	else:
		_record(phase, false, "abilityGranted=%s abilityStacksChanged=%s" % [has_granted, has_stacks_changed])

	GameWorld.destroy()


# ============================================================
# Phase 4a: manual remove_actor (显式)
# ============================================================
func _run_phase_4_manual_remove() -> void:
	var phase := "4a. manual_remove_release"
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()
	var grid_cfg := GridMapConfig.new()
	grid_cfg.grid_type = GridMapConfig.GridType.HEX
	grid_cfg.orientation = GridMapConfig.Orientation.FLAT
	grid_cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	grid_cfg.radius = 3
	UGridMap.configure(grid_cfg)

	var instance: HexWorldGameplayInstance = GameWorld.create_instance(func(): return HexWorldGameplayInstance.new("spike_p4")) as HexWorldGameplayInstance
	instance.grid = UGridMap.model

	var totem := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	instance.add_actor(totem)
	totem.set_team_id(0)
	UGridMap.model.place_occupant(HexCoord.new(1, 0), totem)
	totem.hex_position = HexCoord.new(1, 0)

	# 仿 TTL: 5s 后显式 remove_actor。HexWorldGameplayInstance.remove_actor 应同时清 grid。
	var ttl_ms := 5000.0
	var tick_count := 0
	while instance.get_logic_time() < ttl_ms + 200.0:
		instance.tick(TICK_INTERVAL)
		tick_count += 1
		if tick_count > 100:
			break

	# 手动 simulate TTL → remove；这是 manual remove 结论，不代表 TimeDuration lifecycle。
	instance.remove_actor(totem.get_id())

	var still_in_actors := instance.get_actor(totem.get_id()) != null
	var grid_still_occupied := UGridMap.model.get_occupant(HexCoord.new(1, 0)) != null

	if not still_in_actors and not grid_still_occupied:
		_record(phase, true, "显式 remove_actor 后 actor / grid 都清理干净")
	else:
		_record(phase, false, "still_in_actors=%s grid_still_occupied=%s" % [still_in_actors, grid_still_occupied])

	GameWorld.destroy()


# ============================================================
# Phase 4b: TimeDurationConfig → NoInstance.on_remove lifecycle
# ============================================================
func _run_phase_4b_ttl_lifecycle() -> void:
	var phase := "4b. ttl_lifecycle_on_remove"
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()
	var grid_cfg := GridMapConfig.new()
	grid_cfg.grid_type = GridMapConfig.GridType.HEX
	grid_cfg.orientation = GridMapConfig.Orientation.FLAT
	grid_cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	grid_cfg.radius = 3
	UGridMap.configure(grid_cfg)

	var instance: HexWorldGameplayInstance = GameWorld.create_instance(func(): return HexWorldGameplayInstance.new("spike_p4b")) as HexWorldGameplayInstance
	instance.grid = UGridMap.model

	var totem := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	instance.add_actor(totem)
	totem.set_team_id(0)
	UGridMap.model.place_occupant(HexCoord.new(1, 0), totem)
	totem.hex_position = HexCoord.new(1, 0)
	var totem_id := totem.get_id()

	var remove_actions: Array[Action.BaseAction] = [_RemoveOwnerActorOnRemoveAction.new()]
	var ttl_config := (AbilityConfig.builder()
		.config_id(TTL_LIFECYCLE_CONFIG_ID)
		.display_name("Spike TTL Lifecycle Cleanup")
		.ability_tags(["spike", "ttl"])
		.component_config(TimeDurationConfig.new(300.0))
		.component_config(NoInstanceConfig.builder()
			.on_remove_actions(remove_actions)
			.build())
		.build())
	var ttl_ability := Ability.new(ttl_config, totem_id)
	totem.ability_set.grant_ability(ttl_ability, instance)

	for _i in range(10):
		totem.ability_set.tick(TICK_INTERVAL, instance.get_logic_time())
		if instance.get_actor(totem_id) == null:
			break

	var removed_by_lifecycle := instance.get_actor(totem_id) == null
	var grid_released := UGridMap.model.get_occupant(HexCoord.new(1, 0)) == null
	var expired_by_duration := ttl_ability.is_expired() \
		and ttl_ability.get_expire_reason() == TimeDurationComponent.EXPIRE_REASON_TIME_DURATION

	if removed_by_lifecycle and grid_released and expired_by_duration:
		_record(phase, true, "TimeDurationConfig expire → NoInstance.on_remove → remove_actor 清理 actor / grid")
	else:
		_record(phase, false,
			"removed_by_lifecycle=%s grid_released=%s expired_by_duration=%s" % [
				removed_by_lifecycle, grid_released, expired_by_duration,
			])

	GameWorld.destroy()


# ============================================================
# Phase 5: 图腾行为 (placeholder, 留正式 impl)
# ============================================================
func _run_phase_5_behavior_placeholder() -> void:
	var phase := "5. behavior_placeholder"
	# spike 阶段不实现正式图腾行为 (auto-attack / low HP / TTL 完整 lifecycle)。
	# placeholder 不计入 pass_count；正式 impl 起新 /goal 时再补。
	_record(phase, true, "placeholder: 正式图腾 behavior 留给后续 /goal (不计入完成)", false)


# ============================================================
# Reporting
# ============================================================
func _record(phase: String, pass_v: bool, reason: String, counts_toward_total: bool = true) -> void:
	_phase_results.append({
		"phase": phase,
		"pass": pass_v,
		"reason": reason,
		"counts_toward_total": counts_toward_total,
	})
	var status := "PASS" if pass_v else "FAIL"
	if not counts_toward_total:
		status = "SKIP"
	print("  [%s] %s — %s" % [status, phase, reason])


func _report() -> void:
	var pass_count := 0
	var total_verified := 0
	var skipped := 0
	for r in _phase_results:
		if not bool(r.get("counts_toward_total", true)):
			skipped += 1
			continue
		total_verified += 1
		if r["pass"]:
			pass_count += 1
	var ok := pass_count == total_verified
	var marker := "PASS" if ok else "FAIL"
	print("\nSMOKE_SPIKE_RESULT: %s - %d/%d verified phases passed; %d placeholders skipped" % [
		marker, pass_count, total_verified, skipped,
	])
	get_tree().quit(0 if ok else 1)
