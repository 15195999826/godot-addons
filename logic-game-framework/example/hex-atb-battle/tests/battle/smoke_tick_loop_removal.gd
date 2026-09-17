## Smoke: 战斗 tick 循环里的 remove_actor 与尸体身上在飞的 execution。
##
## 三幕：
##   1. HexBattleProcedure 的补 tick 循环（中途 spawn 的图腾 / 火焰地块走这条）遍历 registry 快照：
##      循环内某个 actor 到期把自己 remove_actor 掉，排在它后面的 actor 本帧照常 tick（活数组遍历会因左移跳过它）；
##      本趟里已被别人移出 registry 的 actor 不再 tick（与活数组遍历同一结果）。
##   2. SkillPreviewProcedure 的环境物循环同形，同一条合同。
##   3. 角色起手 Move（START 已预订目的地）后、EXECUTE 之前被击杀：尸体不 tick，Move 不落地（位置不变、预订已随
##      clear_grid_footprint 清掉）——而那条在飞的 execution 当帧取消，不以「执行中」残留在尸体上。
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
	# 三幕互不依赖，全部跑完再汇总：一幕失败不遮住另外两幕。
	var failures: Array[String] = []
	for status: String in [_phase_hex_mid_spawn_loop(), _phase_skill_preview_environment_loop(), _phase_corpse_execution()]:
		if status != "":
			failures.append(status)
	GameWorld.shutdown()
	if failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - tick loops walk a registry snapshot; a corpse keeps no in-flight action")
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
		var actor := GameWorld.get_actor(mover_id) as CharacterActor
		actor.ability_set.receive_event(
			GameEvent.AbilityActivate.create(move_id, mover_id, 0.0, "", destination_dict).to_dict())
		var hex_world := GameWorld.get_instance_by_id(world_id) as HexWorldGameplayInstance
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
