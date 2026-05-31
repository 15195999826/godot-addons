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
## 死者特殊处理 — 详见 docs/reference/view-logic-reconciliation.md「死者」一节:
##   - 跳过 position (FrontendUnitView.play_death 修改 transform: scale 0.1 + position.y -0.5)
##   - hp / max_hp / is_alive 照查 (logic ability_set 不主动清, view BuffVisualizer 也不主动清,
##     双方对称)
##
## debug-only 协议: HexWorldGameplayInstance 仅在 OS.has_feature("debug") 下 emit
## final_state。release 包跑 smoke 接不到 signal, 调方传空 dict 即视为 SKIPPED 不 fail。
class_name HexBattleViewLogicReconciler


# ========== Schema 常量 ==========

## final_state 字典 key 与 _build_actor_snapshot / _build_final_state_snapshot 的拼写契约。
## producer 与 consumer 走同一份常量, 拼错编译时出错而非静默 default。
class Keys:
	const ACTORS := "actors"
	const IS_DEAD := "is_dead"
	const HEX_POSITION := "hex_position"
	const ATTRIBUTE := "attribute"
	const HP := "hp"
	const MAX_HP := "max_hp"


# ========== 嵌套数据类 ==========

class Mismatch extends RefCounted:
	enum Field { PRESENCE, IS_ALIVE, POSITION, HP, MAX_HP }

	var actor_id: String
	var field: Field
	var detail: String

	func _init(p_actor_id: String, p_field: Field, p_detail: String) -> void:
		actor_id = p_actor_id
		field = p_field
		detail = p_detail

	func to_human_string() -> String:
		return "[%s] %s: %s" % [actor_id, _field_name(field), detail]

	static func _field_name(f: Field) -> String:
		match f:
			Field.PRESENCE: return "presence"
			Field.IS_ALIVE: return "is_alive"
			Field.POSITION: return "position"
			Field.HP: return "hp"
			Field.MAX_HP: return "max_hp"
		return "unknown"


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
##   release build 下没人 emit, 调方传 {} 即可, 返回 SKIPPED report。
## animator: 取 view_state (FrontendActorRenderState) 用。
## world_view: 取 unit_view.global_position + hex_to_world 投影用。
## tree: 用于 await process_frame 跑 settle loop。
##
## 调方:
##   var report := await HexBattleViewLogicReconciler.reconcile(_final, _animator, _world_view, get_tree())
##   if not report.passed and not report.skipped:
##       _fail(report.to_human_string())
static func reconcile(
	final_state: Dictionary,
	animator: FrontendBattleAnimator,
	world_view: FrontendWorldView,
	tree: SceneTree,
	settle_timeout_sec: float = 1.0,
	position_epsilon: float = 0.01,
	hp_epsilon: float = 0.5,
) -> ReconcileReport:
	var report := ReconcileReport.new()

	if final_state.is_empty() or not final_state.has(Keys.ACTORS):
		report.skipped = true
		report.skip_reason = (
			"final_state empty — release build (no debug feature) " +
			"or HexWorldGameplayInstance not emitting battle_final_state_ready"
		)
		return report

	var logic_actors: Dictionary = final_state[Keys.ACTORS]
	report.actor_count = logic_actors.size()

	# 预计算 alive 投影坐标, 避免 settle loop 每帧 + diff 时重复 HexCoord.from_dict 分配。
	var expected_alive_pos := _precompute_alive_positions(logic_actors, world_view)

	var settle_result := await _settle_view_positions(
		expected_alive_pos, world_view, tree, settle_timeout_sec, position_epsilon
	)
	report.settle_time_ms = settle_result["time_ms"]
	report.settle_max_drift = settle_result["max_drift"]

	# 字段对账 (不 short-circuit, 收齐所有 mismatch)
	var view_states: Dictionary = animator.get_actors_snapshot()
	for actor_id: String in logic_actors:
		_diff_actor(
			actor_id, logic_actors[actor_id], view_states, world_view,
			expected_alive_pos, report, position_epsilon, hp_epsilon
		)

	report.passed = report.mismatches.is_empty()
	return report


## 跑 reconcile + 给一致的 print/warning/status 反馈。多调用方共享 (smoke / demo / skill-preview)。
##
## status_setter: Callable(text: String); 不需要时传 Callable() 跳过 UI 提示。
## fail_handler: Callable(report_text: String); 不需要时传 Callable(), mismatch 走 push_warning。
static func reconcile_and_report(
	final_state: Dictionary,
	animator: FrontendBattleAnimator,
	world_view: FrontendWorldView,
	tree: SceneTree,
	log_prefix: String,
	status_setter: Callable = Callable(),
	fail_handler: Callable = Callable(),
) -> ReconcileReport:
	var report := await reconcile(final_state, animator, world_view, tree)
	if report.skipped or report.passed:
		print("[%s] %s" % [log_prefix, report.to_human_string()])
		return report
	if fail_handler.is_valid():
		fail_handler.call(report.to_human_string())
	else:
		push_warning("[%s] %s" % [log_prefix, report.to_human_string()])
	if status_setter.is_valid():
		status_setter.call("⚠ View/Logic mismatch: %d field(s) — see console" % report.mismatches.size())
	return report


# ========== 内部 ==========

