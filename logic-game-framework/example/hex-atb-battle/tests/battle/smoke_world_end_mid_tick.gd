## Smoke: 战斗 tick 内 world 被结束（GameWorld.destroy_instance → end() → abort()）时，
## procedure 的 tick_once 不再跑完余下的 actor —— 排在结束者之后的 actor 本帧不再被 tick。
## 此时本 world 已出 GameWorld 注册表，余下 actor 的 action 反查 ctx.instance 只会拿到 null。
##
## 两个 procedure 各一幕：
##   1. HexBattleProcedure：探针 CharacterActor 在 ATB 累积里结束 world，排在它后面的 actor 的
##      accumulate_atb 不得再被调用
##   2. SkillPreviewProcedure：两个 t=0 keyframe（tag 在 50ms，一次性 timeline 的 tag 只在
##      previous < tag_time <= elapsed 窗口里 fire，0ms 不会触发），第一个 actor 的 tag action 结束 world，
##      第二个 actor 的 tag action 不得再 fire
##
## 退出码: 0 PASS / 1 FAIL; 标记 "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


## 探针角色：accumulate_atb 计数，配置了 end_world_id 的那个在此刻结束 world。
## 不调 super，ATB 永不充满，不会进入 AI 决策；只捕获 world id（String），不成环。
class ProbeCharacter:
	extends CharacterActor

	var atb_calls := 0
	var end_world_id: String = ""

	func _init(p_character_class: HexBattleClassConfig.CharacterClass) -> void:
		super._init(p_character_class)

	func accumulate_atb(_dt: float) -> void:
		atb_calls += 1
		if end_world_id != "":
			GameWorld.destroy_instance(end_world_id)


## 用固定左右队建 HexBattleProcedure 的 world（不录像、不写日志）。
class MidTickHexWorld:
	extends HexWorldGameplayInstance

	var left: Array[CharacterActor] = []
	var right: Array[CharacterActor] = []

	func _create_battle_procedure(_participants: Array[Actor]) -> BattleProcedure:
		return HexBattleProcedure.new(self, left, right, {"logging": false, "recording": false})


## 探针 action：execute 时调一个 Callable。只持 Callable（StateCheck 对属性做 str hash，
## Callable 的字符串稳定），计数与结束 world 都在 lambda 里做，不把 world 存进任何字段。
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
	print("=== Smoke: world ended inside a battle tick stops tick_once ===")
	var status := _phase_hex_battle()
	if status == "":
		status = _phase_skill_preview()
	GameWorld.shutdown()
	if status == "":
		print("SMOKE_TEST_RESULT: PASS - tick_once stops at the actor that ended the world (hex + skill-preview)")
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_RESULT: FAIL - %s" % status)
		get_tree().quit(1)


static func _make_grid_config() -> GridMapConfig:
	var cfg := GridMapConfig.new()
	cfg.grid_type = GridMapConfig.GridType.HEX
	cfg.orientation = GridMapConfig.Orientation.FLAT
	cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	cfg.radius = 3
	return cfg


static func _place(world: HexWorldGameplayInstance, actor: CharacterActor, coord: HexCoord, team_id: int) -> void:
	world.add_actor(actor)
	actor.set_team_id(team_id)
	var placed := world.grid.place_occupant(coord, actor)
	Log.assert_crash(placed, "SmokeWorldEndMidTick", "test setup: place_occupant failed at (%d, %d)" % [coord.q, coord.r])
	actor.hex_position = coord.duplicate()


## 幕 1：HexBattleProcedure。左队的 ender 在 accumulate_atb 里结束 world，右队的 witness 排在它后面。
func _phase_hex_battle() -> String:
	GameWorld.shutdown()
	var world := MidTickHexWorld.new()
	world.configure_grid(_make_grid_config())
	GameWorld.create_instance(world)
	world.start()

	var ender := ProbeCharacter.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	_place(world, ender, HexCoord.new(0, 0), 0)
	var witness := ProbeCharacter.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	_place(world, witness, HexCoord.new(1, 0), 1)
	world.left = [ender]
	world.right = [witness]
	ender.end_world_id = world.id

	var participants: Array[Actor] = [ender, witness]
	var procedure := world.start_battle(participants)
	world.tick(100.0)

	if ender.atb_calls != 1:
		return "hex: the world-ending actor should have been ticked exactly once, got %d" % ender.atb_calls
	if witness.atb_calls != 0:
		return "hex: the actor after the world-ending one was still ticked in the same tick_once (accumulate_atb calls = %d)" % witness.atb_calls
	if not procedure.should_end():
		return "hex: aborted procedure should report finished"
	if world.has_active_battle():
		return "hex: the battle slot should have been released by abort()"
	if GameWorld.get_instance_by_id(world.id) != null:
		return "hex: the world should have left the registry"
	return ""


## 幕 2：SkillPreviewProcedure。两个 t=0 keyframe（tag 在 50ms），ender 的 tag action 结束 world，
## witness 的 tag action 不得再 fire。
func _phase_skill_preview() -> String:
	GameWorld.shutdown()
	var world := SkillPreviewWorldGI.new()
	GameWorld.create_instance(world)
	world.start()
	world.configure_grid(_make_grid_config())

	var ender := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	_place(world, ender, HexCoord.new(0, 0), 0)
	var witness := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	_place(world, witness, HexCoord.new(1, 0), 1)

	var fired := { "ender": 0, "witness": 0 }
	var world_id := world.id
	var end_world_config := _probe_ability("probe_end_world", func() -> void:
		fired["ender"] += 1
		GameWorld.destroy_instance(world_id))
	var count_config := _probe_ability("probe_count", func() -> void:
		fired["witness"] += 1)

	world.queue_preview([
		{
			"actor_id": ender.get_id(),
			"passives": [] as Array[AbilityConfig],
			"track": [{"time_ms": 0, "ability_config": end_world_config, "target_id": ""}],
		},
		{
			"actor_id": witness.get_id(),
			"passives": [] as Array[AbilityConfig],
			"track": [{"time_ms": 0, "ability_config": count_config, "target_id": ""}],
		},
	], false)
	var participants: Array[Actor] = [ender, witness]
	var procedure := world.start_battle(participants)
	world.tick(100.0)

	if int(fired["ender"]) != 1:
		return "preview: the world-ending action should have fired exactly once, got %d" % int(fired["ender"])
	if int(fired["witness"]) != 0:
		return "preview: the participant after the world-ending one still ran its execution in the same tick_once (fired %d)" % int(fired["witness"])
	if not procedure.should_end():
		return "preview: aborted procedure should report finished"
	if world.has_active_battle():
		return "preview: the battle slot should have been released by abort()"
	return ""


## 单 tag 的一次性 active ability（tag 在 50ms / 总长 100ms，第一个 100ms tick 内必 fire）；tag action 是探针。
static func _probe_ability(config_id: String, on_execute: Callable) -> AbilityConfig:
	var actions: Array[Action.BaseAction] = [ProbeAction.new(on_execute)]
	return (AbilityConfig.builder()
		.config_id(config_id)
		.active_use(ActiveUseConfig.builder()
			.timeline(TimelineData.new("t-" + config_id, 100.0, {"fire": 50.0}))
			.on_tag("fire", actions)
			.build())
		.build())
