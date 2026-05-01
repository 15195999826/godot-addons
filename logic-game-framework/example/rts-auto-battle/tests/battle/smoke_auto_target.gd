## RTS auto-target smoke (P2.4 acceptance) — 优先级标签让弓手跨过近距 melee 选远距 ranged
##
## 验证 RtsAutoTargetSystem 在以下场景中行为符合预期:
##   1. **优先级标签生效**: 弓手 target_priorities=[{ranged:100},{melee:10}], 同时存在
##      近距 melee + 远距 ranged 敌人时, _cached_target_id 指向 ranged (而不是按距离最近的 melee)
##   2. **Stance.HOLD_FIRE**: 不写 _cached_target_id (始终空)
##   3. **Stance.DEFENSIVE**: 仅候选距离 ≤ 1.5 × attack_range 的敌人; 全部敌人都更远时 cache 空
##   4. **无 priority fallback**: target_priorities=[] 时, 退化为距离最近 (与 P1.5 _select_nearest 同序)
##   5. **目标死亡当 tick 重扫**: cache 命中目标设 is_dead=true 后, 单 tick 后 cache 改指其他敌人
##
## 不接 procedure / strategy / controller — 直接驱动 AutoTargetSystem.tick(world, units)。
## 这一层在 smoke_rts_auto_battle 4v4 主 smoke (AC9) 验证不退化。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")


var _world: RtsWorldGameplayInstance = null
var _battle_map: RtsBattleMap = null
var _system: RtsAutoTargetSystem = null


func _ready() -> void:
	GameWorld.init()

	_battle_map = RtsBattleMap.new()
	add_child(_battle_map)

	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := RtsWorldGameplayInstance.new()
		w.start()
		return w
	) as RtsWorldGameplayInstance
	_world.set_grid(_battle_map.grid)

	_system = RtsAutoTargetSystem.new()

	if not _test_priority_overrides_distance():
		return
	if not _test_stance_hold_fire():
		return
	if not _test_stance_defensive():
		return
	if not _test_no_priority_falls_back_to_nearest():
		return
	if not _test_target_death_triggers_immediate_rescan():
		return

	_world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - priority + stance + alive-check + fallback")
	get_tree().quit(0)


# ========== 子测试 ==========

## 1. 优先级标签生效: 弓手跨过近距 melee 选远距 ranged
func _test_priority_overrides_distance() -> bool:
	var archer := _spawn_unit(Config.UnitClass.RANGED, 0, Vector2(50.0, 250.0))
	# 高 weight 给 ranged, 低 weight 给 melee — 期望: archer 选远距 ranged 敌人
	archer.target_priorities = [
		{"tag": "ranged", "weight": 100.0},
		{"tag": "melee", "weight": 10.0},
	]

	# 近距 melee (距离 70px)
	var melee_enemy := _spawn_unit(Config.UnitClass.MELEE, 1, Vector2(120.0, 250.0))
	# 远距 ranged (距离 200px) — 默认 unit_tags=["ranged","ground"]
	var ranged_enemy := _spawn_unit(Config.UnitClass.RANGED, 1, Vector2(250.0, 250.0))

	# 一致性自检: melee 确实更近, ranged 更远 (避免出生点笔误悄悄破坏 priority 测试)
	var d_melee: float = archer.position_2d.distance_to(melee_enemy.position_2d)
	var d_ranged: float = archer.position_2d.distance_to(ranged_enemy.position_2d)
	if d_melee >= d_ranged:
		return _fail("setup error: melee at %.1f >= ranged at %.1f" % [d_melee, d_ranged])

	var units: Array = [archer, melee_enemy, ranged_enemy]
	# 跑足 RESCAN_INTERVAL_TICKS+1 次, 走过一次完整 force_full_rescan
	for i in range(RtsAutoTargetSystem.RESCAN_INTERVAL_TICKS + 5):
		_system.tick(_world, units)

	if archer._cached_target_id != ranged_enemy.get_id():
		return _fail(
			"priority test: archer._cached_target_id='%s' (expected ranged='%s', melee='%s'); d_melee=%.1f d_ranged=%.1f" % [
				archer._cached_target_id, ranged_enemy.get_id(), melee_enemy.get_id(), d_melee, d_ranged,
			]
		)

	# Sanity: 敌方 (team 1) 单位反向也都有 cache (无 priority → 最近选 archer)
	if melee_enemy._cached_target_id != archer.get_id():
		return _fail("melee_enemy should target archer, got '%s'" % melee_enemy._cached_target_id)
	if ranged_enemy._cached_target_id != archer.get_id():
		return _fail("ranged_enemy should target archer, got '%s'" % ranged_enemy._cached_target_id)

	# Cleanup: 清场, 不污染下个子测试 (world.remove_actor 走 GameplayInstance.remove_actor 入口)
	_clear_world([archer, melee_enemy, ranged_enemy])
	print("auto_target subtest 1: priority OK (archer→ranged at %.1f over melee at %.1f)" % [d_ranged, d_melee])
	return true


