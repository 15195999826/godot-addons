## Smoke: 战斗 tick 循环里的 remove_actor、尸体身上在飞的 execution 与当帧被击杀者。
##
## 四幕：
##   1. HexBattleProcedure 的补 tick 循环（中途 spawn 的图腾 / 火焰地块走这条）遍历 registry 快照：
##      循环内某个 actor 到期把自己 remove_actor 掉，排在它后面的 actor 本帧照常 tick（活数组遍历会因左移跳过它）；
##      本趟里已被别人移出 registry 的 actor 不再 tick（与活数组遍历同一结果）。
##   2. SkillPreviewProcedure 的环境物循环同形，同一条合同。
##   3. 角色起手 Move（START 已预订目的地）后、EXECUTE 之前被击杀：尸体不 tick，Move 不落地（位置不变、预订已随
##      clear_grid_footprint 清掉）——而那条在飞的 execution 当帧取消，不以「执行中」残留在尸体上。
##   4. 主循环名单是开趟时建的：排在击杀者之后、当帧稍早被打死的角色，轮到它时已是尸体——当帧就不再
##      advance_and_is_acting（身上在飞的 keyframe 不 fire）、不充能、不起手新行动。SkillPreviewProcedure 的参战者循环同一条合同。
##
## 退出码: 0 PASS / 1 FAIL; 标记 "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


## 探针角色：不充能（不进 AI 决策）；配置了 on_atb 的那个在轮到自己充能时调一次（模拟「本帧 AI 起手了一个行动」）。
class ProbeCharacter:
	extends CharacterActor

	var on_atb: Callable = Callable()

	func _init(p_character_class: HexBattleClassConfig.CharacterClass) -> void:
		super._init(p_character_class)

	func accumulate_atb(_dt: float) -> void:
		if on_atb.is_valid():
			var callback := on_atb
			on_atb = Callable()
			callback.call()


## 用固定左右队建 HexBattleProcedure 的 world（不录像、不写日志）。
class FixedTeamsHexWorld:
	extends HexWorldGameplayInstance

	var left: Array[CharacterActor] = []
	var right: Array[CharacterActor] = []

	func _create_battle_procedure(_participants: Array[Actor]) -> BattleProcedure:
		return HexBattleProcedure.new(self, left, right, {"logging": false, "recording": false})


## 探针 action：execute 时调一个 Callable。只持 Callable（StateCheck 对属性做 str hash，Callable 的字符串稳定），
## 计数与 remove_actor 都在 lambda 里做、只捕获 id，不把 world / actor 存进任何字段。
class ProbeAction:
	extends Action.BaseAction

	var _on_execute: Callable

	func _init(on_execute: Callable) -> void:
		super._init(TargetSelector.new())
		type = "probe"
		_on_execute = on_execute

	func execute(_ctx: ExecutionContext) -> ActionResult:
		_on_execute.call()
		return ActionResult.create_success_result([])


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: remove_actor inside the tick loop / in-flight executions on a corpse ===")
	# 四幕互不依赖，全部跑完再汇总：一幕失败不遮住另外几幕。
	var failures: Array[String] = []
	for status: String in [_phase_hex_mid_spawn_loop(), _phase_skill_preview_environment_loop(), _phase_corpse_execution(),
			_phase_killed_earlier_in_the_frame(), _phase_preview_killed_earlier_in_the_frame()]:
		if status != "":
			failures.append(status)
	GameWorld.shutdown()
	if failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - tick loops walk a registry snapshot; a corpse keeps no in-flight action and stops ticking in the frame it dies")
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_RESULT: FAIL - %s" % " | ".join(failures))
		get_tree().quit(1)


# ========== 幕 1：HexBattleProcedure 补 tick 循环 ==========

