## dota2_lane_battle - M1 可视场景（F6 直接看 ARAM 对线 + 富 debug 面板）
##
## logic-view-contract.md / tick-model.md：场景**自持**私有 logic clock block（accumulator
## + 有限 catch-up，**不**建独立 Dota2SimulationDriver 类）。view 只消费 Dota2LogicFrame
## 快照 + events，**不**mutate 战斗状态。catch-up / debt-drop 帧 Log.warning（含
## real_delta_ms / accumulator_before / steps / dropped_debt_ms / tick_index）。
##
## ownership：场景拥有实时累积；procedure 拥有固定步进顺序；view 只渲染快照/事件。
extends Node2D


const LOGIC_DT_MS := 1000.0 / 30.0
const MAX_LOGIC_STEPS_PER_RENDER_FRAME := 2
const MAX_ACCUMULATOR_MS := LOGIC_DT_MS * MAX_LOGIC_STEPS_PER_RENDER_FRAME

const RECENT_EVENTS_MAX := 14
const TEAM_LEFT_COLOR := Color(0.35, 0.6, 1.0)
const TEAM_RIGHT_COLOR := Color(1.0, 0.45, 0.4)


var _world: Dota2WorldGameplayInstance = null
var _procedure: Dota2AutoBattleProcedure = null

# ── 私有 logic clock block 状态（场景独占）─────────────────────────────────
var _accumulator_ms := 0.0
var _paused := false
var _catchup_frames := 0
var _debt_drop_frames := 0
var _finished_once := false

# ── view 只读消费的最新/上一帧 + 最近事件环形缓冲 ──────────────────────────
var _latest_frame: Dota2LogicFrame = null
var _recent_events: Array[String] = []

@onready var _debug_label: Label = $HUD/Debug


func _ready() -> void:
	_create_world_and_procedure()
	_setup_camera()


## GameWorld + world + procedure 装配 + 首帧（_ready 与 _restart 共用，避免 copy-paste）。
func _create_world_and_procedure() -> void:
	GameWorld.init()
	_world = GameWorld.create_instance(func() -> GameplayInstance:
		var w := Dota2WorldGameplayInstance.new()
		w.start()
		return w
	) as Dota2WorldGameplayInstance
	_procedure = _world.start_dota2_battle({ "tick_interval_ms": LOGIC_DT_MS })
	# 立即出一帧让首屏非空（tick 0 快照）。
	_latest_frame = _procedure.advance_tick(LOGIC_DT_MS)
	_ingest_frame_events(_latest_frame)


func _setup_camera() -> void:
	var cam: Camera2D = $Cam
	cam.position = Dota2LaneConfig.MAP_SIZE * 0.5
	var vp := get_viewport_rect().size
	if vp.x > 1.0 and vp.y > 1.0:
		# 让整条中路 + 边距进画面（取较小缩放保证不裁切）。
		var zx := vp.x / (Dota2LaneConfig.MAP_SIZE.x + 80.0)
		var zy := vp.y / (Dota2LaneConfig.MAP_SIZE.y + 80.0)
		var z := minf(zx, zy)
		cam.zoom = Vector2(z, z)
	cam.make_current()


# ========== 实时驱动：私有 logic clock block ==========

func _process(delta: float) -> void:
	if not _paused:
		_advance_logic_clock(delta * 1000.0)
	queue_redraw()
	_refresh_debug_panel()


