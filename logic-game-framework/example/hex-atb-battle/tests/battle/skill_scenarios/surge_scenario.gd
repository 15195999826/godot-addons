## Surge 自施场景:验证 BattleRecorder 把 AbilityGranted(pending)排在 collector
## 主动事件之前(修复点见 stdlib/replay/battle_recorder.gd::record_frame)。
##
## Surge 用 GRANTED_SELF + on_timeline_start,grant 同步链里立即 fire 首 tick:
##   1. ApplyBuffAction → grant_ability:
##      a. _notify_granted → recording_utils push AbilityGranted 进 pending_events
##      b. receive_event(AbilityGranted) → fire_sync_actions(on_timeline_start)
##         → SurgeTickAction → push StacksChanged 进 EventCollector
##
## 修复前:record_frame 用 [events..., pending...] 顺序,replay frame 实际是
##   [StacksChanged, AbilityGranted] —— frontend BuffVisualizer 看到 stacks 时
##   buff 还没 ADD,UPDATE 静默失败 → ADD primary=3 → 显示 U3 → 下帧 U1 → 消失。
## 修复后:[pending..., events...],replay 顺序 [AbilityGranted, StacksChanged] →
##   ADD primary=3 → UPDATE primary=2(同帧合并)→ 显示 U2 → U1 → 消失。
class_name SurgeScenario
extends SkillScenario


func get_name() -> String:
	return "Surge grant + on_timeline_start ordering"


func get_scene_config() -> Dictionary:
	return {
		"map": {"rows": 3, "cols": 3},
		"caster":  {"class": "WARRIOR", "pos": [0, 0]},
		"enemies": [{"class": "WARRIOR", "pos": [2, 0], "hp": 100}],
		"target":  {"mode": "auto"},
	}


func get_active_skill() -> AbilityConfig:
	return HexBattleSurge.ABILITY


## cast(500ms) + 3 次 tick(2s interval) + 尾巴 = 7s 多 → 80 ticks 够
func get_max_ticks() -> int:
	return 100


func assert_replay(ctx: ScenarioAssertContext) -> void:
	# 1. 期望 3 次 stacks_changed:3→2 / 2→1 / 1→0
	var stacks_events := ctx.events_of_kind(GameEvent.ABILITY_STACKS_CHANGED_EVENT)
	var surge_stacks_events: Array[Dictionary] = []
	for e in stacks_events:
		if e.get("abilityConfigId") == HexBattleSurgeBuff.CONFIG_ID:
			surge_stacks_events.append(e)
	ctx.assert_eq(surge_stacks_events.size(), 3, "3 SurgeStacksChanged events")
	if surge_stacks_events.size() == 3:
		ctx.assert_eq(surge_stacks_events[0].get("oldStacks"), 3, "tick 1 oldStacks")
		ctx.assert_eq(surge_stacks_events[0].get("newStacks"), 2, "tick 1 newStacks")
		ctx.assert_eq(surge_stacks_events[2].get("newStacks"), 0, "tick 3 newStacks reaches 0")

	# 2. 验证 BattleRecorder 顺序契约:首 stacks_changed 必须晚于 SurgeBuff grant
	#    (这是 record_frame 把 pending 放前的关键回归保护)。
	var grant_index := -1
	var first_stacks_index := -1
	for i in range(ctx.events.size()):
		var event := ctx.events[i]
		var kind := event.get("kind", "") as String
		if first_stacks_index < 0 and kind == GameEvent.ABILITY_STACKS_CHANGED_EVENT \
			and event.get("abilityConfigId") == HexBattleSurgeBuff.CONFIG_ID:
			first_stacks_index = i
		if grant_index < 0 and kind == GameEvent.ABILITY_GRANTED_EVENT:
			var ability: Dictionary = event.get("ability", {})
			if ability.get("configId") == HexBattleSurgeBuff.CONFIG_ID:
				grant_index = i
	ctx.assert_true(grant_index >= 0, "SurgeBuff AbilityGranted recorded")
	ctx.assert_true(first_stacks_index > grant_index,
		"SurgeBuff grant must appear before first StacksChanged in replay (record_frame ordering contract)")

	# 3. buff 耗尽后应被 revoke
	ctx.assert_actor_ability_absent(ctx.caster_id, HexBattleSurgeBuff.CONFIG_ID,
		"SurgeBuff revoked after stacks exhausted")