## 2. HOLD_FIRE 不写 cache
func _test_stance_hold_fire() -> bool:
	var archer := _spawn_unit(Config.UnitClass.RANGED, 0, Vector2(50.0, 250.0))
	archer.stance = RtsUnitActor.Stance.HOLD_FIRE
	# 即使预先有 cache, HOLD_FIRE 也应清空
	archer._cached_target_id = "stale_id"

	var enemy := _spawn_unit(Config.UnitClass.MELEE, 1, Vector2(150.0, 250.0))
	var units: Array = [archer, enemy]

	for i in range(RtsAutoTargetSystem.RESCAN_INTERVAL_TICKS + 5):
		_system.tick(_world, units)

	if archer._cached_target_id != "":
		return _fail("HOLD_FIRE: archer._cached_target_id='%s' (expected empty)" % archer._cached_target_id)

	_clear_world([archer, enemy])
	print("auto_target subtest 2: HOLD_FIRE keeps cache empty OK")
	return true


## 3. DEFENSIVE 仅在 1.5×atk_range 内选目标
func _test_stance_defensive() -> bool:
	var archer := _spawn_unit(Config.UnitClass.RANGED, 0, Vector2(50.0, 250.0))
	archer.stance = RtsUnitActor.Stance.DEFENSIVE
	# RANGED attack_range = 120, 所以 DEFENSIVE engage range = 180

	# 远距敌人在 250px 外 — 超过 180 engage range
	var far_enemy := _spawn_unit(Config.UnitClass.MELEE, 1, Vector2(350.0, 250.0))
	var units_far_only: Array = [archer, far_enemy]

	for i in range(RtsAutoTargetSystem.RESCAN_INTERVAL_TICKS + 5):
		_system.tick(_world, units_far_only)

	if archer._cached_target_id != "":
		return _fail("DEFENSIVE far-only: cache='%s' (expected empty, far_enemy at distance %.1f > 180)" % [
			archer._cached_target_id, archer.position_2d.distance_to(far_enemy.position_2d),
		])

	# 加一个近距敌人 (在 150px 内)
	var near_enemy := _spawn_unit(Config.UnitClass.MELEE, 1, Vector2(180.0, 250.0))
	var units_with_near: Array = [archer, far_enemy, near_enemy]

	for i in range(RtsAutoTargetSystem.RESCAN_INTERVAL_TICKS + 5):
		_system.tick(_world, units_with_near)

	if archer._cached_target_id != near_enemy.get_id():
		return _fail("DEFENSIVE near+far: cache='%s' (expected near='%s'); near_dist=%.1f far_dist=%.1f" % [
			archer._cached_target_id, near_enemy.get_id(),
			archer.position_2d.distance_to(near_enemy.position_2d),
			archer.position_2d.distance_to(far_enemy.position_2d),
		])

	_clear_world([archer, far_enemy, near_enemy])
	print("auto_target subtest 3: DEFENSIVE engages only within 1.5×atk_range OK")
	return true


