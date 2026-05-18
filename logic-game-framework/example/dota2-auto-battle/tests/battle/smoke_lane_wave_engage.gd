## smoke_lane_wave_engage - M1 端到端冒烟（headless）
##
## 验证垂直切片：两波 lane creep spawn → march（sim-nav 适配器路径）→ aggro-latch
## → chase → 基础攻击（Ability/Timeline/Action）→ damage → death → 战斗收束。
## 输出 SMOKE_TEST_RESULT: PASS|FAIL - <reason> + 退出码 0/1。
extends Node


const LOGIC_DT_MS := 1000.0 / 30.0
const MAX_ITERS := 2000


func _ready() -> void:
	GameWorld.init()
	var world := GameWorld.create_instance(func() -> GameplayInstance:
		var w := Dota2WorldGameplayInstance.new()
		w.start()
		return w
	) as Dota2WorldGameplayInstance

	var procedure := world.start_dota2_battle({ "tick_interval_ms": LOGIC_DT_MS })

	# 起手：两波（左右各一波）= 2 × WAVE_COMPOSITION。
	var expected := 2 * Dota2LaneConfig.get_wave_composition().size()
	var alive0 := world.get_alive_units().size()
	if alive0 != expected:
		_fail("spawn count wrong: expected %d, got %d" % [expected, alive0])
		return

	# 记录初始位置 + 兵种数值抽查（config→AttributeSet，max_hp 先于 hp）。
	var sample := world.get_alive_units()[0]
	if sample.attribute_set.hp <= 0.0 or sample.attribute_set.hp > sample.attribute_set.max_hp:
		_fail("attribute clamp broken: hp=%.1f max_hp=%.1f" % [
			sample.attribute_set.hp, sample.attribute_set.max_hp])
		return
	var left_start_x := _avg_team_x(world, Dota2LaneConfig.TEAM_LEFT)
	var right_start_x := _avg_team_x(world, Dota2LaneConfig.TEAM_RIGHT)

	# 事件词汇出现追踪（logic-view-contract canonical）。
	var seen := {}
	var iters := 0
	while iters < MAX_ITERS and not procedure.should_end():
		var frame: Dota2LogicFrame = procedure.advance_tick(LOGIC_DT_MS)
		for evt in frame.events:
			seen[str(evt.get("kind", ""))] = true
		iters += 1

	procedure.finish()

	# 1) march：双方应朝对方推进（左队均值 x 增大，右队减小）—— sim-nav 适配器在动。
	var left_end_x := _avg_team_x_all(procedure.left_team)
	var right_end_x := _avg_team_x_all(procedure.right_team)
	if left_end_x <= left_start_x + 5.0:
		_fail("left team did not march right: %.1f -> %.1f" % [left_start_x, left_end_x])
		return
	if right_end_x >= right_start_x - 5.0:
		_fail("right team did not march left: %.1f -> %.1f" % [right_start_x, right_end_x])
		return

	# 2) 关键事件链都出现过。
	for required in [
		Dota2BattleEvents.UNIT_SPAWNED,
		Dota2BattleEvents.INTENT_STARTED,
		Dota2BattleEvents.TARGET_ACQUIRED,
		Dota2BattleEvents.ATTACK_STARTED,
		Dota2BattleEvents.ATTACK_LANDED,
		Dota2BattleEvents.DAMAGE_APPLIED,
		Dota2BattleEvents.UNIT_DIED,
	]:
		if not seen.has(required):
			_fail("missing event in run: %s (seen=%s)" % [required, str(seen.keys())])
			return

	# 3) 至少一个单位死亡 + 战斗在 MAX_TICKS 内收束（非 timeout）。
	var total_dead := 0
	for a in procedure.left_team + procedure.right_team:
		if a.is_dead():
			total_dead += 1
	if total_dead == 0:
		_fail("no unit died after %d ticks" % iters)
		return
	if not procedure.should_end():
		_fail("battle did not end within %d iters" % MAX_ITERS)
		return
	if procedure.get_result() == "timeout":
		_fail("battle timed out (no decisive engage); dead=%d" % total_dead)
		return

	world.end()
	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - 2 waves spawn->march(sim-nav)->aggro->attack(Ability)->damage->death; result=%s ticks=%d dead=%d" % [
		procedure.get_result(), iters, total_dead])
	get_tree().quit(0)


func _avg_team_x(world: Dota2WorldGameplayInstance, team_id: int) -> float:
	var sum := 0.0
	var n := 0
	for u in world.get_alive_units():
		if u.get_team_id() == team_id:
			sum += u.position_2d.x
			n += 1
	return sum / float(n) if n > 0 else 0.0


func _avg_team_x_all(team: Array[Dota2BattleActor]) -> float:
	var sum := 0.0
	var n := 0
	for a in team:
		sum += a.position_2d.x
		n += 1
	return sum / float(n) if n > 0 else 0.0


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