## registry 顺序 [l1, r1, leaver, witness, remover, victim, tail]，后五个不在左右队里（= 中途 spawn 的形状）。
## leaver 把自己移出 world；remover 把排在后面的 victim 移出 world。一帧之后：
## leaver / witness / remover / tail 各 fire 一次，victim 零次。
func _phase_hex_mid_spawn_loop() -> String:
	GameWorld.shutdown()
	var world := FixedTeamsHexWorld.new()
	world.configure_grid(_make_grid_config())
	GameWorld.create_instance(world)
	world.start()
	var l1 := _place_character(world, HexCoord.new(-3, 0), 0)
	var r1 := _place_character(world, HexCoord.new(3, 0), 1)
	world.left = [l1]
	world.right = [r1]

	var fired := {}
	var world_id := world.id
	var names: Array[String] = ["leaver", "witness", "remover", "victim", "tail"]
	var ids := {}
	for i in names.size():
		var actor := _place_character(world, HexCoord.new(i - 2, 1), -1)
		ids[names[i]] = actor.get_id()
		fired[names[i]] = 0
	for actor_name in names:
		var removes := ""
		if actor_name == "leaver":
			removes = str(ids["leaver"])
		elif actor_name == "remover":
			removes = str(ids["victim"])
		_grant_probe(world.get_actor(str(ids[actor_name])), actor_name, fired, world_id, removes)

	# 直接驱动 procedure 恰好一个战斗 tick：world.tick() 一次会把整场战斗跑完，被跳过的那一帧就看不出来了。
	var participants: Array[Actor] = [l1, r1]
	var procedure := world.start_battle(participants)
	procedure.tick_once()

	if world.get_actor(str(ids["leaver"])) != null or world.get_actor(str(ids["victim"])) != null:
		return "hex: leaver / victim should have left the registry"
	var expected := {"leaver": 1, "witness": 1, "remover": 1, "victim": 0, "tail": 1}
	for actor_name in names:
		if int(fired[actor_name]) != int(expected[actor_name]):
			return "hex: '%s' fired %d time(s) in the tick, expected %d (all: %s)" % [
				actor_name, int(fired[actor_name]), int(expected[actor_name]), str(fired)]
	return ""


# ========== 幕 2：SkillPreviewProcedure 环境物循环 ==========

func _phase_skill_preview_environment_loop() -> String:
	GameWorld.shutdown()
	var world := SkillPreviewWorldGI.new()
	GameWorld.create_instance(world)
	world.start()
	world.configure_grid(_make_grid_config())
	var a := _place_plain_character(world, HexCoord.new(-3, 0), 0)
	var b := _place_plain_character(world, HexCoord.new(3, 0), 1)

	var fired := {}
	var world_id := world.id
	var names: Array[String] = ["leaver", "witness", "remover", "victim", "tail"]
	var ids := {}
	for actor_name in names:
		var env := EnvironmentActor.new("probe_env", null)
		world.add_actor(env)
		ids[actor_name] = env.get_id()
		fired[actor_name] = 0
	for actor_name in names:
		var removes := ""
		if actor_name == "leaver":
			removes = str(ids["leaver"])
		elif actor_name == "remover":
			removes = str(ids["victim"])
		_grant_probe(world.get_actor(str(ids[actor_name])), actor_name, fired, world_id, removes)

	world.queue_preview([
		{"actor_id": a.get_id(), "passives": [] as Array[AbilityConfig], "track": []},
		{"actor_id": b.get_id(), "passives": [] as Array[AbilityConfig], "track": []},
	], true)
	var participants: Array[Actor] = [a, b]
	var procedure := world.start_battle(participants)
	procedure.tick_once()

	var expected := {"leaver": 1, "witness": 1, "remover": 1, "victim": 0, "tail": 1}
	for actor_name in names:
		if int(fired[actor_name]) != int(expected[actor_name]):
			return "preview: '%s' fired %d time(s) in the tick, expected %d (all: %s)" % [
				actor_name, int(fired[actor_name]), int(expected[actor_name]), str(fired)]
	return ""


# ========== 幕 3：尸体身上在飞的 Move ==========

