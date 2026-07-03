## Smoke: Knockback Punch (Tier 1 #4) — forced displacement + collision pattern
##
## 验证 9 个 case:
##   1. free push       → target 移动 1 格, ActorDisplacedEvent
##   2. edge            → target 不动, PushBlockedEvent(blocked_by="edge"), 1pt collision damage to target
##   3. stone_wall      → target 不动, PushBlockedEvent(blocked_by="actor", blocker=wall),
##                        target 受 wall.dealt_to_pusher (=1), wall hp 不变 (taken=0)
##   4. character blocker → target 不动, PushBlockedEvent, target +1, blocker +1
##   5a. non-neighbor (out of range) → can_use_skill_on() == false
##   5b. direct target stone_wall    → can_use_skill_on() == false (ALLOWED_TARGET_KINDS=["Character"])
##   6. killed by base damage  → 整段 push 跳过 (0 ActorDisplaced / 0 PushBlocked / 0 collision)
##   7. collision deterministic → N 次 trial, 每次 collision damage 都 == 1.0 (无暴击)
##   8. action lock metadata/status → push event 写 action_lock_duration_ms, target 获得 status_action_lock
##   9. cant_act gate → ATB 满但不决策不 reset; action lock 到期后恢复主动行动
extends Node


const COLLISION_DETERMINISTIC_RUNS := 20


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: Knockback Punch ===")

	if not _phase_can_use_skill_on():
		return
	if not _phase_free_push():
		return
	if not _phase_edge():
		return
	if not _phase_stone_wall_blocker():
		return
	if not _phase_character_blocker():
		return
	if not _phase_killed_by_base_damage():
		return
	if not _phase_collision_deterministic():
		return
	if not _phase_action_lock_metadata_and_status():
		return
	if not _phase_action_lock_blocks_atb_then_expires():
		return

	print("SMOKE_TEST_RESULT: PASS - all knockback_punch checks passed")
	get_tree().quit(0)


# ============================================================
# Phase 1: can_use_skill_on (cases 5a, 5b)
# ============================================================

func _phase_can_use_skill_on() -> bool:
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()

	var battle := GameWorld.create_instance(func() -> GameplayInstance:
		var inst := HexWorldGameplayInstance.new()
		var grid_cfg := GridMapConfig.new()
		grid_cfg.grid_type = GridMapConfig.GridType.HEX
		grid_cfg.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		grid_cfg.rows = 9
		grid_cfg.columns = 9
		inst.configure_grid(grid_cfg)
		return inst
	) as HexWorldGameplayInstance

	if battle == null:
		_fail("can_use_skill_on phase: failed to create instance")
		return false

	var caster := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(caster)
	caster.hex_position = HexCoord.new(0, 0)
	caster.set_team_id(0)

	var adj_target := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(adj_target)
	adj_target.hex_position = HexCoord.new(1, 0)
	adj_target.set_team_id(1)

	var far_target := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(far_target)
	far_target.hex_position = HexCoord.new(3, 0)
	far_target.set_team_id(1)

	var wall := HexBattleStoneWall.create()
	battle.add_actor(wall)
	wall.hex_position = HexCoord.new(0, 1)

	var kp := Ability.new(HexBattleKnockbackPunch.ABILITY, caster.get_id())

	var passed := true

	# 5a: out of range (distance 3 > range 1) → false
	if battle.can_use_skill_on(caster, kp, far_target) != false:
		_fail("can_use_skill_on(KP, far_target) expected false (out of range)")
		passed = false

	# 5b: stone_wall as direct target → false (ALLOWED_TARGET_KINDS=["Character"])
	if battle.can_use_skill_on(caster, kp, wall) != false:
		_fail("can_use_skill_on(KP, wall) expected false (env not in allowedTargetKinds)")
		passed = false

	# Sanity: adjacent enemy character → true
	if battle.can_use_skill_on(caster, kp, adj_target) != true:
		_fail("can_use_skill_on(KP, adj_target) expected true")
		passed = false

	GameWorld.destroy()

	if passed:
		print("  [PASS] can_use_skill_on (range / kind / sanity)")
	return passed


# ============================================================
# Phase 2: free push (case 1)
# ============================================================