static func _precompute_alive_positions(
	logic_actors: Dictionary,
	world_view: FrontendWorldView,
) -> Dictionary:
	var result := {}
	for actor_id: String in logic_actors:
		var logic_actor: Dictionary = logic_actors[actor_id]
		if logic_actor.get(Keys.IS_DEAD, false) as bool:
			continue
		var pos_dict: Dictionary = logic_actor.get(Keys.HEX_POSITION, {})
		if pos_dict.is_empty():
			continue
		result[actor_id] = world_view.hex_to_world(HexCoord.from_dict(pos_dict))
	return result


## 等 unit_view 位置收敛 (FrontendUnitView._process 用 delta*15 lerp 到 _target_position)。
## animator playback_ended 不代表 view 已 snap — director ended 只意味着 scheduler 空。
##
## 退出条件 (任一即可):
##   1. max alive drift < epsilon → 收敛, 立即返回
##   2. 累计 wait time >= timeout_sec → 超时返回 (后续字段 diff 报 position fail)
static func _settle_view_positions(
	expected_alive_pos: Dictionary,
	world_view: FrontendWorldView,
	tree: SceneTree,
	timeout_sec: float,
	epsilon: float,
) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var deadline_ms := t0 + int(timeout_sec * 1000.0)
	var max_drift := 0.0
	while true:
		max_drift = _max_alive_drift(expected_alive_pos, world_view)
		if max_drift < epsilon:
			break
		if Time.get_ticks_msec() >= deadline_ms:
			break
		await tree.process_frame
	return {
		"time_ms": Time.get_ticks_msec() - t0,
		"max_drift": max_drift,
	}


static func _max_alive_drift(
	expected_alive_pos: Dictionary,
	world_view: FrontendWorldView,
) -> float:
	var max_drift := 0.0
	for actor_id: String in expected_alive_pos:
		var unit_view := world_view.get_unit_view(actor_id)
		if unit_view == null:
			continue
		var drift: float = (unit_view.global_position - expected_alive_pos[actor_id]).length()
		if drift > max_drift:
			max_drift = drift
	return max_drift


static func _diff_actor(
	actor_id: String,
	logic_actor: Dictionary,
	view_states: Dictionary,
	world_view: FrontendWorldView,
	expected_alive_pos: Dictionary,
	report: ReconcileReport,
	position_epsilon: float,
	hp_epsilon: float,
) -> void:
	var view_state: FrontendActorRenderState = view_states.get(actor_id, null)
	if view_state == null:
		report.mismatches.append(Mismatch.new(
			actor_id, Mismatch.Field.PRESENCE,
			"logic actor present but view has no RenderState entry"
		))
		return

	var logic_dead: bool = logic_actor.get(Keys.IS_DEAD, false) as bool
	var logic_alive: bool = not logic_dead
	if view_state.is_alive != logic_alive:
		report.mismatches.append(Mismatch.new(
			actor_id, Mismatch.Field.IS_ALIVE,
			"logic=%s view=%s" % [logic_alive, view_state.is_alive]
		))

	# position: 死者跳过 (play_death tween 改 transform); alive 才比
	if logic_alive:
		_diff_position(actor_id, world_view, expected_alive_pos, report, position_epsilon)

	_diff_hp(actor_id, logic_actor, view_state, report, hp_epsilon)


static func _diff_position(
	actor_id: String,
	world_view: FrontendWorldView,
	expected_alive_pos: Dictionary,
	report: ReconcileReport,
	epsilon: float,
) -> void:
	if not expected_alive_pos.has(actor_id):
		return  # 未放置, 不参与 position 对账

	var unit_view := world_view.get_unit_view(actor_id)
	if unit_view == null:
		report.mismatches.append(Mismatch.new(
			actor_id, Mismatch.Field.POSITION,
			"logic has hex_position but world_view has no unit_view"
		))
		return

	var expected: Vector3 = expected_alive_pos[actor_id]
	var actual := unit_view.global_position
	var drift := (actual - expected).length()
	if drift >= epsilon:
		report.mismatches.append(Mismatch.new(
			actor_id, Mismatch.Field.POSITION,
			"drift=%.4f (>= eps %.4f)  expected=%v actual=%v" % [drift, epsilon, expected, actual]
		))


static func _diff_hp(
	actor_id: String,
	logic_actor: Dictionary,
	view_state: FrontendActorRenderState,
	report: ReconcileReport,
	epsilon: float,
) -> void:
	var attr: Dictionary = logic_actor.get(Keys.ATTRIBUTE, {})
	if attr.is_empty():
		return

	var logic_hp: float = attr.get(Keys.HP, 0.0) as float
	var logic_max_hp: float = attr.get(Keys.MAX_HP, 0.0) as float

	if absf(view_state.visual_hp - logic_hp) >= epsilon:
		report.mismatches.append(Mismatch.new(
			actor_id, Mismatch.Field.HP,
			"logic=%.2f view=%.2f (eps %.2f)" % [logic_hp, view_state.visual_hp, epsilon]
		))
	if absf(view_state.max_hp - logic_max_hp) >= epsilon:
		report.mismatches.append(Mismatch.new(
			actor_id, Mismatch.Field.MAX_HP,
			"logic=%.2f view=%.2f (eps %.2f)" % [logic_max_hp, view_state.max_hp, epsilon]
		))