## 左队 [mover, bystander]、右队 [killer]。一帧之内：mover 轮到自己时起手 Move（START 预订 (1, 0)）→ killer 的
## 探针技能打死 mover（死亡清足迹：占用与预订都清掉）。此后 mover 不再 tick：Move 永不落地；那条 execution 不残留。
func _phase_corpse_execution() -> String:
	GameWorld.shutdown()
	var world := FixedTeamsHexWorld.new()
	world.configure_grid(_make_grid_config())
	GameWorld.create_instance(world)
	world.start()
	var origin := HexCoord.new(0, 0)
	var destination := HexCoord.new(1, 0)
	var mover := _place_character(world, origin, 0, HexBattleClassConfig.CharacterClass.ARCHER)
	var bystander := _place_character(world, HexCoord.new(-3, 0), 0)
	var killer := _place_character(world, HexCoord.new(3, 0), 1)
	world.left = [mover, bystander]
	world.right = [killer]
	mover.equip_abilities()
	var move := mover.get_move_ability()
	if move == null:
		return "corpse: mover has no move ability"

	var mover_id := mover.get_id()
	var move_id := move.id
	var world_id := world.id
	var destination_dict := destination.to_dict()
	# 防空转：起手那一刻的预订、被激活的 execution 都记下来——取消后 ability 不再持有它，只能从这里看它的终态。
	var observed := {"reserved_by": ""}
	var executions: Array[AbilityExecutionInstance] = []
	move.add_execution_activated_listener(func(instance: AbilityExecutionInstance) -> void:
		executions.append(instance))
	mover.on_atb = func() -> void:
		var hex_world := GameWorld.get_instance_by_id(world_id) as HexWorldGameplayInstance
		hex_world.event_processor.deliver_to_ability(
			GameEvent.AbilityActivate.create(move_id, mover_id, 0.0, "", destination_dict).to_dict(), mover_id, move_id)
		observed["reserved_by"] = hex_world.grid.get_reservation(HexCoord.from_dict(destination_dict))
	var targets: Array[String] = [mover_id]
	var kill_actions: Array[Action.BaseAction] = [
		HexBattleDamageAction.new(HexBattleTargetSelectors.fixed(targets), Resolvers.float_val(99999.0)),
	]
	killer.ability_set.grant_ability(Ability.new(_self_firing_config("probe_kill", kill_actions), killer.get_id()))

	var participants: Array[Actor] = [mover, bystander, killer]
	var procedure := world.start_battle(participants)
	procedure.tick_once()

	if executions.size() != 1 or str(observed["reserved_by"]) != mover_id:
		return "corpse: test setup — the Move should have started exactly once and reserved the destination (executions=%d reserved_by='%s')" % [
			executions.size(), str(observed["reserved_by"])]
	if not mover.is_dead():
		return "corpse: the mover should have been killed in the first tick"
	if not mover.hex_position.equals(origin):
		return "corpse: test setup — the move landed before the kill"
	if world.grid.get_reservation(destination) != "":
		return "corpse: death should have cleared the mover's reservation on the destination"
	if not executions[0].is_cancelled():
		return "corpse: the dead mover's in-flight Move execution is still '%s', expected cancelled" % executions[0].get_state()
	if not move.get_executing_instances().is_empty():
		return "corpse: the dead mover still holds %d in-flight Move execution(s)" % move.get_executing_instances().size()

	for _i in 3:
		procedure.tick_once()
	if not mover.hex_position.equals(origin):
		return "corpse: a dead mover's Move must never land (position moved to %s)" % str(mover.hex_position.to_dict())
	if world.grid.get_occupant(destination) != null:
		return "corpse: nobody should occupy the destination"
	if not move.get_executing_instances().is_empty():
		return "corpse: an in-flight execution reappeared on the corpse"
	return ""


# ========== 幕 4：主循环里当帧稍早被击杀者 ==========