func _phase_free_push() -> bool:
	var scene := {
		"map": {"rows": 9, "cols": 9},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": 10, "hp": 100},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}
	var actions: Array[Dictionary] = [
		{"caster": "caster", "skill": HexBattleKnockbackPunch.ABILITY, "target": "enemy_0"},
	]
	var result := HexBattleSkillScenarioHarness.run_with_actions(scene, actions, 80)
	if not result.get("success", false):
		_fail("free_push: harness failed: %s" % str(result.get("errors", [])))
		return false

	var enemy_id := str((result["enemy_ids"] as Array)[0])
	var replay: Dictionary = result.get("replay", {})

	var displaced := _find_events(replay, "actor_displaced")
	if displaced.size() != 1:
		_fail("free_push: expected 1 actor_displaced, got %d" % displaced.size())
		return false
	var disp: Dictionary = displaced[0]
	if str(disp.get("actor_id", "")) != enemy_id:
		_fail("free_push: displaced actor_id mismatch")
		return false
	if str(disp.get("displacement_kind", "")) != "knockback":
		_fail("free_push: displacement_kind expected 'knockback'")
		return false
	if int((disp["from_hex"] as Dictionary)["q"]) != 1 or int((disp["from_hex"] as Dictionary)["r"]) != 0:
		_fail("free_push: from_hex expected (1,0) got %s" % str(disp.get("from_hex")))
		return false
	if int((disp["to_hex"] as Dictionary)["q"]) != 2 or int((disp["to_hex"] as Dictionary)["r"]) != 0:
		_fail("free_push: to_hex expected (2,0) got %s" % str(disp.get("to_hex")))
		return false

	if _find_events(replay, "push_blocked").size() != 0:
		_fail("free_push: expected 0 push_blocked events")
		return false

	# 仅 1 个 damage event (基础伤害)
	var dmgs := _filter_damage(replay, enemy_id)
	if dmgs.size() != 1:
		_fail("free_push: expected 1 damage event on target, got %d" % dmgs.size())
		return false

	print("  [PASS] free push: target moved (1,0)→(2,0), 1 damage, no blocked")
	return true


# ============================================================
# Phase 3: edge (case 2)
# ============================================================

func _phase_edge() -> bool:
	# map 9x9 → q ∈ [-4, 4]; caster (3,0), target (4,0), push east → (5,0) 无 tile
	var scene := {
		"map": {"rows": 9, "cols": 9},
		"caster":  {"class": "WARRIOR", "pos": [3, 0], "atk": 10, "hp": 100},
		"enemies": [{"class": "WARRIOR", "pos": [4, 0], "hp": 1000}],
	}
	var actions: Array[Dictionary] = [
		{"caster": "caster", "skill": HexBattleKnockbackPunch.ABILITY, "target": "enemy_0"},
	]
	var result := HexBattleSkillScenarioHarness.run_with_actions(scene, actions, 80)
	if not result.get("success", false):
		_fail("edge: harness failed: %s" % str(result.get("errors", [])))
		return false

	var enemy_id := str((result["enemy_ids"] as Array)[0])
	var replay: Dictionary = result.get("replay", {})

	if _find_events(replay, "actor_displaced").size() != 0:
		_fail("edge: expected 0 actor_displaced (target should stay at (4,0))")
		return false

	var blocked := _find_events(replay, "push_blocked")
	if blocked.size() != 1:
		_fail("edge: expected 1 push_blocked, got %d" % blocked.size())
		return false
	var bl: Dictionary = blocked[0]
	if str(bl.get("blocked_by", "")) != "edge":
		_fail("edge: blocked_by expected 'edge', got %s" % bl.get("blocked_by"))
		return false
	if str(bl.get("blocker_actor_id", "_")) != "":
		_fail("edge: blocker_actor_id expected empty, got %s" % bl.get("blocker_actor_id"))
		return false
	if int((bl["attempted_to_hex"] as Dictionary).get("q", -99)) != 5:
		_fail("edge: attempted_to_hex.q expected 5, got %s" % str(bl.get("attempted_to_hex")))
		return false

	# 2 个 damage event on target: 基础 + 1pt collision (default_wall.dealt_to_pusher)
	var dmgs := _filter_damage(replay, enemy_id)
	if dmgs.size() != 2:
		_fail("edge: expected 2 damage events on target, got %d" % dmgs.size())
		return false
	if not _has_damage_amount(dmgs, 1.0):
		_fail("edge: expected a damage event with amount=1.0 (collision), got: %s" % _summarize_amounts(dmgs))
		return false

	print("  [PASS] edge: target stays at (4,0), 1 push_blocked(edge), 2 damages (base+1)")
	return true


# ============================================================
# Phase 4: stone_wall blocker (case 3)
# ============================================================

func _phase_stone_wall_blocker() -> bool:
	var scene := {
		"map": {"rows": 9, "cols": 9},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": 10, "hp": 100},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
		"environment": [{"type": "stone_wall", "pos": [2, 0]}],
	}
	var actions: Array[Dictionary] = [
		{"caster": "caster", "skill": HexBattleKnockbackPunch.ABILITY, "target": "enemy_0"},
	]
	var result := HexBattleSkillScenarioHarness.run_with_actions(scene, actions, 80)
	if not result.get("success", false):
		_fail("stone_wall: harness failed: %s" % str(result.get("errors", [])))
		return false

	var enemy_id := str((result["enemy_ids"] as Array)[0])
	var env_ids: Array = result.get("environment_ids", [])
	if env_ids.size() != 1:
		_fail("stone_wall: expected 1 environment id")
		return false
	var wall_id := str(env_ids[0])
	var replay: Dictionary = result.get("replay", {})

	if _find_events(replay, "actor_displaced").size() != 0:
		_fail("stone_wall: expected 0 actor_displaced (target stays)")
		return false

	var blocked := _find_events(replay, "push_blocked")
	if blocked.size() != 1:
		_fail("stone_wall: expected 1 push_blocked, got %d" % blocked.size())
		return false
	if str(blocked[0].get("blocked_by", "")) != "actor":
		_fail("stone_wall: blocked_by expected 'actor'")
		return false
	if str(blocked[0].get("blocker_actor_id", "")) != wall_id:
		_fail("stone_wall: blocker_actor_id expected wall_id=%s, got %s" % [
			wall_id, blocked[0].get("blocker_actor_id")
		])
		return false

	# target: 基础 + 1pt collision
	var target_dmgs := _filter_damage(replay, enemy_id)
	if target_dmgs.size() != 2:
		_fail("stone_wall: expected 2 damage events on target, got %d" % target_dmgs.size())
		return false
	if not _has_damage_amount(target_dmgs, 1.0):
		_fail("stone_wall: expected target to receive a 1.0 collision damage")
		return false

	# wall: hp 不变 (taken_on_blocked_push=0), 不应有任何 damage event 减少其 hp
	# stone_wall 默认 damage_taken_on_blocked_push=0 → wall 不会收到 collision damage event
	if not _wall_hp_unchanged(replay, wall_id):
		_fail("stone_wall: wall hp should be unchanged (taken=0)")
		return false

	print("  [PASS] stone_wall blocker: target stays, target+1, wall hp unchanged")
	return true


# ============================================================
# Phase 5: character blocker (case 4)
# ============================================================

func _phase_character_blocker() -> bool:
	# caster (0,0), target enemy_0 (1,0), blocker enemy_1 (2,0)
	var scene := {
		"map": {"rows": 9, "cols": 9},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": 10, "hp": 100},
		"enemies": [
			{"class": "WARRIOR", "pos": [1, 0], "hp": 1000},
			{"class": "WARRIOR", "pos": [2, 0], "hp": 1000},
		],
	}
	var actions: Array[Dictionary] = [
		{"caster": "caster", "skill": HexBattleKnockbackPunch.ABILITY, "target": "enemy_0"},
	]
	var result := HexBattleSkillScenarioHarness.run_with_actions(scene, actions, 80)
	if not result.get("success", false):
		_fail("character_blocker: harness failed: %s" % str(result.get("errors", [])))
		return false

	var enemy_ids: Array = result["enemy_ids"]
	var target_id := str(enemy_ids[0])
	var blocker_id := str(enemy_ids[1])
	var replay: Dictionary = result.get("replay", {})

	if _find_events(replay, "actor_displaced").size() != 0:
		_fail("character_blocker: expected 0 actor_displaced")
		return false

	var blocked := _find_events(replay, "push_blocked")
	if blocked.size() != 1:
		_fail("character_blocker: expected 1 push_blocked")
		return false
	if str(blocked[0].get("blocker_actor_id", "")) != blocker_id:
		_fail("character_blocker: blocker_actor_id mismatch")
		return false

	# target: 基础 + 1 collision; blocker: 1 collision only
	var target_dmgs := _filter_damage(replay, target_id)
	if target_dmgs.size() != 2:
		_fail("character_blocker: expected 2 damage events on target, got %d" % target_dmgs.size())
		return false
	if not _has_damage_amount(target_dmgs, 1.0):
		_fail("character_blocker: target should have 1.0 collision damage")
		return false

	var blocker_dmgs := _filter_damage(replay, blocker_id)
	if blocker_dmgs.size() != 1:
		_fail("character_blocker: expected 1 damage event on blocker, got %d" % blocker_dmgs.size())
		return false
	if abs(float(blocker_dmgs[0].get("damage", -1.0)) - 1.0) > 0.01:
		_fail("character_blocker: blocker damage expected 1.0, got %s" % str(blocker_dmgs[0].get("damage")))
		return false

	print("  [PASS] character blocker: target+1, blocker+1, no displaced")
	return true


# ============================================================
# Phase 6: killed by base damage (case 6)
# ============================================================

func _phase_killed_by_base_damage() -> bool:
	# caster atk=200, target hp=10 → 基础伤害必杀
	var scene := {
		"map": {"rows": 9, "cols": 9},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": 200, "hp": 100},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 10}],
	}
	var actions: Array[Dictionary] = [
		{"caster": "caster", "skill": HexBattleKnockbackPunch.ABILITY, "target": "enemy_0"},
	]
	var result := HexBattleSkillScenarioHarness.run_with_actions(scene, actions, 80)
	if not result.get("success", false):
		_fail("killed_by_base: harness failed: %s" % str(result.get("errors", [])))
		return false

	var replay: Dictionary = result.get("replay", {})

	if _find_events(replay, "actor_displaced").size() != 0:
		_fail("killed_by_base: expected 0 actor_displaced")
		return false
	if _find_events(replay, "push_blocked").size() != 0:
		_fail("killed_by_base: expected 0 push_blocked (target dead before push)")
		return false

	# target 应该死了 → death event
	var deaths := _find_events(replay, "death")
	if deaths.size() != 1:
		_fail("killed_by_base: expected 1 death event, got %d" % deaths.size())
		return false

	# 没有 collision damage (即只有 base damage event)
	var enemy_id := str((result["enemy_ids"] as Array)[0])
	var dmgs := _filter_damage(replay, enemy_id)
	if dmgs.size() != 1:
		_fail("killed_by_base: expected 1 damage event (base only), got %d" % dmgs.size())
		return false

	print("  [PASS] killed by base damage: push skipped, target died")
	return true


# ============================================================
# Phase 7: collision deterministic (case 7)
# ============================================================

func _phase_collision_deterministic() -> bool:
	# stone_wall blocker setup, 跑 N 次, 验证每次 collision damage 都恰好 == 1.0
	for run_idx in range(COLLISION_DETERMINISTIC_RUNS):
		var scene := {
			"map": {"rows": 9, "cols": 9},
			"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": 10, "hp": 100},
			"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
			"environment": [{"type": "stone_wall", "pos": [2, 0]}],
		}
		var actions: Array[Dictionary] = [
			{"caster": "caster", "skill": HexBattleKnockbackPunch.ABILITY, "target": "enemy_0"},
		]
		var result := HexBattleSkillScenarioHarness.run_with_actions(scene, actions, 80)
		if not result.get("success", false):
			_fail("deterministic run %d: harness failed" % run_idx)
			return false

		var enemy_id := str((result["enemy_ids"] as Array)[0])
		var replay: Dictionary = result.get("replay", {})
		var target_dmgs := _filter_damage(replay, enemy_id)
		# 找出值为 1.0 的 collision damage event (atk=10, crit=15, 都 ≠ 1, 故 1.0 必是 collision)
		var collision_count := 0
		for ev in target_dmgs:
			var amt := float(ev.get("damage", -1.0))
			if abs(amt - 1.0) < 0.01:
				collision_count += 1
			elif abs(amt - 10.0) < 0.01 or abs(amt - 15.0) < 0.01:
				pass  # 基础伤害 (10 普通 / 15 暴击)
			else:
				_fail("deterministic run %d: unexpected damage amount %f" % [run_idx, amt])
				return false
		if collision_count != 1:
			_fail("deterministic run %d: expected exactly 1 collision damage (1.0), got %d" % [
				run_idx, collision_count
			])
			return false

	print("  [PASS] collision deterministic: %d runs, all collisions == 1.0" % COLLISION_DETERMINISTIC_RUNS)
	return true


