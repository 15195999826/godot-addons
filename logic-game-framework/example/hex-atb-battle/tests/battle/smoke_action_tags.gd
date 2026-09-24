## Smoke: 行动载体 tag（active = 主动技能 / action = 移动）的两条合同。
##
## ATB 冻结认 active | action——角色花行动条换来的那个行动在飞才停充能（幕 1、2）；
## 眩晕的取消只认 active——在飞的主动技能被取消，在飞的 Move 照常走完（幕 3）。两张清单有意不同，别顺手统一。
##
## 三幕：
##   1. buff / 被动的周期 timeline 不冻结持有者：中毒 DOT（buff_poison）、涌动（buff_surge）、恶魔形态
##      （passive_demon_form）都是 grant 即启动的 loop timeline，buff 在身期间全程「执行中」；持有者照常充能
##      （把它们当成阻塞 = 中毒即定身、恶魔形态持有者整场零行动）。
##   2. 行动在飞仍冻结：真实的 Move（action tag）与 Strike（active tag）起手后，起帧时还在飞的每一帧都不充能
##      ——本帧内跑完的 execution 也算占用了这一帧——跑完后的下一帧恢复充能。
##   3. 眩晕落到正在行动的角色身上：在飞的 Strike 被取消（那一击不再命中），在飞的 Move 不打断
##      （已起手的那一步照常落地；前端凭 move_start 播整段位移，逻辑侧中途取消会让表现与棋盘错位）。
##
## 直接驱动 procedure.tick_once()：world.tick() 一次会把整场战斗跑完。
## 退出码: 0 PASS / 1 FAIL; 标记 "SMOKE_TEST_RESULT: PASS|FAIL - <reason>"
extends Node


const TICK_MS := 100.0


## 不充能的旁观者：只占队伍名额，不进 AI 决策。
class InertCharacter:
	extends CharacterActor

	func _init(p_character_class: HexBattleClassConfig.CharacterClass) -> void:
		super._init(p_character_class)

	func accumulate_atb(_dt: float) -> void:
		pass


## 用固定左右队建 HexBattleProcedure 的 world（不录像、不写日志）。
class FixedTeamsHexWorld:
	extends HexWorldGameplayInstance

	var left: Array[CharacterActor] = []
	var right: Array[CharacterActor] = []

	func _create_battle_procedure(_participants: Array[Actor]) -> BattleProcedure:
		return HexBattleProcedure.new(self, left, right, {"logging": false, "recording": false})


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke: action carrier tags — ATB freezes on active | action; stun cancels active only ===")
	# 三幕互不依赖，全部跑完再汇总。
	var failures: Array[String] = []
	for status: String in [_phase_periodic_timelines_do_not_freeze(), _phase_actions_in_flight_freeze(),
			_phase_stun_cancels_skill_not_move()]:
		if status != "":
			failures.append(status)
	GameWorld.shutdown()
	if failures.is_empty():
		print("SMOKE_TEST_RESULT: PASS - periodic timelines keep charging; an in-flight skill / move freezes ATB; stun cancels the skill, not the move")
		get_tree().quit(0)
	else:
		print("SMOKE_TEST_RESULT: FAIL - %s" % " | ".join(failures))
		get_tree().quit(1)


# ========== 幕 1：周期 timeline 不冻结持有者 ==========