## 左队 [killer]、右队 [ticker, actor_b]：主循环名单顺序 killer → ticker → actor_b。一帧之内 killer 的探针技能先把
## 右队两人都打死，轮到它们时已是尸体：ticker 身上在飞的探针 keyframe 当帧不 fire（尸体不 advance_and_is_acting）；
## actor_b 不充能、也就不起手（on_atb 里那次 Move 不发生，目的地无人预订）。
func _phase_killed_earlier_in_the_frame() -> String:
	GameWorld.shutdown()
	var world := FixedTeamsHexWorld.new()
	world.configure_grid(_make_grid_config())
	GameWorld.create_instance(world)
	world.start()
	var destination := HexCoord.new(1, 1)
	var killer := _place_character(world, HexCoord.new(-3, 0), 0)
	var ticker := _place_character(world, HexCoord.new(3, 0), 1)
	var actor_b := _place_character(world, HexCoord.new(0, 1), 1, HexBattleClassConfig.CharacterClass.ARCHER)
	world.left = [killer]
	world.right = [ticker, actor_b]
	actor_b.equip_abilities()
	var move := actor_b.get_move_ability()
	if move == null:
		return "killed-earlier: actor_b has no move ability"

	var fired := {"ticker": 0}
	_grant_probe(ticker, "ticker", fired, world.id, "")

	var actor_b_id := actor_b.get_id()
	var move_id := move.id
	var destination_dict := destination.to_dict()
	var observed := {"atb_turns": 0}
	var executions: Array[AbilityExecutionInstance] = []
	move.add_execution_activated_listener(func(instance: AbilityExecutionInstance) -> void:
		executions.append(instance))
	actor_b.on_atb = func() -> void:
		observed["atb_turns"] = int(observed["atb_turns"]) + 1
		GameWorld.get_instance_of_actor(actor_b_id).event_processor.deliver_to_ability(
			GameEvent.AbilityActivate.create(move_id, actor_b_id, 0.0, "", destination_dict).to_dict(), actor_b_id, move_id)
	var targets: Array[String] = [ticker.get_id(), actor_b_id]
	var kill_actions: Array[Action.BaseAction] = [
		HexBattleDamageAction.new(HexBattleTargetSelectors.fixed(targets), Resolvers.float_val(99999.0)),
	]
	killer.ability_set.grant_ability(Ability.new(_self_firing_config("probe_kill_both", kill_actions), killer.get_id()))

	var participants: Array[Actor] = [killer, ticker, actor_b]
	var procedure := world.start_battle(participants)
	procedure.tick_once()

	if not ticker.is_dead() or not actor_b.is_dead():
		return "killed-earlier: test setup — both right-team actors should have been killed in the first tick"
	# 三条互不遮挡：advance_and_is_acting / 充能 / 起手各报各的。
	var problems: Array[String] = []
	if int(fired["ticker"]) != 0:
		problems.append("the corpse's in-flight keyframe fired %d time(s) in the frame it was killed, expected 0 (a corpse must not advance_and_is_acting)" % int(fired["ticker"]))
	if int(observed["atb_turns"]) != 0:
		problems.append("the corpse got %d ATB turn(s) in the frame it was killed, expected 0 (a corpse must not charge)" % int(observed["atb_turns"]))
	if not executions.is_empty():
		problems.append("the corpse started %d Move(s) after it was killed" % executions.size())
	if world.grid.get_reservation(destination) != "":
		problems.append("a corpse holds a reservation on the destination")
	if not problems.is_empty():
		return "killed-earlier: " + "; ".join(problems)
	return ""