# ============================================================
# Phase 8: action lock metadata/status (case 8)
# ============================================================

func _phase_action_lock_metadata_and_status() -> bool:
	var scene := {
		"map": {"rows": 9, "cols": 9},
		"caster":  {"class": "WARRIOR", "pos": [0, 0], "atk": 10, "hp": 100},
		"enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
	}
	var actions: Array[Dictionary] = [
		{"caster": "caster", "skill": HexBattleKnockbackPunch.ABILITY, "target": "enemy_0"},
	]
	var result := HexBattleSkillScenarioHarness.run_with_actions(scene, actions, 80)
	if not result.get("success", false):
		_fail("action_lock_metadata: harness failed: %s" % str(result.get("errors", [])))
		return false

	var enemy_id := str((result["enemy_ids"] as Array)[0])
	var replay: Dictionary = result.get("replay", {})
	var expected_duration := HexBattleActionLockStatus.compute_displacement_duration_ms(1, 0.0)

	var displaced := _find_events(replay, "actor_displaced")
	if displaced.size() != 1:
		_fail("action_lock_metadata: expected 1 actor_displaced, got %d" % displaced.size())
		return false
	var disp: Dictionary = displaced[0]
	if int(disp.get("actual_distance", -1)) != 1:
		_fail("action_lock_metadata: actual_distance expected 1, got %s" % str(disp.get("actual_distance")))
		return false
	if abs(float(disp.get("action_lock_duration_ms", -1.0)) - expected_duration) > 0.01:
		_fail("action_lock_metadata: action_lock_duration_ms expected %.1f, got %s" % [
			expected_duration, str(disp.get("action_lock_duration_ms"))
		])
		return false
	if abs(float(disp.get("collision_action_lock_bonus_ms", -1.0))) > 0.01:
		_fail("action_lock_metadata: collision_action_lock_bonus_ms expected 0")
		return false

	var granted := _find_ability_granted(replay, enemy_id, HexBattleActionLockStatus.CONFIG_ID)
	if granted.is_empty():
		_fail("action_lock_metadata: expected AbilityGranted(status_action_lock) on pushed target")
		return false
	var ability: Dictionary = granted.get("ability", {}) as Dictionary
	var metadata: Dictionary = ability.get("metadata", {}) as Dictionary
	if str(metadata.get("reason", "")) != HexBattleActionLockStatus.REASON_DISPLACEMENT_STAGGER:
		_fail("action_lock_metadata: status reason expected displacement_stagger")
		return false
	if abs(float(metadata.get("duration_ms", -1.0)) - expected_duration) > 0.01:
		_fail("action_lock_metadata: status duration metadata mismatch")
		return false
	var ability_tags: Array = ability.get("abilityTags", [])
	if not ability_tags.has(HexBattleActionLockStatus.TAG_ACTION_LOCKED):
		_fail("action_lock_metadata: abilityTags missing action_locked")
		return false
	if not ability_tags.has(HexBattleActionLockStatus.REASON_DISPLACEMENT_STAGGER):
		_fail("action_lock_metadata: abilityTags missing displacement_stagger")
		return false

	print("  [PASS] action lock metadata/status: event duration + status grant")
	return true