## 4. 无 priority fallback: 与 _select_nearest 同序
func _test_no_priority_falls_back_to_nearest() -> bool:
	var unit := _spawn_unit(Config.UnitClass.MELEE, 0, Vector2(50.0, 250.0))
	# 默认 target_priorities=[] (Phase 1 兼容), stance=AGGRESSIVE
	if not unit.target_priorities.is_empty():
		return _fail("default MELEE.target_priorities should be empty, got %s" % str(unit.target_priorities))

	# 远敌在 200, 近敌在 80 — 期望选近敌
	var far_enemy := _spawn_unit(Config.UnitClass.RANGED, 1, Vector2(250.0, 250.0))
	var near_enemy := _spawn_unit(Config.UnitClass.MELEE, 1, Vector2(130.0, 250.0))
	var units: Array = [unit, far_enemy, near_enemy]

	for i in range(RtsAutoTargetSystem.RESCAN_INTERVAL_TICKS + 5):
		_system.tick(_world, units)

	if unit._cached_target_id != near_enemy.get_id():
		return _fail("no-priority fallback: cache='%s' (expected near='%s')" % [
			unit._cached_target_id, near_enemy.get_id(),
		])

	_clear_world([unit, far_enemy, near_enemy])
	print("auto_target subtest 4: no-priority → nearest fallback OK")
	return true


## 5. cache 命中目标死亡时, 当 tick 立即触发重扫 (不等下个 RESCAN_INTERVAL_TICKS)
func _test_target_death_triggers_immediate_rescan() -> bool:
	var unit := _spawn_unit(Config.UnitClass.MELEE, 0, Vector2(50.0, 250.0))

	var enemy_a := _spawn_unit(Config.UnitClass.MELEE, 1, Vector2(130.0, 250.0))
	var enemy_b := _spawn_unit(Config.UnitClass.MELEE, 1, Vector2(180.0, 250.0))
	var units: Array = [unit, enemy_a, enemy_b]

	# 第一次 tick: enemy_a 更近, unit cache 应指向 enemy_a
	for i in range(RtsAutoTargetSystem.RESCAN_INTERVAL_TICKS + 5):
		_system.tick(_world, units)
	if unit._cached_target_id != enemy_a.get_id():
		return _fail("immediate-rescan setup: unit→enemy_a, got '%s' (expected '%s')" % [
			unit._cached_target_id, enemy_a.get_id(),
		])

	# 杀掉 enemy_a (mark_dead 模拟战斗中目标被击毙)
	enemy_a.mark_dead()

	# 仅一个 tick: 应该立即清空旧 cache + 重扫 → 切到 enemy_b (不需要等 20 tick)
	_system.tick(_world, units)

	if unit._cached_target_id != enemy_b.get_id():
		return _fail("immediate-rescan after death: cache='%s' (expected enemy_b='%s')" % [
			unit._cached_target_id, enemy_b.get_id(),
		])

	_clear_world([unit, enemy_a, enemy_b])
	print("auto_target subtest 5: dead-cache triggers immediate rescan OK")
	return true


# ========== Helpers ==========

func _spawn_unit(unit_class: Config.UnitClass, team_id: int, pos: Vector2) -> RtsUnitActor:
	var actor := RtsUnitActor.new(unit_class)
	actor.set_team_id(team_id)
	_world.add_actor(actor)
	actor.position_2d = pos
	return actor


## 在子测试结束时清理 world, 让下一子测试从空状态开始 (避免 actor 串台)。
func _clear_world(actors: Array) -> void:
	for a in actors:
		if a is Actor:
			_world.remove_actor((a as Actor).get_id())


func _fail(reason: String) -> bool:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
	return false