## 左队三人各挂一个 grant 即启动的周期 timeline，推进 3 帧（远不到 ATB 满，不触发 AI 决策）：
## 每人的 ATB = 3 帧 × speed 对应的充能量；那条周期 execution 全程在飞（防空转）。
func _phase_periodic_timelines_do_not_freeze() -> String:
	var world := _make_world()
	var periodic: Array[AbilityConfig] = [
		HexBattlePoisonBuff.POISON_BUFF,
		HexBattleSurgeBuff.SURGE_BUFF,
		HexBattleDemonForm.ABILITY,
	]
	var holders: Array[CharacterActor] = []
	var granted: Array[Ability] = []
	for i in periodic.size():
		var holder := _place(world, CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR), HexCoord.new(-3, i), 0)
		holder.equip_abilities()
		var ability := Ability.new(periodic[i], holder.get_id())
		holder.ability_set.grant_ability(ability)
		holders.append(holder)
		granted.append(ability)
	var bystander := _place(world, InertCharacter.new(HexBattleClassConfig.CharacterClass.WARRIOR), HexCoord.new(3, 0), 1)
	world.left = holders
	world.right = [bystander]

	var participants: Array[Actor] = []
	for holder in holders:
		participants.append(holder)
	participants.append(bystander)
	var procedure := world.start_battle(participants)
	var ticks := 3
	for _i in ticks:
		procedure.tick_once()

	var problems: Array[String] = []
	for i in holders.size():
		var config_id := periodic[i].config_id
		if not granted[i].has_executing_instance():
			return "periodic: test setup — '%s' should still have its loop timeline in flight after %d ticks" % [config_id, ticks]
		var expected := holders[i].attribute_set.speed / 1000.0 * TICK_MS * float(ticks)
		var gauge := holders[i].get_atb_gauge()
		if not is_equal_approx(gauge, expected):
			problems.append("the '%s' holder's ATB is %.1f after %d ticks, expected %.1f" % [config_id, gauge, ticks, expected])
	if not problems.is_empty():
		return "periodic: a periodic buff / passive timeline must not freeze its holder's ATB — " + "; ".join(problems)
	return ""


# ========== 幕 2：行动在飞仍冻结 ==========

## mover 起手真实的 Move、striker 对相邻敌人起手真实的 Strike，逐帧推进：
## 起帧时行动还在飞 → 这一帧不充能；行动跑完后的下一帧恢复充能。
func _phase_actions_in_flight_freeze() -> String:
	var world := _make_world()
	var mover := _place(world, CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR), HexCoord.new(-2, 0), 0)
	var striker := _place(world, CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR), HexCoord.new(0, 0), 0)
	var target := _place(world, InertCharacter.new(HexBattleClassConfig.CharacterClass.WARRIOR), HexCoord.new(1, 0), 1)
	mover.equip_abilities()
	striker.equip_abilities()
	target.attribute_set.set_max_hp_base(1000.0)
	target.attribute_set.set_hp(1000.0)
	world.left = [mover, striker]
	world.right = [target]

	var move := mover.get_move_ability()
	var strike := striker.get_skill_ability()
	if move == null or strike == null or strike.config_id != HexBattleStrike.CONFIG_ID:
		return "in-flight: test setup — expected a Move on the mover and a Strike on the striker"

	var participants: Array[Actor] = [mover, striker, target]
	var procedure := world.start_battle(participants)
	world.event_processor.deliver_to_ability(GameEvent.AbilityActivate.create(
		move.id, mover.get_id(), 0.0, "", HexCoord.new(-2, 1).to_dict()).to_dict(), mover.get_id(), move.id)
	world.event_processor.deliver_to_ability(GameEvent.AbilityActivate.create(
		strike.id, striker.get_id(), 0.0, target.get_id(), {}).to_dict(), striker.get_id(), strike.id)

	var watched := {"Move": [mover, move], "Strike": [striker, strike]}
	var frozen_frames := {"Move": 0, "Strike": 0}
	var resumed := {"Move": false, "Strike": false}
	for _i in 20:
		var in_flight := {}
		var before := {}
		for label: String in watched:
			in_flight[label] = (watched[label][1] as Ability).has_executing_instance()
			before[label] = (watched[label][0] as CharacterActor).get_atb_gauge()
		procedure.tick_once()
		for label: String in watched:
			if resumed[label]:
				continue
			var after := (watched[label][0] as CharacterActor).get_atb_gauge()
			if in_flight[label]:
				if not is_equal_approx(after, float(before[label])):
					return "in-flight: ATB charged (%.1f -> %.1f) in a frame that started with the %s still in flight" % [
						float(before[label]), after, label]
				frozen_frames[label] = int(frozen_frames[label]) + 1
			elif after <= float(before[label]):
				return "in-flight: ATB did not resume charging in the frame after the %s ended" % label
			else:
				resumed[label] = true
		if resumed["Move"] and resumed["Strike"]:
			break

	for label: String in watched:
		if int(frozen_frames[label]) == 0:
			return "in-flight: test setup — the %s never was in flight at a frame start" % label
		if not resumed[label]:
			return "in-flight: the %s is still in flight after 20 ticks" % label
	return ""