# ============================================================
# Phase 9: action lock gates ATB without reset, then expires (case 9)
# ============================================================

func _phase_action_lock_blocks_atb_then_expires() -> bool:
	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()

	var battle := GameWorld.create_instance(func() -> GameplayInstance:
		var inst := HexWorldGameplayInstance.new()
		var grid_cfg := GridMapConfig.new()
		grid_cfg.grid_type = GridMapConfig.GridType.HEX
		grid_cfg.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		grid_cfg.rows = 9
		grid_cfg.columns = 9
		inst.configure_grid(grid_cfg)
		return inst
	) as HexWorldGameplayInstance
	if battle == null:
		_fail("action_lock_gate: failed to create battle")
		return false

	var caster := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(caster)
	caster.set_team_id(0)
	caster.equip_abilities()
	if not battle.grid.place_occupant(HexCoord.new(0, 0), caster):
		_fail("action_lock_gate: failed to place caster")
		GameWorld.destroy()
		return false
	caster.hex_position = HexCoord.new(0, 0)

	var enemy := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(enemy)
	enemy.set_team_id(1)
	enemy.equip_abilities()
	enemy.attribute_set.set_max_hp_base(1000.0)
	enemy.attribute_set.set_hp_base(1000.0)
	if not battle.grid.place_occupant(HexCoord.new(1, 0), enemy):
		_fail("action_lock_gate: failed to place enemy")
		GameWorld.destroy()
		return false
	enemy.hex_position = HexCoord.new(1, 0)

	battle.start()

	var duration := HexBattleActionLockStatus.compute_displacement_duration_ms(1, 0.0)
	var action_lock := Ability.new(
		HexBattleActionLockStatus.create_config(
			duration,
			HexBattleActionLockStatus.REASON_DISPLACEMENT_STAGGER,
			HexBattleActionLockStatus.REASON_DISPLACEMENT_STAGGER
		),
		caster.get_id(),
		enemy.get_id()
	)
	caster.ability_set.grant_ability(action_lock, battle)
	caster.accumulate_atb(100000.0)
	if caster.get_atb_gauge() < CharacterActor.ATB_FULL:
		_fail("action_lock_gate: setup failed, caster ATB not full")
		GameWorld.destroy()
		return false

	var skill := caster.get_skill_ability()
	var direct_event := GameEvent.AbilityActivate.create(
		skill.id, caster.get_id(), 0.0, enemy.get_id()
	).to_dict()
	caster.ability_set.receive_event(direct_event, battle)
	if skill.get_executing_instances().size() != 0:
		_fail("action_lock_gate: direct active skill activation should be blocked by cant_act")
		GameWorld.destroy()
		return false

	var left_team: Array[CharacterActor] = [caster]
	var right_team: Array[CharacterActor] = [enemy]
	var procedure := HexBattleProcedure.new(battle, left_team, right_team, {
		"logging": false,
		"recording": false,
	})
	procedure.start()

	procedure.tick_once()
	if not caster.ability_set.has_tag(HexBattleActionLockStatus.TAG_CANT_ACT):
		_fail("action_lock_gate: cant_act expired too early")
		GameWorld.destroy()
		return false
	if caster.get_atb_gauge() < CharacterActor.ATB_FULL:
		_fail("action_lock_gate: ATB reset while cant_act was active")
		GameWorld.destroy()
		return false

	var recovered_and_acted := false
	for _i in range(10):
		procedure.tick_once()
		if not caster.ability_set.has_tag(HexBattleActionLockStatus.TAG_CANT_ACT):
			if caster.get_atb_gauge() >= CharacterActor.ATB_FULL:
				_fail("action_lock_gate: action lock expired but caster did not spend ready action")
				GameWorld.destroy()
				return false
			recovered_and_acted = true
			break

	if not recovered_and_acted:
		_fail("action_lock_gate: action lock did not expire within expected ticks")
		GameWorld.destroy()
		return false

	GameWorld.destroy()
	print("  [PASS] action lock gate: ATB held during cant_act, action resumes after expiry")
	return true