## tick-model.md 规定形态：accumulator + 有限 catch-up + 超额 debt 丢弃 + 警告遥测。
func _advance_logic_clock(real_delta_ms: float) -> void:
	if _procedure == null:
		return
	if _procedure.should_end():
		if not _finished_once:
			_procedure.finish()
			_finished_once = true
		return

	var accumulator_before := _accumulator_ms
	_accumulator_ms += real_delta_ms

	var dropped_debt_ms := 0.0
	if _accumulator_ms > MAX_ACCUMULATOR_MS:
		dropped_debt_ms = _accumulator_ms - MAX_ACCUMULATOR_MS
		_accumulator_ms = MAX_ACCUMULATOR_MS

	var steps := 0
	while _accumulator_ms >= LOGIC_DT_MS and steps < MAX_LOGIC_STEPS_PER_RENDER_FRAME:
		var frame := _procedure.advance_tick(LOGIC_DT_MS)
		_latest_frame = frame
		_ingest_frame_events(frame)
		_accumulator_ms -= LOGIC_DT_MS
		steps += 1
		if _procedure.should_end():
			break

	if steps > 1 or dropped_debt_ms > 0.0:
		if steps > 1:
			_catchup_frames += 1
		if dropped_debt_ms > 0.0:
			_debt_drop_frames += 1
		# Log.warning(module, message)：把遥测拼进 message（含 tick-model.md 要求的全部字段）。
		Log.warning("Dota2AutoBattle", (
			"catch-up frame real_delta_ms=%.2f accumulator_ms_before=%.2f"
			+ " logic_steps_executed=%d dropped_debt_ms=%.2f logic_tick_index=%d"
		) % [real_delta_ms, accumulator_before, steps, dropped_debt_ms, _procedure.get_tick_index()])


func _ingest_frame_events(frame: Dota2LogicFrame) -> void:
	if frame == null:
		return
	for evt in frame.events:
		var kind := str(evt.get("kind", ""))
		if kind.begins_with("dota2_pre_") or kind.begins_with("dota2_post_"):
			continue
		_recent_events.append("[t%d] %s" % [frame.tick_index, _format_event(evt)])
	while _recent_events.size() > RECENT_EVENTS_MAX:
		_recent_events.pop_front()


func _format_event(evt: Dictionary) -> String:
	var kind := str(evt.get("kind", ""))
	match kind:
		Dota2BattleEvents.DAMAGE_APPLIED:
			return "damage %s->%s %.0f (hp %.0f)" % [
				evt.get("source_actor_id", ""), evt.get("target_actor_id", ""),
				evt.get("damage", 0.0), evt.get("target_hp_after", 0.0)]
		Dota2BattleEvents.UNIT_DIED:
			return "DIED %s (by %s)" % [evt.get("actor_id", ""), evt.get("killer_id", "")]
		Dota2BattleEvents.TARGET_ACQUIRED:
			return "aggro %s->%s" % [evt.get("actor_id", ""), evt.get("target_id", "")]
		_:
			return kind


# ========== 输入：显式 scene 级 debug 入口（非 mutate 战斗内部）==========

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_paused = not _paused
		elif event.keycode == KEY_R:
			_restart()


func _restart() -> void:
	if _procedure != null and not _procedure.should_end():
		_procedure.finish()
	if _world != null:
		_world.end()
	GameWorld.destroy()
	_accumulator_ms = 0.0
	_catchup_frames = 0
	_debt_drop_frames = 0
	_finished_once = false
	_recent_events.clear()
	_latest_frame = null
	_create_world_and_procedure()


# ========== view：只读渲染最新快照 ==========

func _draw() -> void:
	# 中路参考线。
	draw_line(
		Vector2(0.0, Dota2LaneConfig.LANE_Y),
		Vector2(Dota2LaneConfig.MAP_SIZE.x, Dota2LaneConfig.LANE_Y),
		Color(1, 1, 1, 0.12), 2.0)
	if _latest_frame == null:
		return
	for actor_id in _latest_frame.actor_snapshots:
		var s: Dictionary = _latest_frame.actor_snapshots[actor_id]
		_draw_unit(s)


