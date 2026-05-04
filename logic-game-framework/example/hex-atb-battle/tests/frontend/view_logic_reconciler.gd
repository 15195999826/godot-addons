## ViewLogicReconciler - 战斗结束后 logic ↔ view 终态一致性 oracle
##
## 在 playback 结束后跑一次, 比对两端是否一致:
##   logic 终态 = HexWorldGameplayInstance.battle_final_state_ready 给的 final_state
##   view 终态  = FrontendBattleAnimator.get_actors_snapshot 给的 RenderState 集合 +
##                FrontendWorldView 上各 unit_view 的 global_position (经 settle loop 收敛)
##
## 任一字段漂 → 收集进 mismatches (不 short-circuit) → 返回 ReconcileReport。
## 调方决定是否硬 fail (smoke) / push_warning (skill-preview 交互场景)。
##
## 死者特殊处理 — 详见 docs/view-logic-reconciliation.md「死者」一节:
##   - 跳过 position (FrontendUnitView.play_death 修改 transform: scale 0.1 + position.y -0.5)
##   - hp / max_hp / is_alive 照查 (logic ability_set 不主动清, view BuffVisualizer 也不主动清,
##     双方对称)
##
## debug-only 协议: HexWorldGameplayInstance 仅在 OS.has_feature("debug") 下 emit
## final_state。release 包跑 smoke 接不到 signal, 调方传空 dict 即视为 SKIPPED 不 fail。
##
## 本轮覆盖字段: position / is_alive / hp / max_hp。 buffs / shields 字段集留作 follow-up
## (见文档 #扩展点)。
class_name HexBattleViewLogicReconciler
extends RefCounted


# ========== 嵌套数据类 ==========

class Mismatch extends RefCounted:
	var actor_id: String
	var field: String
	var detail: String

	func _init(p_actor_id: String, p_field: String, p_detail: String) -> void:
		actor_id = p_actor_id
		field = p_field
		detail = p_detail

	func to_human_string() -> String:
		return "[%s] %s: %s" % [actor_id, field, detail]


class ReconcileReport extends RefCounted:
	var passed: bool = false
	var skipped: bool = false
	var skip_reason: String = ""
	var mismatches: Array[Mismatch] = []
	var settle_time_ms: int = 0
	var settle_max_drift: float = 0.0
	var actor_count: int = 0

	func to_human_string() -> String:
		if skipped:
			return "Reconcile SKIPPED: %s" % skip_reason
		if passed:
			return "Reconcile PASS (%d actors, settled in %d ms, max drift %.4f)" % [
				actor_count, settle_time_ms, settle_max_drift,
			]
		var lines := PackedStringArray()
		lines.append("Reconcile FAIL with %d mismatches (settled in %d ms):" % [
			mismatches.size(), settle_time_ms,
		])
		for m: Mismatch in mismatches:
			lines.append("  " + m.to_human_string())
		return "\n".join(lines)


# ========== 公共入口 ==========

## 比对 final_state 与当前 view 状态。
##
## final_state: HexWorldGameplayInstance.battle_final_state_ready 给的 dict;
##   release build 下没人 emit, 调方传 {} 即可, reconciler 返回 SKIPPED。
## animator: 取 view_state (FrontendActorRenderState) 用。
## world_view: 取 unit_view.global_position + hex_to_world 投影用。
## tree: 用于 await process_frame 跑 settle loop。
##
## 调方:
##   var rec := HexBattleViewLogicReconciler.new()
##   var report: ReconcileReport = await rec.reconcile(_final, _animator, _world_view, get_tree())
##   if not report.passed and not report.skipped:
##       _fail(report.to_human_string())
func reconcile(
	final_state: Dictionary,
	animator: FrontendBattleAnimator,
	world_view: FrontendWorldView,
	tree: SceneTree,
	settle_timeout_sec: float = 1.0,
	position_epsilon: float = 0.01,
	hp_epsilon: float = 0.5,
) -> ReconcileReport:
	var report := ReconcileReport.new()

	if final_state.is_empty() or not final_state.has("actors"):
		report.skipped = true
		report.skip_reason = (
			"final_state empty — release build (no debug feature) " +
			"or HexWorldGameplayInstance not emitting battle_final_state_ready"
		)
		return report

	var logic_actors: Dictionary = final_state["actors"]
	report.actor_count = logic_actors.size()

	# Step 1: settle view positions (alive unit_view lerp 收敛)
	var settle_result := await _settle_view_positions(
		logic_actors, animator, world_view, tree, settle_timeout_sec, position_epsilon
	)
	report.settle_time_ms = settle_result["time_ms"]
	report.settle_max_drift = settle_result["max_drift"]

	# Step 2: 字段对账 (不 short-circuit, 收齐所有 mismatch)
	var view_states: Dictionary = animator.get_actors_snapshot()
	for actor_id: String in logic_actors.keys():
		var logic_actor: Dictionary = logic_actors[actor_id]
		_diff_actor(
			actor_id, logic_actor, view_states, world_view,
			report, position_epsilon, hp_epsilon
		)

	report.passed = report.mismatches.is_empty()
	return report


# ========== Settle loop ==========