# ============================================================
# Helpers
# ============================================================

func _find_events(replay: Dictionary, kind: String) -> Array:
	var result: Array = []
	var frames: Array = replay.get("timeline", [])
	for frame in frames:
		var events: Array = (frame as Dictionary).get("events", [])
		for ev in events:
			var ev_dict := ev as Dictionary
			if ev_dict == null:
				continue
			if str(ev_dict.get("kind", "")) == kind:
				result.append(ev_dict)
	return result


func _filter_damage(replay: Dictionary, target_id: String) -> Array:
	var result: Array = []
	for ev in _find_events(replay, "damage"):
		if str((ev as Dictionary).get("target_actor_id", "")) == target_id:
			result.append(ev)
	return result


func _find_ability_granted(replay: Dictionary, actor_id: String, config_id: String) -> Dictionary:
	for ev in _find_events(replay, GameEvent.ABILITY_GRANTED_EVENT):
		var ev_dict := ev as Dictionary
		if str(ev_dict.get("actorId", "")) != actor_id:
			continue
		var ability: Dictionary = ev_dict.get("ability", {}) as Dictionary
		if str(ability.get("configId", "")) == config_id:
			return ev_dict
	return {}


func _has_damage_amount(events: Array, amount: float) -> bool:
	for ev in events:
		if abs(float((ev as Dictionary).get("damage", -1.0)) - amount) < 0.01:
			return true
	return false


func _summarize_amounts(events: Array) -> String:
	var parts: Array[String] = []
	for ev in events:
		parts.append(str((ev as Dictionary).get("damage", "?")))
	return "[" + ", ".join(parts) + "]"


func _wall_hp_unchanged(replay: Dictionary, wall_id: String) -> bool:
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
			# 任何 hp 变化都视为失败 (V1 stone_wall taken=0, 不应被改)
			return false
	return true


func _fail(msg: String) -> void:
	print("  [FAIL] %s" % msg)
	print("SMOKE_TEST_RESULT: FAIL - %s" % msg)
	get_tree().quit(1)