func _draw_unit(s: Dictionary) -> void:
	var pos := Vector2(s.get("x", 0.0), s.get("y", 0.0))
	var alive: bool = s.get("alive", true)
	var team: int = s.get("team_id", -1)
	var base_col := TEAM_LEFT_COLOR if team == Dota2LaneConfig.TEAM_LEFT else TEAM_RIGHT_COLOR
	var col := base_col if alive else Color(0.4, 0.4, 0.4, 0.5)
	var radius := 12.0 if str(s.get("unit_type_id", "")) == "lane_melee" else 9.0

	# 攻击中：外圈闪一下（attack_executing）。
	if alive and bool(s.get("attack_executing", false)):
		draw_arc(pos, radius + 5.0, 0.0, TAU, 24, Color(1, 1, 0.3, 0.9), 2.0)
	draw_circle(pos, radius, col)

	# HP 条。
	var hp: float = s.get("hp", 0.0)
	var max_hp: float = maxf(1.0, s.get("max_hp", 1.0))
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var bar_w := 26.0
	var bar_top := pos + Vector2(-bar_w * 0.5, -radius - 9.0)
	draw_rect(Rect2(bar_top, Vector2(bar_w, 4.0)), Color(0, 0, 0, 0.6))
	if alive:
		draw_rect(Rect2(bar_top, Vector2(bar_w * frac, 4.0)),
			Color(0.3, 0.9, 0.3) if frac > 0.35 else Color(0.95, 0.5, 0.2))

	# 攻击目标连线（debug 可视）。
	var tgt_id := str(s.get("attack_target_id", ""))
	if alive and tgt_id != "" and _latest_frame.actor_snapshots.has(tgt_id):
		var ts: Dictionary = _latest_frame.actor_snapshots[tgt_id]
		draw_line(pos, Vector2(ts.get("x", 0.0), ts.get("y", 0.0)), Color(1, 1, 1, 0.10), 1.0)


# ========== 富 debug 面板 ==========

func _refresh_debug_panel() -> void:
	if _debug_label == null:
		return
	var lines: Array[String] = []
	var tick := _procedure.get_tick_index() if _procedure != null else 0
	var ended := _procedure != null and _procedure.should_end()
	var alive_n := 0
	if _latest_frame != null:
		for aid in _latest_frame.actor_snapshots:
			if bool((_latest_frame.actor_snapshots[aid] as Dictionary).get("alive", false)):
				alive_n += 1
	lines.append("DOTA2 Auto Battle — M1  [%s]" % ("PAUSED" if _paused else ("ENDED:" + _procedure.get_result() if ended else "RUNNING")))
	lines.append("tick=%d  logic_t=%.0fms  alive=%d  result=%s" % [
		tick, _latest_frame.logic_time_ms if _latest_frame != null else 0.0,
		alive_n, _procedure.get_result() if _procedure != null else ""])
	lines.append("catch-up frames=%d  debt-drop frames=%d  (Space=pause  R=restart)" % [
		_catchup_frames, _debt_drop_frames])
	lines.append("── actors ───────────────────────────────")
	if _latest_frame != null:
		var ids := _latest_frame.actor_snapshots.keys()
		ids.sort()
		for aid in ids:
			var s: Dictionary = _latest_frame.actor_snapshots[aid]
			lines.append("%s T%d %s hp=%.0f/%.0f %s/%s tgt=%s mv=%s%s%s" % [
				_short_id(str(aid)), s.get("team_id", -1), s.get("unit_type_id", ""),
				s.get("hp", 0.0), s.get("max_hp", 0.0),
				s.get("intent_kind", ""), s.get("intent_status", ""),
				_short_id(str(s.get("attack_target_id", ""))),
				s.get("movement_state", ""),
				"" if str(s.get("movement_block_reason", "")) == "" else " blk=" + str(s.get("movement_block_reason")),
				" CD" if bool(s.get("attack_on_cooldown", false)) else ("" if not bool(s.get("attack_executing", false)) else " ATK"),
			])
	lines.append("── recent events ────────────────────────")
	for i in range(_recent_events.size() - 1, -1, -1):
		lines.append(_recent_events[i])
	_debug_label.text = "\n".join(lines)


func _short_id(full: String) -> String:
	var idx := full.rfind(":")
	return full.substr(idx + 1) if idx >= 0 else full
