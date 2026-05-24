## Smoke: WallBreaker — EnvironmentActor opt-in 通路验证
##
## 验证两件事:
##   1. can_use_skill_on() 按 metadata.allowedTargetKinds 正确放行/拦截
##      - Strike 默认 ["Character"]: 选墙 → false
##      - WallBreaker 显式 ["Character", "Environment"]: 选墙 → true; 选 character → true
##   2. 经 harness 用 WallBreaker 打 environment_0, replay 含 DamageEvent
##      且墙 hp 减少 (Damage 路径对 env 平权已验证, 这里只复用)
##
## "墙被打死后留在 world" 不在本 smoke 范围 — StoneWall 用 INDESTRUCTIBLE_HP 数据驱动,
## 死亡留 world 由 LGF 既有死亡测试覆盖 (见 2026-04-26-death-keeps-actor)。
extends Node


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: WallBreaker EnvironmentActor opt-in ===")

	if not _phase_can_use_skill_on():
		return
	if not _phase_harness_hits_wall():
		return

	print("SMOKE_TEST_RESULT: PASS - all wall_breaker checks passed")
	get_tree().quit(0)


# ============================================================
# Phase 1: 直接 can_use_skill_on 三态校验
# ============================================================

func _phase_can_use_skill_on() -> bool:
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()

	var battle := GameWorld.create_instance(func() -> GameplayInstance:
		var inst := HexWorldGameplayInstance.new()
		var grid_cfg := GridMapConfig.new()
		grid_cfg.grid_type = GridMapConfig.GridType.HEX
		grid_cfg.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		grid_cfg.rows = 3
		grid_cfg.columns = 3
		inst.configure_grid(grid_cfg)
		return inst
	) as HexWorldGameplayInstance

	if battle == null:
		_fail("failed to create HexWorldGameplayInstance for can_use_skill_on phase")
		return false

	var caster := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(caster)
	caster.hex_position = HexCoord.new(0, 0)
	caster.set_team_id(0)

	var character_target := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(character_target)
	character_target.hex_position = HexCoord.new(1, 0)
	character_target.set_team_id(1)

	var wall := HexBattleStoneWall.create()
	battle.add_actor(wall)
	wall.hex_position = HexCoord.new(0, 1)

	var strike := Ability.new(HexBattleStrike.ABILITY, caster.get_id())
	var wallbreaker := Ability.new(HexBattleWallBreaker.ABILITY, caster.get_id())
	var cleanse := Ability.new(HexBattleCleanse.ABILITY, caster.get_id())
	var holy_heal := Ability.new(HexBattleHolyHeal.ABILITY, caster.get_id())

	var passed := true

	# Strike on wall → false (default ["Character"], wall.type == "Environment")
	if battle.can_use_skill_on(caster, strike, wall) != false:
		_fail("can_use_skill_on(Strike, wall) expected false, got true")
		passed = false

	# WallBreaker on wall → true (allowedTargetKinds includes "Environment")
	if battle.can_use_skill_on(caster, wallbreaker, wall) != true:
		_fail("can_use_skill_on(WallBreaker, wall) expected true, got false")
		passed = false

	# WallBreaker on character target → true (allowedTargetKinds includes "Character")
	if battle.can_use_skill_on(caster, wallbreaker, character_target) != true:
		_fail("can_use_skill_on(WallBreaker, character_target) expected true, got false")
		passed = false

	# Cleanse declares ["ally", "self"], so self-target is legal.
	if battle.can_use_skill_on(caster, cleanse, caster) != true:
		_fail("can_use_skill_on(Cleanse, self) expected true, got false")
		passed = false

	# Ally skills without "self" still cannot target self.
	if battle.can_use_skill_on(caster, holy_heal, caster) != false:
		_fail("can_use_skill_on(HolyHeal, self) expected false, got true")
		passed = false

	# Cleanse remains ally-only; enemy targets are still illegal.
	if battle.can_use_skill_on(caster, cleanse, character_target) != false:
		_fail("can_use_skill_on(Cleanse, enemy) expected false, got true")
		passed = false

	GameWorld.destroy()

	if passed:
		print("  [PASS] can_use_skill_on eligibility check")
	return passed


# ============================================================
# Phase 2: harness 用 WallBreaker 打 environment_0, 验证 replay 有 damage 且 wall hp 减少
# ============================================================

func _phase_harness_hits_wall() -> bool:
	var scene_config := {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [2, 0], "hp": 1000}],
		"environment": [
			{"type": "stone_wall", "pos": [0, 1]},
		],
	}
	var actions: Array[Dictionary] = [
		{"caster": "caster", "skill": HexBattleWallBreaker.ABILITY, "target": "environment_0"},
	]

	var result := HexBattleSkillScenarioHarness.run_with_actions(scene_config, actions, 80)

	if not result.get("success", false):
		_fail("harness run failed: %s" % str(result.get("errors", [])))
		return false

	var environment_ids: Array = result.get("environment_ids", [])
	if environment_ids.size() != 1 or str(environment_ids[0]).is_empty():
		_fail("expected 1 environment id, got: %s" % str(environment_ids))
		return false
	var wall_id := str(environment_ids[0])

	var replay: Dictionary = result.get("replay", {})
	var damage_to_wall := _count_damage_events_for(replay, wall_id)
	if damage_to_wall <= 0:
		_fail("expected DamageEvent on wall_id=%s, got 0" % wall_id)
		return false

	# 墙在 wall_breaker 命中后 hp 应降至 INDESTRUCTIBLE_HP 之下,
	# 但 harness 的 final_actor_hps 只收 character;
	# 用 replay frames 里的属性变化事件检查更直接。
	if not _replay_has_wall_hp_drop(replay, wall_id):
		_fail("expected wall hp to drop in replay frames, but no hp change found for %s" % wall_id)
		return false

	print("  [PASS] WallBreaker hits wall via harness (damage events: %d)" % damage_to_wall)
	return true


# ============================================================
# Helpers
# ============================================================

func _count_damage_events_for(replay: Dictionary, target_id: String) -> int:
	# DamageEvent.kind 是字符串字面量 "damage" (battle_events.gd:39),
	# 没有专门的 const 常量, 这里直接对照字面量。
	var count := 0
	var frames: Array = replay.get("timeline", [])
	for frame in frames:
		var events: Array = (frame as Dictionary).get("events", [])
		for ev in events:
			var ev_dict := ev as Dictionary
			if ev_dict == null:
				continue
			if str(ev_dict.get("kind", "")) != "damage":
				continue
			if str(ev_dict.get("target_actor_id", "")) == target_id:
				count += 1
	return count


func _replay_has_wall_hp_drop(replay: Dictionary, wall_id: String) -> bool:
	var frames: Array = replay.get("timeline", [])
	for frame in frames:
		var events: Array = (frame as Dictionary).get("events", [])
		for ev in events:
			var ev_dict := ev as Dictionary
			if ev_dict == null:
				continue
			if str(ev_dict.get("kind", "")) != GameEvent.ATTRIBUTE_CHANGED_EVENT:
				continue
			if str(ev_dict.get("actorId", "")) != wall_id:
				continue
			if str(ev_dict.get("attribute", "")) != "hp":
				continue
			var old_value := float(ev_dict.get("oldValue", 0.0))
			var new_value := float(ev_dict.get("newValue", 0.0))
			if new_value < old_value:
				return true
	return false


func _fail(msg: String) -> void:
	print("  [FAIL] %s" % msg)
	print("SMOKE_TEST_RESULT: FAIL - %s" % msg)
	get_tree().quit(1)
