## Smoke: TARGETING 双入口协议 —— can_use_skill_on(ACTOR/SELF) vs can_use_skill_at(COORD)
##
## codex W7-P2 修复的回归网:
##   - COORD 型技能(锥形)不得从 can_use_skill_on 放行(绕过 coord 模式/has_tile 检查)
##   - can_use_skill_at 裁决: coord 模式 + 在图内 + 施法距离
##   - ACTOR 型技能走 can_use_skill_at 必须被拒(wrong-mode)
extends Node


func _ready() -> void:
	Log.set_level(Log.LogLevel.WARNING)
	print("=== Smoke Test: TARGETING dual-entry protocol ===")

	GameWorld.init()
	HexBattleAllSkills.register_all_timelines()

	var battle := GameWorld.create_instance(func() -> GameplayInstance:
		var inst := HexWorldGameplayInstance.new()
		var grid_cfg := GridMapConfig.new()
		grid_cfg.grid_type = GridMapConfig.GridType.HEX
		grid_cfg.draw_mode = GridMapConfig.DrawMode.ROW_COLUMN
		grid_cfg.rows = 3
		grid_cfg.columns = 6
		inst.configure_grid(grid_cfg)
		return inst
	) as HexWorldGameplayInstance

	if battle == null:
		_fail("failed to create HexWorldGameplayInstance")
		return

	var caster := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(caster)
	caster.hex_position = HexCoord.new(0, 0)
	caster.set_team_id(0)

	var enemy := CharacterActor.new(HexBattleClassConfig.CharacterClass.WARRIOR)
	battle.add_actor(enemy)
	enemy.hex_position = HexCoord.new(1, 0)
	enemy.set_team_id(1)

	var grid_cone := Ability.new(HexBattleGridCone.ABILITY, caster.get_id())
	var strike := Ability.new(HexBattleStrike.ABILITY, caster.get_id())

	var passed := true

	# 1. COORD 技能走 actor 入口 → 拒绝
	if battle.can_use_skill_on(caster, grid_cone, enemy) != false:
		_fail("can_use_skill_on(GridCone, enemy) expected false (COORD 必须走 at 入口)")
		passed = false

	# 2. COORD 技能对合法格(敌人站位, 距离 1 ≤ range 3) → 放行
	if battle.can_use_skill_at(caster, grid_cone, enemy.hex_position) != true:
		_fail("can_use_skill_at(GridCone, (1,0)) expected true")
		passed = false

	# 3. 超射程(在图内, 距离 4 > range 3) → 拒绝
	if battle.can_use_skill_at(caster, grid_cone, HexCoord.new(4, 0)) != false:
		_fail("can_use_skill_at(GridCone, (4,0)) expected false (out of range)")
		passed = false

	# 4. 图外坐标(射程内但地图无此 tile) → 拒绝
	# 探针自寻找: 不对 ROW_COLUMN 的轴向映射做假设(3×6 地图 18 格 < 半径 3 圆盘 37 格, 必有缺口)
	var off_grid: HexCoord = null
	for probe_q in range(-3, 4):
		for probe_r in range(-3, 4):
			var cand := HexCoord.new(probe_q, probe_r)
			if caster.hex_position.distance_to(cand) > 3:
				continue
			if not battle.grid.has_tile(cand):
				off_grid = cand
				break
		if off_grid != null:
			break
	if off_grid == null:
		_fail("test setup: 半径 3 内找不到图外坐标")
		passed = false
	elif battle.can_use_skill_at(caster, grid_cone, off_grid) != false:
		_fail("can_use_skill_at(GridCone, (%d,%d)) expected false (off grid)" % [off_grid.q, off_grid.r])
		passed = false

	# 5. ACTOR 技能走 coord 入口 → 拒绝(wrong-mode)
	if battle.can_use_skill_at(caster, strike, enemy.hex_position) != false:
		_fail("can_use_skill_at(Strike, coord) expected false (ACTOR 走 on 入口)")
		passed = false

	# 6. ACTOR 路 sanity: strike 打相邻敌人照常放行
	if battle.can_use_skill_on(caster, strike, enemy) != true:
		_fail("can_use_skill_on(Strike, enemy) expected true")
		passed = false

	GameWorld.destroy()

	if passed:
		print("SMOKE_TEST_RESULT: PASS - targeting dual-entry protocol checks passed")
		get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - " + reason)
	get_tree().quit(1)