# ========== 幕 3：眩晕只取消 active ==========

## mover 起手 Move（START 已预订目的地，EXECUTE 未到）、striker 起手 Strike（HIT 未到），随即两人各中一个眩晕：
## Strike 的 execution 当场取消、那一击永不命中；Move 的 execution 还在飞，照常落到目的地。
func _phase_stun_cancels_skill_not_move() -> String:
	var world := _make_world()
	var origin := HexCoord.new(-2, 0)
	var destination := HexCoord.new(-2, 1)
	var mover := _place(world, CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR), origin, 0)
	var striker := _place(world, CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR), HexCoord.new(0, 0), 0)
	var target := _place(world, InertCharacter.new(HexBattleClassConfig.CharacterClass.WARRIOR), HexCoord.new(1, 0), 1)
	mover.equip_abilities()
	striker.equip_abilities()
	target.attribute_set.set_max_hp_base(1000.0)
	target.attribute_set.set_hp(1000.0)
	world.left = [mover, striker]
	world.right = [target]
	var move := mover.get_move_ability()
	var strike := striker.get_skill_ability()
	if move == null or strike == null or strike.config_id != HexBattleStrike.CONFIG_ID:
		return "stun: test setup — expected a Move on the mover and a Strike on the striker"

	var participants: Array[Actor] = [mover, striker, target]
	var procedure := world.start_battle(participants)
	world.event_processor.deliver_to_ability(GameEvent.AbilityActivate.create(
		move.id, mover.get_id(), 0.0, "", destination.to_dict()).to_dict(), mover.get_id(), move.id)
	world.event_processor.deliver_to_ability(GameEvent.AbilityActivate.create(
		strike.id, striker.get_id(), 0.0, target.get_id(), {}).to_dict(), striker.get_id(), strike.id)
	if not move.has_executing_instance() or not strike.has_executing_instance():
		return "stun: test setup — both the Move and the Strike should be in flight before the stun lands"

	for stunned: CharacterActor in [mover, striker]:
		stunned.ability_set.grant_ability(Ability.new(HexBattleStunBuff.create_config(1000.0), stunned.get_id(), target.get_id()))

	var problems: Array[String] = []
	if strike.has_executing_instance():
		problems.append("the stun left the in-flight Strike running")
	if not move.has_executing_instance():
		problems.append("the stun cancelled the in-flight Move")
	for _i in 8:
		procedure.tick_once()
	if not is_equal_approx(target.attribute_set.hp, 1000.0):
		problems.append("the cancelled Strike still hit (target hp %.1f, expected 1000.0)" % target.attribute_set.hp)
	if not mover.hex_position.equals(destination):
		problems.append("the stunned mover's in-flight Move did not land (position %s)" % str(mover.hex_position.to_dict()))
	if world.grid.get_occupant(destination) != mover or world.grid.get_occupant(origin) != null:
		problems.append("the board does not show the mover on the destination")
	if not problems.is_empty():
		return "stun: a stun cancels in-flight skills (active tag) only, an in-flight Move (action tag) finishes — " + "; ".join(problems)
	return ""


# ========== 夹具 ==========

func _make_world() -> FixedTeamsHexWorld:
	GameWorld.shutdown()
	var world := FixedTeamsHexWorld.new()
	var cfg := GridMapConfig.new()
	cfg.grid_type = GridMapConfig.GridType.HEX
	cfg.orientation = GridMapConfig.Orientation.FLAT
	cfg.draw_mode = GridMapConfig.DrawMode.RADIUS
	cfg.radius = 3
	world.configure_grid(cfg)
	GameWorld.create_instance(world)
	world.start()
	return world


static func _place(world: HexWorldGameplayInstance, actor: CharacterActor, coord: HexCoord, team_id: int) -> CharacterActor:
	world.add_actor(actor)
	actor.set_team_id(team_id)
	var placed := world.grid.place_occupant(coord, actor)
	Log.assert_crash(placed, "SmokeActionTags", "test setup: place_occupant failed at (%d, %d)" % [coord.q, coord.r])
	actor.hex_position = coord.duplicate()
	return actor