## SkillPreviewProcedure 的参战者循环同形：名单顺序 killer → ticker，killer 的探针当帧打死 ticker，
## ticker 身上在飞的探针 keyframe 当帧不 fire。
func _phase_preview_killed_earlier_in_the_frame() -> String:
	GameWorld.shutdown()
	var world := SkillPreviewWorldGI.new()
	GameWorld.create_instance(world)
	world.start()
	world.configure_grid(_make_grid_config())
	var killer := _place_plain_character(world, HexCoord.new(-3, 0), 0)
	var ticker := _place_plain_character(world, HexCoord.new(3, 0), 1)

	var fired := {"ticker": 0}
	_grant_probe(ticker, "ticker", fired, world.id, "")
	var targets: Array[String] = [ticker.get_id()]
	var kill_actions: Array[Action.BaseAction] = [
		HexBattleDamageAction.new(HexBattleTargetSelectors.fixed(targets), Resolvers.float_val(99999.0)),
	]
	killer.ability_set.grant_ability(Ability.new(_self_firing_config("probe_preview_kill", kill_actions), killer.get_id()))

	world.queue_preview([
		{"actor_id": killer.get_id(), "passives": [] as Array[AbilityConfig], "track": []},
		{"actor_id": ticker.get_id(), "passives": [] as Array[AbilityConfig], "track": []},
	], true)
	var participants: Array[Actor] = [killer, ticker]
	var procedure := world.start_battle(participants)
	procedure.tick_once()

	if not ticker.is_dead():
		return "preview killed-earlier: test setup — the ticker should have been killed in the first tick"
	if int(fired["ticker"]) != 0:
		return "preview killed-earlier: the corpse's in-flight keyframe fired %d time(s) in the frame it was killed, expected 0" % int(fired["ticker"])
	return ""


# ========== 夹具 ==========

static func _make_grid_config() -> GridMapConfig:
	var cfg := GridMapConfig.new()
	cfg.grid_type = GridMapConfig.GridType.HEX
	cfg.orientation = GridMapConfig.Orientation.FLAT
	cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	cfg.radius = 3
	return cfg


static func _place_character(world: HexWorldGameplayInstance, coord: HexCoord, team_id: int,
		character_class: HexBattleClassConfig.CharacterClass = HexBattleClassConfig.CharacterClass.WARRIOR) -> ProbeCharacter:
	var actor := ProbeCharacter.new(character_class)
	_put(world, actor, coord, team_id)
	return actor


static func _place_plain_character(world: HexWorldGameplayInstance, coord: HexCoord, team_id: int) -> CharacterActor:
	var actor := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	_put(world, actor, coord, team_id)
	return actor


static func _put(world: HexWorldGameplayInstance, actor: CharacterActor, coord: HexCoord, team_id: int) -> void:
	world.add_actor(actor)
	if team_id >= 0:
		actor.set_team_id(team_id)
	var placed := world.grid.place_occupant(coord, actor)
	Log.assert_crash(placed, "SmokeTickLoopRemoval", "test setup: place_occupant failed at (%d, %d)" % [coord.q, coord.r])
	actor.hex_position = coord.duplicate()


## 给 actor 挂一个 grant 即自激活的探针 ability：第一帧 tick 内 fire 一次——计数，removes 非空时再把那个 actor 移出 world。
static func _grant_probe(actor: HexBattleActor, actor_name: String, fired: Dictionary, world_id: String, removes: String) -> void:
	var actions: Array[Action.BaseAction] = [ProbeAction.new(func() -> void:
		fired[actor_name] = int(fired[actor_name]) + 1
		if removes != "":
			var world := GameWorld.get_instance_by_id(world_id) as HexWorldGameplayInstance
			if world != null:
				world.remove_actor(removes))]
	actor.ability_set.grant_ability(Ability.new(_self_firing_config("probe_" + actor_name, actions), actor.get_id()))


## grant 即自激活的一次性 ability（tag 在 50ms / 总长 100ms，第一个 100ms tick 内必 fire）。
static func _self_firing_config(config_id: String, actions: Array[Action.BaseAction]) -> AbilityConfig:
	return (AbilityConfig.builder()
		.config_id(config_id)
		.component_config(ActivateInstanceConfig.builder()
			.trigger(TriggerConfig.GRANTED_SELF)
			.timeline(TimelineData.new("t-" + config_id, 100.0, {"fire": 50.0}))
			.on_tag("fire", actions)
			.build())
		.build())