## 等 unit_view 位置收敛 (FrontendUnitView._process 用 delta*15 lerp 到 _target_position)。
## animator playback_ended 不代表 view 已 snap — director ended 只意味着 scheduler 空。
##
## 退出条件 (任一即可):
##   1. max alive drift < position_epsilon → 收敛, 立即返回
##   2. 累计 wait time >= settle_timeout_sec → 超时返回 (此时由后续字段 diff 报 position fail)
##
## 死者跳过, 因为 play_death tween 永远不会"收敛"到逻辑投影位置, 等也是浪费。
func _settle_view_positions(
	logic_actors: Dictionary,
	_animator: FrontendBattleAnimator,
	world_view: FrontendWorldView,
	tree: SceneTree,
	timeout_sec: float,
	epsilon: float,
) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var deadline_ms := t0 + int(timeout_sec * 1000.0)
	var max_drift := 0.0
	while true:
		max_drift = _max_alive_drift(logic_actors, world_view)
		if max_drift < epsilon:
			break
		if Time.get_ticks_msec() >= deadline_ms:
			break
		await tree.process_frame
	return {
		"time_ms": Time.get_ticks_msec() - t0,
		"max_drift": max_drift,
	}


func _max_alive_drift(logic_actors: Dictionary, world_view: FrontendWorldView) -> float:
	var max_drift := 0.0
	for actor_id: String in logic_actors.keys():
		var logic_actor: Dictionary = logic_actors[actor_id]
		if logic_actor.get("is_dead", false) as bool:
			continue
		var pos_dict: Dictionary = logic_actor.get("hex_position", {})
		if pos_dict.is_empty():
			continue
		var unit_view := world_view.get_unit_view(actor_id)
		if unit_view == null:
			continue
		var expected := world_view.hex_to_world(HexCoord.from_dict(pos_dict))
		var drift := (unit_view.global_position - expected).length()
		if drift > max_drift:
			max_drift = drift
	return max_drift


# ========== 字段 diff ==========

func _diff_actor(
	actor_id: String,
	logic_actor: Dictionary,
	view_states: Dictionary,
	world_view: FrontendWorldView,
	report: ReconcileReport,
	position_epsilon: float,
	hp_epsilon: float,
) -> void:
	var view_state: FrontendActorRenderState = view_states.get(actor_id, null)
	if view_state == null:
		report.mismatches.append(Mismatch.new(
			actor_id, "presence",
			"logic actor present but view has no RenderState entry"
		))
		return

	var logic_dead: bool = logic_actor.get("is_dead", false) as bool

	# is_alive: 严格对齐 (双方都不应漂)
	var view_alive: bool = view_state.is_alive
	var logic_alive: bool = not logic_dead
	if view_alive != logic_alive:
		report.mismatches.append(Mismatch.new(
			actor_id, "is_alive",
			"logic=%s view=%s" % [logic_alive, view_alive]
		))

	# position: 死者跳过 (play_death tween 改 transform); alive 才比
	if not logic_dead:
		_diff_position(actor_id, logic_actor, world_view, report, position_epsilon)

	# hp / max_hp: 全查 (死者也比 — 死者 hp 应该 ≤ 0 双方都对得上)
	_diff_hp(actor_id, logic_actor, view_state, report, hp_epsilon)


func _diff_position(
	actor_id: String,
	logic_actor: Dictionary,
	world_view: FrontendWorldView,
	report: ReconcileReport,
	epsilon: float,
) -> void:
	var pos_dict: Dictionary = logic_actor.get("hex_position", {})
	if pos_dict.is_empty():
		return  # 未放置 actor, 不参与 position 对账

	var unit_view := world_view.get_unit_view(actor_id)
	if unit_view == null:
		report.mismatches.append(Mismatch.new(
			actor_id, "position",
			"logic has hex_position but world_view has no unit_view"
		))
		return

	var expected := world_view.hex_to_world(HexCoord.from_dict(pos_dict))
	var actual := unit_view.global_position
	var drift := (actual - expected).length()
	if drift >= epsilon:
		report.mismatches.append(Mismatch.new(
			actor_id, "position",
			"drift=%.4f (>= eps %.4f)  expected=%v actual=%v hex=%s" % [
				drift, epsilon, expected, actual, str(pos_dict),
			]
		))


func _diff_hp(
	actor_id: String,
	logic_actor: Dictionary,
	view_state: FrontendActorRenderState,
	report: ReconcileReport,
	epsilon: float,
) -> void:
	var attr: Dictionary = logic_actor.get("attribute", {})
	if attr.is_empty():
		return  # actor 没 attribute snapshot (理论不会, env actor 也有), 跳

	var logic_hp: float = attr.get("hp", 0.0) as float
	var logic_max_hp: float = attr.get("max_hp", 0.0) as float

	# visual_hp 是 director 经 lerp 收敛到 target_hp 的值; settle loop 后应已收敛。
	var view_hp: float = view_state.visual_hp
	var view_max_hp: float = view_state.max_hp

	if absf(view_hp - logic_hp) >= epsilon:
		report.mismatches.append(Mismatch.new(
			actor_id, "hp",
			"logic=%.2f view=%.2f (eps %.2f)" % [logic_hp, view_hp, epsilon]
		))
	if absf(view_max_hp - logic_max_hp) >= epsilon:
		report.mismatches.append(Mismatch.new(
			actor_id, "max_hp",
			"logic=%.2f view=%.2f (eps %.2f)" % [logic_max_hp, view_max_hp, epsilon]
		))
