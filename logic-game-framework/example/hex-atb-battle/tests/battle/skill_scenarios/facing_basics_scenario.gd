## §0.3 Character logic-facing V0 - 基础合同断言
##
## 验证:
## 1. 初始默认: A 队 (team 0) caster facing = DIR_EAST; B 队 (team 1) enemy_0 facing = DIR_WEST
## 2. forced displacement (knockback_punch): caster 被推不改变 facing
##
## 不验证主动施法 face target (各 active skill 通过 HexFacing.face_target_action() 自己接入,
## Shadow Step / Stance / Chain Lightning / Demon Form scenario 各自覆盖)。
## 不验证主动 move face destination (scenario harness 当前不支持 action.target_coord;
## start_move_action.gd 内已集成 HexFacing.face_actor_toward, 由其它 move-based scenario 覆盖)。
class_name FacingBasicsScenario
extends SkillScenario


func get_name() -> String:
	return "§0.3 Facing basics: A 队 EAST / B 队 WEST 初始, forced displacement 不改 facing"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 5, "cols": 8},
		"caster": {"class": "WARRIOR", "pos": [1, 2], "atk": 50, "hp": 1000, "max_hp": 1000},
		"enemies": [
			# enemy_0 与 caster 相邻 [2,2], 推 caster 一格 (knockback_punch RANGE=1)
			{"class": "WARRIOR", "pos": [2, 2], "hp": 200, "max_hp": 200},
		],
	}


func get_actions() -> Array[Dictionary]:
	return [
		# enemy_0 推 caster: forced displacement, caster facing 不应改变
		{"caster": "enemy_0", "skill": HexBattleKnockbackPunch.ABILITY, "target": "caster", "time_ms": 0},
	]


## knockback_punch ~250ms + buffer; max 1500ms / 100ms tick = 15, 取 30.
func get_max_ticks() -> int:
	return 30


func assert_replay(ctx: ScenarioAssertContext) -> void:
	_assert_direction_between_six_dirs(ctx)

	# Case 1: 初始默认 facing 与 team 对齐 (init 不产生 event,直接读 final state)。
	# enemy_0 是 B 队 (team 1) → 应保持 WEST; 整场 scenario enemy_0 无 active skill 改 facing。
	ctx.assert_eq(ctx.actor_final_facing(ctx.enemy_id(0)), HexFacing.DIR_WEST,
		"Case1: enemy_0 (B 队) 初始 facing = DIR_WEST (3)")

	# Case 2: caster 是 A 队, 被 enemy_0 推. caster 的 facing 不应改变 (knockback 是
	# forced displacement, push_action 不调 HexFacing.face_actor_toward)。
	ctx.assert_eq(ctx.actor_final_facing(ctx.caster_id), HexFacing.DIR_EAST,
		"Case2: caster (A 队) 被推后 facing 仍为 DIR_EAST (forced displacement 不改 facing)")

	# Case 3 (复用 case 2 数据): 整场 scenario 不应有 caster 的 actor_facing_changed event。
	# (knockback push_action 不产生 facing changed, 因为没 active facing update)
	var caster_facing_events: Array[Dictionary] = []
	for e in ctx.events:
		if str(e.get("kind", "")) == "actor_facing_changed" \
				and str(e.get("actor_id", "")) == ctx.caster_id:
			caster_facing_events.append(e)
	ctx.assert_eq(caster_facing_events.size(), 0,
		"Case3: caster 整场无 ActorFacingChangedEvent (forced displacement 与无主动施法时不应产生)")


func _assert_direction_between_six_dirs(ctx: ScenarioAssertContext) -> void:
	var origin := HexCoord.new(0, 0)
	var cases: Array[Dictionary] = [
		{"to": HexCoord.new(1, 0), "dir": HexFacing.DIR_EAST, "name": "EAST"},
		{"to": HexCoord.new(1, -1), "dir": HexFacing.DIR_NORTHEAST, "name": "NORTHEAST"},
		{"to": HexCoord.new(0, -1), "dir": HexFacing.DIR_NORTHWEST, "name": "NORTHWEST"},
		{"to": HexCoord.new(-1, 0), "dir": HexFacing.DIR_WEST, "name": "WEST"},
		{"to": HexCoord.new(-1, 1), "dir": HexFacing.DIR_SOUTHWEST, "name": "SOUTHWEST"},
		{"to": HexCoord.new(0, 1), "dir": HexFacing.DIR_SOUTHEAST, "name": "SOUTHEAST"},
	]
	for case_data in cases:
		var actual := HexFacing.direction_between(origin, case_data["to"] as HexCoord)
		ctx.assert_eq(actual, case_data["dir"], "direction_between covers %s neighbor" % str(case_data["name"]))
