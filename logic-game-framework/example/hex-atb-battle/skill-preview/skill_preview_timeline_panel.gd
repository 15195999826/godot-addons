class_name SkillPreviewTimelinePanel
extends RefCounted

## SkillPreviewTimelinePanel - SkillPreview 的 Timeline (SPT) 工作区子控制器
##
## 职责: Workspace drawer 的 Timeline tab —— 多 actor 时间轴编辑器的构建、绘制、
## keyframe 拖拽/游标/警告交互, 以及 SkillPreviewTimeline (SPT) 视觉常量。从
## skill_preview.gd 纯平移拆出, 函数体逻辑逐行不变, 仅把对宿主状态/方法的引用改
## 为 `_host.` 前缀。
##
## 命名 SPT 前缀 = SkillPreviewTimeline, 与 LGF core TimelineRegistry / Ability
## timeline 概念严格区分: 这是技能预览 UI 的多 actor 时间轴, 不是 ability animation
## timeline。视图全部从 _host._actors[i] 派生, 不引入新数据 (除 _spt_max_override 一个 int)。
##
## host 契约:
## - 宿主 (skill_preview.gd, extends Node) 持有本 panel: `_host._timeline_panel`。
##   本 panel 反向持宿主引用 `_host` (RefCounted 持 Node 无 refcount 环)。
## - **共享 selection 留宿主**: `_selected_spt_actor_idx` / `_selected_spt_kf_idx` 是
##   timeline / character panel / details / inventory 多方共读写的头号共享 selection,
##   由宿主唯一持有; `_set_spt_selection` / `_remove_keyframe` 等直接读写
##   `_host._selected_spt_*`。若下沉到 panel 会产生多副本同步问题, 故不搬。
##   `_selected_kind` / `_selected_actor_idx` / `_selected_hex` 等其它 selection 态同理留宿主。
## - keyframe 数据 mutation 层 (`_add_keyframe_at` / `_on_keyframe_time_changed` /
##   `_remove_keyframe` ...) 与 `_set_status` / `_set_drawer_tab` /
##   `_apply_timeline_workspace_layout` / `_rebuild_actors_ui` / 选择函数族 /
##   `_get_skill_config` / `_role_id_for` / theme 助手 / CLAY_* 与 KF_*/TICK_* 常量
##   均属宿主, panel 经 `_host.` 调用。
## - 本 panel 是 RefCounted, 不在场景树: `get_viewport()` 等 Node API 走 `_host.`。
##   `_spt_*` UI 节点引用是 build 时创建并赋值 (原 @onready 初值总被 build 覆盖)。


# SkillPreviewTimeline (SPT) tab 视觉常量
const SPT_ACTOR_LABEL_W := 220
const SPT_ROW_H := 84
const SPT_RULER_H := 34
const SPT_RULER_LABEL_W := 58.0
const SPT_RULER_LABEL_H := 16.0
const SPT_KF_BTN_W := 92
const SPT_KF_BTN_H := 30
const SPT_RELEASE_SPAN_H := 14
const SPT_KF_LANE_CENTER_Y := 25.0
const SPT_RELEASE_LANE_Y := 45.0
const SPT_COOLDOWN_LANE_Y := 62.0
const SPT_RESULT_LANE_Y := 78.0
const SPT_MIN_AUTO_MS := 5000
const SPT_AUTO_BUFFER_MS := 1000
const SPT_MIN_TRACK_W := 1500.0
const SPT_MS_TO_PX := 0.32
const SPT_WARNING_COOLDOWN := Color("DC2626")
const SPT_WARNING_OVERLAP := Color("D97706")
const SPT_EDITOR_BG := Color("0B1117")
const SPT_EDITOR_PANEL := Color("141F2A")
const SPT_EDITOR_ROW := Color("101820")
const SPT_EDITOR_GRID := Color(0.68, 0.78, 0.84, 0.08)
const SPT_EDITOR_GRID_MAJOR := Color(0.78, 0.88, 0.92, 0.18)
const SPT_EDITOR_TEXT := Color("E5E7EB")
const SPT_EDITOR_TEXT_SOFT := Color("94A3B8")
const SPT_CURSOR_COLOR := Color("FACC15")


var _host: Node = null

var _spt_max_override: int = 0           # 0 = auto-fit; >0 = override
var _spt_dragging: bool = false
var _spt_drag_actor_idx: int = -1
var _spt_drag_kf_idx: int = -1
var _spt_drag_requested_ms: int = 0
var _spt_drag_track_area: Control = null
var _spt_drag_grab_offset_x: float = 0.0
var _spt_cursor_actor_idx: int = -1
var _spt_cursor_time_ms: int = 0

var _spt_max_override_input: SpinBox = null
var _spt_max_auto_label: Label = null
var _spt_ruler: Control = null
var _spt_tracks_container: VBoxContainer = null
var _timeline_tracks_container: VBoxContainer = null
var _timeline_warning_list: VBoxContainer = null
var _timeline_add_button: Button = null
var _timeline_delete_button: Button = null
var _timeline_warnings_button: Button = null
var _timeline_status_label: Label = null
var _drawer_timeline_tab: VBoxContainer = null


func _init(host: Node) -> void:
	_host = host


func _build_drawer_timeline_tab() -> void:
	_drawer_timeline_tab.add_theme_stylebox_override(
		"panel",
		_host._clay_sb(SPT_EDITOR_BG, 8, 8, 8, 0, 0)
	)
	var toolbar := HBoxContainer.new()
	toolbar.name = "TimelineToolbar"
	toolbar.add_theme_constant_override("separation", 8)
	toolbar.add_theme_stylebox_override("panel", _host._clay_sb(SPT_EDITOR_PANEL, 6, 9, 7, 0, 0))
	_drawer_timeline_tab.add_child(toolbar)

	var title := Label.new()
	title.text = "Timeline"
	title.add_theme_font_override("font", _host._clay_font_bold())
	title.add_theme_color_override("font_color", SPT_EDITOR_TEXT)
	toolbar.add_child(title)

	toolbar.add_child(_make_timeline_legend_chip(
		"Release",
		Color("14532D"),
		Color("22C55E"),
		"Skill execution window"
	))
	toolbar.add_child(_make_timeline_legend_chip(
		"Cooldown",
		Color("334155"),
		Color("94A3B8"),
		"Same skill cannot be reused before this ends"
	))

	var add_btn := _make_timeline_tool_button("Add", "Create a keyframe at the current timeline cursor")
	add_btn.pressed.connect(_on_timeline_add_keyframe_pressed)
	toolbar.add_child(add_btn)
	_timeline_add_button = add_btn

	var delete_btn := _make_timeline_tool_button("Del", "Delete selected keyframe")
	delete_btn.pressed.connect(func() -> void:
		if _host._selected_spt_actor_idx >= 0 and _host._selected_spt_kf_idx >= 0:
			_host._remove_keyframe(_host._selected_spt_actor_idx, _host._selected_spt_kf_idx)
	)
	toolbar.add_child(delete_btn)
	_timeline_delete_button = delete_btn

	var warnings_btn := _make_timeline_tool_button("Warnings 0", "Open timeline warnings")
	warnings_btn.pressed.connect(func() -> void:
		_host._set_drawer_tab("Warnings")
	)
	toolbar.add_child(warnings_btn)
	_timeline_warnings_button = warnings_btn

	var divider := VSeparator.new()
	toolbar.add_child(divider)

	var step_label := Label.new()
	step_label.text = "Step %dms" % _host.KF_TIME_STEP_MS
	step_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
	toolbar.add_child(step_label)

	var span_label := Label.new()
	span_label.text = "Span"
	span_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
	toolbar.add_child(span_label)

	var span_input := SpinBox.new()
	span_input.name = "TimelineSpanOverride"
	span_input.min_value = 0.0
	span_input.max_value = 60000.0
	span_input.step = 100.0
	span_input.suffix = "ms"
	span_input.custom_minimum_size = Vector2(120, 0)
	toolbar.add_child(span_input)
	_spt_max_override_input = span_input
	# SkillPreviewTimeline span override 自绘。Override 警告在 mutation 点 emit,
	# 不放 _spt_max_ms() getter — 否则每次 redraw 都会盖掉用户正在看的 status。
	_spt_max_override_input.value_changed.connect(func(v: float) -> void:
		_spt_max_override = int(v)
		_warn_if_override_below_keyframes()
		_rebuild_spt_ui()
	)

	var auto_label := Label.new()
	auto_label.name = "TimelineAutoSpan"
	auto_label.text = "auto = 1000 ms"
	auto_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
	toolbar.add_child(auto_label)
	_spt_max_auto_label = auto_label

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var status_label := Label.new()
	status_label.text = "Status: Editing"
	status_label.add_theme_color_override("font_color", Color("60A5FA"))
	status_label.add_theme_font_override("font", _host._clay_font_bold())
	toolbar.add_child(status_label)
	_timeline_status_label = status_label

	var timeline_scroll := ScrollContainer.new()
	timeline_scroll.name = "TimelineScroll"
	timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline_scroll.add_theme_stylebox_override("panel", _host._clay_sb(SPT_EDITOR_BG, 6, 0, 0, 0, 0))
	_drawer_timeline_tab.add_child(timeline_scroll)

	var timeline_content := VBoxContainer.new()
	timeline_content.name = "TimelineContent"
	timeline_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_content.add_theme_constant_override("separation", 4)
	timeline_scroll.add_child(timeline_content)

	var ruler_row := HBoxContainer.new()
	ruler_row.name = "TimelineRulerRow"
	ruler_row.add_theme_constant_override("separation", 0)
	timeline_content.add_child(ruler_row)

	var ruler_spacer := Control.new()
	ruler_spacer.custom_minimum_size = Vector2(SPT_ACTOR_LABEL_W, SPT_RULER_H)
	ruler_row.add_child(ruler_spacer)

	var ruler := Control.new()
	ruler.name = "TimelineRuler"
	ruler.custom_minimum_size = Vector2(_spt_track_width(), SPT_RULER_H)
	ruler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ruler.draw.connect(func() -> void: _draw_spt_ruler_on(ruler))
	ruler.resized.connect(func() -> void: _rebuild_spt_ruler_labels(ruler))
	ruler_row.add_child(ruler)
	_spt_ruler = ruler
	call_deferred("_rebuild_spt_ruler_labels", ruler)

	var tracks := VBoxContainer.new()
	tracks.name = "TimelineTracksContainer"
	tracks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracks.add_theme_constant_override("separation", 4)
	timeline_content.add_child(tracks)
	_spt_tracks_container = tracks


func _make_timeline_tool_button(text: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(42, 30)
	btn.add_theme_stylebox_override("normal", _host._outlined_sb(Color("243142"), Color("334155"), 5, 7, 4))
	btn.add_theme_stylebox_override("hover", _host._outlined_sb(Color("2F4056"), Color("60A5FA"), 5, 7, 4))
	btn.add_theme_stylebox_override("pressed", _host._outlined_sb(Color("1D4ED8"), Color("93C5FD"), 5, 7, 4))
	btn.add_theme_stylebox_override("disabled", _host._outlined_sb(Color("1F2937"), Color("334155"), 5, 7, 4))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", SPT_EDITOR_TEXT)
	btn.add_theme_color_override("font_hover_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_disabled_color", Color("64748B"))
	return btn


func _make_timeline_legend_chip(
	text: String, fill: Color, border: Color, tooltip: String
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.tooltip_text = tooltip
	panel.add_theme_stylebox_override("panel", _host._outlined_sb(fill, border, 5, 7, 3))
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _host._clay_font_bold())
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("E5E7EB"))
	panel.add_child(label)
	return panel


func _update_timeline_mode_buttons() -> void:
	_clear_spt_cursor_if_invalid()
	var editable: bool = not _host._playback_mode and not _host._is_playing
	var target_actor_idx := _timeline_add_target_actor_idx()
	var target_time_ms := _timeline_add_target_time_ms(target_actor_idx)
	if _timeline_add_button != null:
		var can_add: bool = editable and target_actor_idx >= 0 and target_actor_idx < _host._actors.size()
		_timeline_add_button.disabled = not can_add
		if can_add:
			_timeline_add_button.text = "Add @ %dms" % target_time_ms
			_timeline_add_button.tooltip_text = "Create keyframe on %s at %dms" % [
				_host._role_id_for(target_actor_idx), target_time_ms,
			]
		else:
			_timeline_add_button.text = "Add"
			_timeline_add_button.tooltip_text = "Select an actor track before adding"
	if _timeline_delete_button != null:
		_timeline_delete_button.disabled = not editable \
				or _host._selected_spt_actor_idx < 0 \
				or _host._selected_spt_kf_idx < 0
	if _timeline_warnings_button != null:
		var warning_count := _collect_spt_warnings().size()
		_timeline_warnings_button.text = "Warnings %d" % warning_count
		_timeline_warnings_button.tooltip_text = "No timeline warnings" if warning_count == 0 else "Open %d timeline warnings" % warning_count
		_timeline_warnings_button.disabled = false
		var warning_bg := Color("243142") if warning_count == 0 else Color("451A03")
		var warning_border := Color("334155") if warning_count == 0 else Color("F59E0B")
		_timeline_warnings_button.add_theme_stylebox_override("normal", _host._outlined_sb(warning_bg, warning_border, 5, 7, 4))
		_timeline_warnings_button.add_theme_stylebox_override("hover", _host._outlined_sb(warning_bg.lightened(0.1), warning_border, 5, 7, 4))
	if _timeline_status_label != null:
		_timeline_status_label.text = _timeline_status_text()


func _timeline_add_target_actor_idx() -> int:
	if _spt_cursor_actor_idx >= 0 and _spt_cursor_actor_idx < _host._actors.size():
		return _spt_cursor_actor_idx
	if _host._selected_kind == _host.SELECT_KEYFRAME \
			and _host._selected_spt_actor_idx >= 0 \
			and _host._selected_spt_actor_idx < _host._actors.size():
		return _host._selected_spt_actor_idx
	if _host._selected_kind == _host.SELECT_ACTOR \
			and _host._selected_actor_idx >= 0 \
			and _host._selected_actor_idx < _host._actors.size():
		return _host._selected_actor_idx
	return -1


func _timeline_add_target_time_ms(actor_idx: int) -> int:
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return 0
	if _spt_cursor_actor_idx == actor_idx:
		return _spt_cursor_time_ms
	return _next_keyframe_time_for(actor_idx)


func _timeline_status_text() -> String:
	if _host._is_playing or _host._playback_mode:
		return "Playback"
	if _host._selected_spt_actor_idx >= 0 \
			and _host._selected_spt_actor_idx < _host._actors.size() \
			and _host._selected_spt_kf_idx >= 0:
		var track: Array = (_host._actors[_host._selected_spt_actor_idx] as Dictionary).get("track", []) as Array
		if _host._selected_spt_kf_idx < track.size():
			var kf: Dictionary = track[_host._selected_spt_kf_idx] as Dictionary
			var skill_id := str(kf.get("skill", ""))
			var skill_cfg: AbilityConfig = _host._get_skill_config(skill_id)
			var skill_name := skill_cfg.display_name if skill_cfg != null else skill_id
			return "Selected %s @ %dms" % [skill_name, int(kf.get("time_ms", 0))]
	if _spt_cursor_actor_idx >= 0 and _spt_cursor_actor_idx < _host._actors.size():
		return "Cursor %s @ %dms" % [_host._role_id_for(_spt_cursor_actor_idx), _spt_cursor_time_ms]
	if _host._selected_spt_actor_idx >= 0 and _host._selected_spt_actor_idx < _host._actors.size():
		return "Selected %s" % _host._role_id_for(_host._selected_spt_actor_idx)
	return "Ready"


# ========== UI: SkillPreviewTimeline tab ==========
#
# 视图全部从 _host._actors[i] 派生, 不引入新数据 (除 _spt_max_override 一个 int)。
# 重建职责严格分离:
#   _rebuild_spt_ui            只重建节点 (清空 + 每 actor 一行 row)
#   _layout_keyframes_for_row  只调整 KeyframeButton 的 position/size
# resized signal 触发 layout(不重建), 避免 flicker。

func _rebuild_spt_ui() -> void:
	_host._inspector_rebuild_queued = false
	_clear_spt_cursor_if_invalid()
	if _spt_max_auto_label != null:
		_spt_max_auto_label.text = "auto = %d ms" % _compute_auto_max_ms()
	var track_w := _spt_track_width()
	if _spt_ruler != null:
		_spt_ruler.custom_minimum_size = Vector2(track_w, SPT_RULER_H)
		_spt_ruler.queue_redraw()
		_rebuild_spt_ruler_labels(_spt_ruler)
	if _timeline_tracks_container != null:
		_timeline_tracks_container.custom_minimum_size = Vector2(track_w, 0)
	_rebuild_spt_track_container(_spt_tracks_container, true)
	_rebuild_spt_track_container(_timeline_tracks_container, false)
	_rebuild_spt_warning_list()
	_update_timeline_mode_buttons()


func _rebuild_spt_track_container(container: VBoxContainer, include_actor_label: bool) -> void:
	if container == null:
		return
	for c in container.get_children():
		c.queue_free()
	for i in _host._actors.size():
		container.add_child(_build_track_row(i, include_actor_label))


## 一行 actor track: [ActorLabel(min_w=110)] [TrackArea(expand)]。
## TrackArea Control 上挂: baseline draw / 每条 keyframe 一个 Button 子节点 /
## 空白点击 gui_input handler。
func _build_track_row(actor_idx: int, include_actor_label: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, SPT_ROW_H)
	row.add_theme_constant_override("separation", 0)
	row.add_theme_stylebox_override("panel", _host._outlined_sb(SPT_EDITOR_ROW, Color("243142"), 0, 0, 0))

	if include_actor_label:
		row.add_child(_build_timeline_actor_label(actor_idx))

	var track_area := Control.new()
	track_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_area.custom_minimum_size = Vector2(_spt_track_width(), SPT_ROW_H)
	# STOP 而非 PASS: 自己处理空白处单击选轨 / 双击新增; KeyframeButton 子节点默认 STOP
	# 优先吃事件, 命中 button 时不会传到这里。
	track_area.mouse_filter = Control.MOUSE_FILTER_STOP
	track_area.tooltip_text = "Click sets the Add cursor; double-click creates a keyframe at that time"
	track_area.draw.connect(_draw_track_row.bind(actor_idx, track_area))
	# 每条 keyframe 一个 Button 子节点; position 由 _layout_keyframes_for_row 后期填。
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	for k in track.size():
		track_area.add_child(_build_keyframe_button(actor_idx, k))
	# 容器尺寸 settle 后/任意 resize 触发 layout, 不重建节点。
	track_area.resized.connect(func() -> void: _layout_keyframes_for_row(actor_idx, track_area))
	track_area.gui_input.connect(func(event: InputEvent) -> void:
		_on_track_area_clicked(actor_idx, track_area, event)
	)
	# 首次 build: layout 时 size 还没 settle, 推迟一帧。
	call_deferred("_layout_keyframes_for_row", actor_idx, track_area)
	row.add_child(track_area)

	return row


func _build_timeline_actor_label(actor_idx: int) -> Button:
	var actor_label := Button.new()
	actor_label.text = "%d  %s  %s" % [actor_idx, _actor_role_icon(actor_idx), _host._actor_timeline_label(actor_idx)]
	actor_label.tooltip_text = "Select actor"
	actor_label.custom_minimum_size = Vector2(SPT_ACTOR_LABEL_W, SPT_ROW_H)
	actor_label.alignment = HORIZONTAL_ALIGNMENT_LEFT
	actor_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actor_label.add_theme_stylebox_override("normal", _host._outlined_sb(SPT_EDITOR_PANEL, _actor_track_color(actor_idx, 0.85), 5, 10, 6))
	actor_label.add_theme_stylebox_override("hover", _host._outlined_sb(Color("1A2835"), _actor_track_color(actor_idx, 1.0), 5, 10, 6))
	actor_label.add_theme_stylebox_override("pressed", _host._outlined_sb(Color("12313A"), Color("7DD3FC"), 5, 10, 6))
	actor_label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	actor_label.add_theme_color_override("font_color", SPT_EDITOR_TEXT)
	actor_label.add_theme_color_override("font_hover_color", Color("FFFFFF"))
	actor_label.add_theme_color_override("font_pressed_color", Color("FFFFFF"))
	actor_label.add_theme_font_override("font", _host._clay_font_bold())
	actor_label.pressed.connect(func() -> void:
		_host._select_actor(actor_idx)
		if _host._inspector_tabs != null:
			_host._inspector_tabs.current_tab = 0
	)
	if _host._is_character_actor_selected(actor_idx):
		actor_label.add_theme_stylebox_override("normal", _host._outlined_sb(Color("12313A"), _actor_track_color(actor_idx, 1.0), 5, 10, 6))
	return actor_label


func _actor_role_icon(actor_idx: int) -> String:
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return "?"
	var data: Dictionary = _host._actors[actor_idx]
	if str(data.get("role", "")) == "caster":
		return "Caster"
	return "Ally" if str(data.get("team", "B")) == "A" else "Enemy"


## TrackArea: duration span / cooldown bar / baseline。draw 信号自身不带 sender 上下文。
func _draw_track_row(actor_idx: int, track_area: Control) -> void:
	var w := track_area.size.x
	var h := track_area.size.y
	if w <= 0.0 or h <= 0.0:
		return
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	var max_ms := _spt_max_ms()
	track_area.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), SPT_EDITOR_ROW, true)
	if actor_idx == _host._selected_spt_actor_idx:
		track_area.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), _actor_track_color(actor_idx, 0.08), true)
	_draw_spt_track_lanes(track_area, w, h)
	var tick_step := _pick_tick_step(max_ms)
	var tick := 0
	while tick <= max_ms:
		var tick_x := _track_x_for_time(tick, max_ms, w)
		track_area.draw_line(
			Vector2(tick_x, 0.0),
			Vector2(tick_x, h),
			SPT_EDITOR_GRID_MAJOR if tick % (tick_step * 2) == 0 else SPT_EDITOR_GRID,
			1.0
		)
		tick += tick_step
	for kf_variant in track:
		var kf: Dictionary = kf_variant as Dictionary
		var time_ms := int(kf.get("time_ms", 0))
		var skill_cfg: AbilityConfig = _host._get_skill_config(str(kf.get("skill", "")))
		if skill_cfg == null:
			continue
		var occupy_ms := SkillPreviewValidation.ability_occupy_ms(skill_cfg)
		var cooldown_ms := SkillPreviewValidation.ability_cooldown_ms(skill_cfg)
		if occupy_ms > 0:
			var span_start := _track_x_for_time(time_ms, max_ms, w)
			var span_end := _track_x_for_time(time_ms + occupy_ms, max_ms, w)
			var span_rect := Rect2(
				Vector2(span_start, SPT_RELEASE_LANE_Y),
				Vector2(maxf(2.0, span_end - span_start), SPT_RELEASE_SPAN_H)
			)
			track_area.draw_rect(span_rect, _actor_track_color(actor_idx, 0.24), true)
			track_area.draw_rect(span_rect, _actor_track_color(actor_idx, 0.7), false, 1.0)
		if cooldown_ms > occupy_ms:
			var cooldown_start := _track_x_for_time(time_ms + occupy_ms, max_ms, w)
			var cooldown_end := _track_x_for_time(time_ms + cooldown_ms, max_ms, w)
			var cooldown_rect := Rect2(
				Vector2(cooldown_start, SPT_COOLDOWN_LANE_Y),
				Vector2(maxf(2.0, cooldown_end - cooldown_start), 10.0)
			)
			track_area.draw_rect(cooldown_rect, Color(0.65, 0.68, 0.75, 0.2), true)
			track_area.draw_rect(cooldown_rect, Color(0.65, 0.68, 0.75, 0.38), false, 1.0)
	_draw_spt_runtime_markers(actor_idx, track_area, max_ms, w)
	var y := SPT_KF_LANE_CENTER_Y
	track_area.draw_line(Vector2(0, y), Vector2(w, y), Color(1.0, 1.0, 1.0, 0.22), 1)
	if _spt_cursor_actor_idx == actor_idx:
		var cursor_x := _track_x_for_time(_spt_cursor_time_ms, max_ms, w)
		track_area.draw_line(Vector2(cursor_x, 3.0), Vector2(cursor_x, h - 3.0), SPT_CURSOR_COLOR, 2.0)
		track_area.draw_circle(Vector2(cursor_x, y), 4.0, SPT_CURSOR_COLOR)
	if _spt_dragging and _spt_drag_actor_idx == actor_idx:
		var ghost_x := _track_x_for_time(_spt_drag_requested_ms, max_ms, w)
		track_area.draw_line(Vector2(ghost_x, 4.0), Vector2(ghost_x, h - 4.0), Color("FFFFFF"), 2.0)
		track_area.draw_circle(Vector2(ghost_x, y), 4.0, Color("FFFFFF"))


func _draw_spt_track_lanes(track_area: Control, w: float, h: float) -> void:
	track_area.draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(w, 47.0)), Color(0.04, 0.07, 0.10, 0.22), true)
	track_area.draw_rect(Rect2(Vector2(0.0, 48.0), Vector2(w, 38.0)), Color(0.0, 0.0, 0.0, 0.12), true)
	track_area.draw_line(Vector2(0.0, 48.0), Vector2(w, 48.0), Color(1.0, 1.0, 1.0, 0.08), 1.0)
	track_area.draw_line(Vector2(0.0, 70.0), Vector2(w, 70.0), Color(1.0, 1.0, 1.0, 0.06), 1.0)
	track_area.draw_line(Vector2(0.0, 86.0), Vector2(w, 86.0), Color(1.0, 1.0, 1.0, 0.06), 1.0)
	track_area.draw_line(Vector2(0.0, h - 1.0), Vector2(w, h - 1.0), Color(1.0, 1.0, 1.0, 0.08), 1.0)


func _draw_spt_runtime_markers(actor_idx: int, track_area: Control, max_ms: int, w: float) -> void:
	var actor_id: String = _host._actor_id_for_idx(actor_idx)
	if actor_id == "" or _host._last_timeline.is_empty():
		return
	for entry_variant in _host._last_timeline.get("timeline", []):
		var entry := entry_variant as Dictionary
		var frame_ms: int = int(entry.get("frame", 0)) * _host.TICK_INTERVAL_MS
		var x := _track_x_for_time(frame_ms, max_ms, w)
		for event_variant in entry.get("events", []):
			var ev := event_variant as Dictionary
			var marker_color := _runtime_marker_color_for_actor(actor_id, ev)
			if marker_color.a <= 0.0:
				continue
			track_area.draw_circle(Vector2(x, SPT_RESULT_LANE_Y), 3.5, marker_color)
			track_area.draw_line(
				Vector2(x, SPT_RESULT_LANE_Y - 5.0),
				Vector2(x, SPT_RESULT_LANE_Y + 5.0),
				marker_color,
				1.0
			)


func _runtime_marker_color_for_actor(actor_id: String, ev: Dictionary) -> Color:
	match str(ev.get("kind", "")):
		"damage":
			if str(ev.get("target_actor_id", "")) == actor_id:
				return Color("F87171")
		"heal":
			if str(ev.get("target_actor_id", "")) == actor_id:
				return Color("34D399")
		"death":
			if str(ev.get("actor_id", "")) == actor_id:
				return Color("EF4444")
		"abilityTriggered", "executionActivated":
			if str(ev.get("actor_id", "")) == actor_id or str(ev.get("source_actor_id", "")) == actor_id:
				return Color("60A5FA")
	return Color(0.0, 0.0, 0.0, 0.0)


## Keyframe 色块按钮: 颜色按 actor team 区分(caster=绿/A=蓝/B=红);
## 按钮正文显示技能名, 详细时间/目标走 tooltip。点击/拖拽会同步右侧 Details。
func _build_keyframe_button(actor_idx: int, kf_idx: int) -> Button:
	var btn := Button.new()
	btn.set_meta("kf_idx", kf_idx)
	btn.size = Vector2(SPT_KF_BTN_W, SPT_KF_BTN_H)
	btn.custom_minimum_size = Vector2(SPT_KF_BTN_W, SPT_KF_BTN_H)
	btn.tooltip_text = _keyframe_tooltip(actor_idx, kf_idx)
	btn.text = _keyframe_button_text(actor_idx, kf_idx)
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.focus_mode = Control.FOCUS_NONE

	var bg: Color
	var border: Color
	var data: Dictionary = _host._actors[actor_idx]
	if data["role"] == "caster":
		bg = Color("14532D"); border = Color("86EFAC")
	elif data["team"] == "A":
		bg = Color("164E63"); border = Color("7DD3FC")
	else:
		bg = Color("7F1D1D"); border = Color("FCA5A5")
	var warning := _keyframe_timing_warning(actor_idx, kf_idx)
	if not warning.is_empty():
		var warning_type := str(warning.get("type", ""))
		border = _spt_warning_color(warning_type)
	if actor_idx == _host._selected_spt_actor_idx and kf_idx == _host._selected_spt_kf_idx:
		border = Color("FFFFFF")
	btn.add_theme_stylebox_override("normal", _host._outlined_sb(bg, border, 4, 0, 0))
	btn.add_theme_stylebox_override("hover", _host._outlined_sb(bg.lightened(0.1), border, 4, 0, 0))
	btn.add_theme_stylebox_override("pressed", _host._outlined_sb(bg.darkened(0.1), border, 4, 0, 0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", _host._clay_font_bold())
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_hover_color", Color("FFFFFF"))
	btn.add_theme_color_override("font_pressed_color", Color("FFFFFF"))
	btn.gui_input.connect(func(event: InputEvent) -> void:
		_on_keyframe_button_gui_input(actor_idx, int(btn.get_meta("kf_idx", -1)), btn, event)
	)
	return btn


func _keyframe_button_text(actor_idx: int, kf_idx: int) -> String:
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return "?"
	var skill_id := str((track[kf_idx] as Dictionary).get("skill", ""))
	var skill_cfg: AbilityConfig = _host._get_skill_config(skill_id)
	if skill_cfg == null:
		return skill_id
	return skill_cfg.display_name


## tooltip 文本: "Strike @ 600ms → enemy_0"。target 模式简写。
func _keyframe_tooltip(actor_idx: int, kf_idx: int) -> String:
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return ""
	var kf: Dictionary = track[kf_idx]
	var skill_name := str(kf.get("skill", "?"))
	var skill_cfg: AbilityConfig = _host._get_skill_config(skill_name)
	var time_ms := int(kf.get("time_ms", 0))
	var target: Dictionary = kf.get("target", {}) as Dictionary
	var mode := str(target.get("mode", "auto"))
	var target_str: String = _host._target_mode_label(mode)
	if _host._skill_uses_self_target(skill_cfg):
		target_str = "Self"
	else:
		match mode:
			"enemy_index", "ally_index":
				target_str = "%s %d" % [_host._target_mode_label(mode), int(target.get("index", 0))]
			"fixed_pos":
				target_str = "(%d,%d)" % [int(target.get("q", 0)), int(target.get("r", 0))]
		var resolved_idx: int = _host._resolve_target_actor_idx_for_ui(actor_idx, target)
		if resolved_idx >= 0:
			target_str += " -> %s" % _host._role_id_for(resolved_idx)
	var timing_parts: Array[String] = []
	var occupy_ms := SkillPreviewValidation.ability_occupy_ms(skill_cfg)
	var cooldown_ms := SkillPreviewValidation.ability_cooldown_ms(skill_cfg)
	if occupy_ms > 0:
		timing_parts.append("release %d-%dms" % [time_ms, time_ms + occupy_ms])
	if cooldown_ms > 0:
		timing_parts.append("cooldown ready %dms" % (time_ms + cooldown_ms))
	var lines: Array[String] = ["%s @ %dms -> %s" % [skill_name, time_ms, target_str]]
	if not timing_parts.is_empty():
		lines.append(", ".join(timing_parts))
	var warning := _keyframe_timing_warning(actor_idx, kf_idx)
	if not warning.is_empty():
		lines.append("Warning: %s" % str(warning.get("message", "")))
	return "\n".join(lines)


func _keyframe_timing_warning(actor_idx: int, kf_idx: int) -> Dictionary:
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return {}
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return {}
	var current: Dictionary = track[kf_idx] as Dictionary
	var current_t := int(current.get("time_ms", 0))
	var current_skill := str(current.get("skill", ""))
	for release_idx in track.size():
		if release_idx == kf_idx:
			continue
		var release_kf: Dictionary = track[release_idx] as Dictionary
		var release_t := int(release_kf.get("time_ms", 0))
		if release_t > current_t:
			continue
		var release_skill := str(release_kf.get("skill", ""))
		var release_cfg: AbilityConfig = _host._get_skill_config(release_skill)
		if release_cfg == null:
			continue
		var occupy_ms := SkillPreviewValidation.ability_occupy_ms(release_cfg)
		if occupy_ms > 0 and current_t < release_t + occupy_ms:
			var warning_type := "release_conflict" if release_skill == current_skill else "overlap"
			return {
				"type": warning_type,
				"message": "%s starts inside %s release window (%d-%dms)" % [
					current_skill, release_skill, release_t, release_t + occupy_ms,
				],
				"source_idx": release_idx,
			}
	for other_idx in track.size():
		if other_idx == kf_idx:
			continue
		var other: Dictionary = track[other_idx] as Dictionary
		var other_t := int(other.get("time_ms", 0))
		if other_t > current_t:
			continue
		var other_skill := str(other.get("skill", ""))
		var other_cfg: AbilityConfig = _host._get_skill_config(other_skill)
		if other_cfg == null:
			continue
		var cooldown_ms := SkillPreviewValidation.ability_cooldown_ms(other_cfg)
		if other_skill == current_skill and cooldown_ms > 0 \
				and current_t > other_t and current_t < other_t + cooldown_ms:
			return {
				"type": "cooldown",
				"message": "%s cooldown ready at %dms" % [current_skill, other_t + cooldown_ms],
				"ready_ms": other_t + cooldown_ms,
				"source_idx": other_idx,
			}
	return {}


static func _spt_warning_color(warning_type: String) -> Color:
	if warning_type == "cooldown" or warning_type == "release_conflict":
		return SPT_WARNING_COOLDOWN
	return SPT_WARNING_OVERLAP


func _actor_track_color(actor_idx: int, alpha: float) -> Color:
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return Color(0.45, 0.5, 0.6, alpha)
	var data: Dictionary = _host._actors[actor_idx]
	if data["role"] == "caster":
		return Color(0.09, 0.64, 0.29, alpha)
	if data["team"] == "A":
		return Color(0.15, 0.39, 0.92, alpha)
	return Color(0.7, 0.23, 0.23, alpha)


func _track_x_for_time(time_ms: int, max_ms: int, width: float) -> float:
	if max_ms <= 0:
		return 0.0
	var ratio := clampf(float(time_ms) / float(max_ms), 0.0, 1.0)
	return ratio * width


## 重排 track_area 内所有 KeyframeButton 的 position/size, 不创建/删除节点。
## resized signal / 首次 build call_deferred / span override 改变后 _rebuild_spt_ui
## 三处都会调到。
func _layout_keyframes_for_row(actor_idx: int, track_area: Control) -> void:
	# Stale callback 防御: 该 row 是 deferred / resized 触发的, 但 actor 可能在
	# 这之间被 _remove_actor_at / _on_preset_load_selected 干掉了, 此时 actor_idx
	# 越界或落到了不同的 actor 上; track_area 也可能正在被 queue_free。
	if track_area == null or not is_instance_valid(track_area):
		return
	if track_area.is_queued_for_deletion():
		return
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	var max_ms := _spt_max_ms()
	var w := track_area.size.x
	for k in track.size():
		if k >= track_area.get_child_count():
			break
		var btn := track_area.get_child(k) as Button
		if btn == null:
			continue
		var t := int((track[k] as Dictionary).get("time_ms", 0))
		var ratio := clampf(float(t) / float(max_ms), 0.0, 1.0)
		var x := int(ratio * (w - SPT_KF_BTN_W))
		var lane := _keyframe_lane_for_time(track, k)
		var lane_count := _keyframe_lane_count_at_time(track, t)
		var group_h := float(lane_count) * float(SPT_KF_BTN_H) + float(maxi(0, lane_count - 1)) * 2.0
		var lane_top := maxf(2.0, SPT_KF_LANE_CENTER_Y - group_h * 0.5)
		var y := int(lane_top + float(lane) * (float(SPT_KF_BTN_H) + 2.0))
		btn.position = Vector2(x, y)
		btn.size = Vector2(SPT_KF_BTN_W, SPT_KF_BTN_H)


func _keyframe_lane_for_time(track: Array, kf_idx: int) -> int:
	if kf_idx < 0 or kf_idx >= track.size():
		return 0
	var time_ms := int((track[kf_idx] as Dictionary).get("time_ms", 0))
	var lane := 0
	for i in range(0, kf_idx):
		if int((track[i] as Dictionary).get("time_ms", 0)) == time_ms:
			lane += 1
	return lane


func _keyframe_lane_count_at_time(track: Array, time_ms: int) -> int:
	var count := 0
	for kf_variant in track:
		if int((kf_variant as Dictionary).get("time_ms", 0)) == time_ms:
			count += 1
	return maxi(1, count)


func _on_keyframe_button_gui_input(
	actor_idx: int, kf_idx: int, btn: Button, event: InputEvent
) -> void:
	if _host._is_playing:
		return
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	if kf_idx < 0 or kf_idx >= track.size():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_select_spt_keyframe(actor_idx, kf_idx)
			_spt_dragging = true
			_spt_drag_actor_idx = actor_idx
			_spt_drag_kf_idx = kf_idx
			_spt_drag_requested_ms = int((track[kf_idx] as Dictionary).get("time_ms", 0))
			_spt_drag_track_area = btn.get_parent() as Control
			_spt_drag_grab_offset_x = clampf(mb.position.x, 0.0, float(SPT_KF_BTN_W))
			if _spt_drag_track_area != null:
				_spt_drag_track_area.queue_redraw()
		else:
			_commit_spt_drag()
	elif event is InputEventMouseMotion:
		if not _is_dragging_keyframe(actor_idx, kf_idx):
			return
		_update_spt_drag_from_viewport()


func _update_spt_drag_from_viewport() -> void:
	if not _spt_dragging:
		return
	var track_area := _spt_drag_track_area
	if track_area == null or not is_instance_valid(track_area):
		return
	if track_area.size.x <= 0.0:
		return
	var mouse_pos := _host.get_viewport().get_mouse_position()
	var local_x := mouse_pos.x - track_area.get_global_rect().position.x
	var button_x := local_x - _spt_drag_grab_offset_x
	_spt_drag_requested_ms = _time_for_keyframe_button_x(button_x, track_area.size.x)
	track_area.queue_redraw()
	_host._rebuild_actors_ui()


func _commit_spt_drag() -> void:
	if not _spt_dragging:
		return
	var actor_idx := _spt_drag_actor_idx
	var kf_idx := _spt_drag_kf_idx
	var requested_ms := _spt_drag_requested_ms
	if _is_dragging_keyframe(actor_idx, kf_idx):
		var final_ms: int = _host._on_keyframe_time_changed(actor_idx, kf_idx, requested_ms)
		_select_spt_keyframe(actor_idx, kf_idx)
		if final_ms != requested_ms:
			_host._set_status("Moved to %dms: same skill release window is occupied" % final_ms)
	_clear_spt_drag_state()
	_rebuild_spt_ui()


func _clear_spt_drag_state() -> void:
	var redraw_area := _spt_drag_track_area
	_spt_dragging = false
	_spt_drag_actor_idx = -1
	_spt_drag_kf_idx = -1
	_spt_drag_requested_ms = 0
	_spt_drag_track_area = null
	_spt_drag_grab_offset_x = 0.0
	if redraw_area != null and is_instance_valid(redraw_area):
		redraw_area.queue_redraw()


func _is_dragging_keyframe(actor_idx: int, kf_idx: int) -> bool:
	return _spt_dragging and _spt_drag_actor_idx == actor_idx and _spt_drag_kf_idx == kf_idx


func _time_for_track_x(x: float, width: float) -> int:
	if width <= 0.0:
		return 0
	var ratio := clampf(x / width, 0.0, 1.0)
	return int(round(ratio * float(_spt_max_ms()) / float(_host.KF_TIME_STEP_MS))) * _host.KF_TIME_STEP_MS


func _time_for_keyframe_button_x(x: float, width: float) -> int:
	var usable_w := maxf(1.0, width - float(SPT_KF_BTN_W))
	var ratio := clampf(x / usable_w, 0.0, 1.0)
	return int(round(ratio * float(_spt_max_ms()) / float(_host.KF_TIME_STEP_MS))) * _host.KF_TIME_STEP_MS


func _set_spt_cursor(actor_idx: int, time_ms: int, redraw: bool = true) -> void:
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		_spt_cursor_actor_idx = -1
		_spt_cursor_time_ms = 0
	else:
		_spt_cursor_actor_idx = actor_idx
		_spt_cursor_time_ms = clampi(time_ms, 0, _spt_max_ms())
	if redraw:
		_queue_spt_track_redraw()
	_update_timeline_mode_buttons()


func _clear_spt_cursor_if_invalid() -> void:
	if _spt_cursor_actor_idx < 0:
		_spt_cursor_actor_idx = -1
		_spt_cursor_time_ms = 0
		return
	if _spt_cursor_actor_idx >= _host._actors.size():
		_spt_cursor_actor_idx = -1
		_spt_cursor_time_ms = 0
		return
	_spt_cursor_time_ms = clampi(_spt_cursor_time_ms, 0, _spt_max_ms())


func _queue_spt_track_redraw() -> void:
	var containers: Array[VBoxContainer] = []
	if _spt_tracks_container != null:
		containers.append(_spt_tracks_container)
	if _timeline_tracks_container != null:
		containers.append(_timeline_tracks_container)
	for container in containers:
		for row_variant in container.get_children():
			var row := row_variant as Control
			if row == null:
				continue
			row.queue_redraw()
			for child_variant in row.get_children():
				var child := child_variant as Control
				if child != null:
					child.queue_redraw()


func _set_spt_selection(actor_idx: int, kf_idx: int) -> void:
	_host._selected_spt_actor_idx = actor_idx
	_host._selected_spt_kf_idx = kf_idx
	if actor_idx >= 0 and kf_idx >= 0:
		_host._selected_kind = _host.SELECT_KEYFRAME
		_host._selected_actor_idx = -1
		_host._selected_environment_idx = -1
		_host._details_popup_user_closed = false
		if actor_idx < _host._actors.size():
			_host._selected_hex = _host._actor_coord(actor_idx)
			var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
			if kf_idx < track.size():
				_set_spt_cursor(actor_idx, int((track[kf_idx] as Dictionary).get("time_ms", 0)), false)
		_host._update_hex_selection_cursor()
	elif actor_idx >= 0:
		_host._select_actor_at(actor_idx, false)


func _select_spt_keyframe(actor_idx: int, kf_idx: int) -> void:
	_set_spt_selection(actor_idx, kf_idx)
	_host._rebuild_actors_ui()
	_rebuild_spt_warning_list()


func _clear_spt_selection_if_invalid() -> void:
	if _host._selected_spt_actor_idx < 0 or _host._selected_spt_actor_idx >= _host._actors.size():
		_host._selected_spt_actor_idx = -1
		_host._selected_spt_kf_idx = -1
		return
	if _host._selected_spt_kf_idx < 0:
		return
	var track: Array = (_host._actors[_host._selected_spt_actor_idx] as Dictionary).get("track", []) as Array
	if _host._selected_spt_kf_idx >= track.size():
		_host._selected_spt_kf_idx = track.size() - 1


func _rebuild_spt_warning_list() -> void:
	if _timeline_warning_list == null:
		return
	for c in _timeline_warning_list.get_children():
		c.queue_free()
	var warnings := _collect_spt_warnings()
	if warnings.is_empty():
		var ok := Label.new()
		ok.text = "No timeline warnings"
		ok.add_theme_color_override("font_color", _host.CLAY_TEXT_SOFT)
		_timeline_warning_list.add_child(ok)
		return
	for warning in warnings:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var focus_btn := Button.new()
		var actor_idx := int(warning.get("actor_idx", -1))
		var kf_idx := int(warning.get("kf_idx", -1))
		focus_btn.text = str(warning.get("message", ""))
		focus_btn.tooltip_text = "Focus keyframe"
		focus_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		focus_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var warning_type := str(warning.get("type", ""))
		var border := _spt_warning_color(warning_type)
		focus_btn.add_theme_stylebox_override("normal", _host._outlined_sb(Color("1F2937"), border, 5, 8, 5))
		focus_btn.add_theme_stylebox_override("hover", _host._outlined_sb(Color("2A3445"), border, 5, 8, 5))
		focus_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		focus_btn.pressed.connect(func() -> void:
			_host._apply_timeline_workspace_layout()
			_select_spt_keyframe(actor_idx, kf_idx)
			_rebuild_spt_ui()
		)
		row.add_child(focus_btn)
		if warning_type == "cooldown":
			var fix_btn := Button.new()
			fix_btn.text = "Ready"
			fix_btn.tooltip_text = "Move to ready time"
			fix_btn.pressed.connect(func() -> void: _move_keyframe_to_ready_time(actor_idx, kf_idx))
			row.add_child(fix_btn)
		var source_idx := int(warning.get("source_idx", -1))
		if source_idx >= 0:
			var source_btn := Button.new()
			source_btn.text = "Source"
			source_btn.tooltip_text = "Select conflicting keyframe"
			source_btn.pressed.connect(func() -> void:
				_host._apply_timeline_workspace_layout()
				_select_spt_keyframe(actor_idx, source_idx)
				_rebuild_spt_ui()
			)
			row.add_child(source_btn)
		_timeline_warning_list.add_child(row)


func _collect_spt_warnings() -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	for actor_idx in _host._actors.size():
		var actor_data: Dictionary = _host._actors[actor_idx]
		var track: Array = actor_data.get("track", []) as Array
		for kf_idx in track.size():
			var kf: Dictionary = track[kf_idx] as Dictionary
			var skill_id := str(kf.get("skill", ""))
			var time_ms := int(kf.get("time_ms", 0))
			var skill_cfg: AbilityConfig = _host._get_skill_config(skill_id)
			if skill_cfg == null:
				warnings.append({
					"type": "error",
					"actor_idx": actor_idx,
					"kf_idx": kf_idx,
					"message": "%s @ %dms unknown skill: %s" % [_host._role_id_for(actor_idx), time_ms, skill_id],
				})
				continue
			var target: Dictionary = kf.get("target", {"mode": "auto"}) as Dictionary
			var target_idx: int = _host._resolve_target_actor_idx_for_ui(actor_idx, target)
			if _host._skill_requires_external_target(skill_cfg) and target_idx < 0:
				warnings.append({
					"type": "error",
					"actor_idx": actor_idx,
					"kf_idx": kf_idx,
					"message": "%s @ %dms invalid target" % [_host._role_id_for(actor_idx), time_ms],
				})
			var timing_warning := _keyframe_timing_warning(actor_idx, kf_idx)
			if not timing_warning.is_empty():
				timing_warning["actor_idx"] = actor_idx
				timing_warning["kf_idx"] = kf_idx
				timing_warning["message"] = "%s @ %dms: %s" % [
					_host._role_id_for(actor_idx), time_ms, str(timing_warning.get("message", "")),
				]
				warnings.append(timing_warning)
	return warnings


func _move_keyframe_to_ready_time(actor_idx: int, kf_idx: int) -> void:
	var warning := _keyframe_timing_warning(actor_idx, kf_idx)
	if str(warning.get("type", "")) != "cooldown":
		return
	var ready_ms := int(warning.get("ready_ms", 0))
	var final_ms: int = _host._on_keyframe_time_changed(actor_idx, kf_idx, ready_ms)
	_select_spt_keyframe(actor_idx, kf_idx)
	_host._set_status("Moved keyframe to ready time: %dms" % final_ms)
	_rebuild_spt_ui()


func _on_timeline_add_keyframe_pressed() -> void:
	var actor_idx := _timeline_add_target_actor_idx()
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		_host._set_status("Select an actor track before adding")
		return
	var requested_ms := _timeline_add_target_time_ms(actor_idx)
	var new_idx: int = _host._add_keyframe_at(actor_idx, requested_ms)
	if new_idx >= 0:
		_select_spt_keyframe(actor_idx, new_idx)
		var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
		var final_ms := requested_ms
		if new_idx < track.size():
			final_ms = int((track[new_idx] as Dictionary).get("time_ms", requested_ms))
		_set_spt_cursor(actor_idx, final_ms, false)
		_host._set_status("Added keyframe to %s at %dms" % [_host._role_id_for(actor_idx), final_ms])


func _next_keyframe_time_for(actor_idx: int) -> int:
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return 0
	var track: Array = (_host._actors[actor_idx] as Dictionary).get("track", []) as Array
	var t := 0
	for kf_variant in track:
		t = maxi(t, int((kf_variant as Dictionary).get("time_ms", 0)) + _host.KF_TIME_STEP_MS)
	return mini(t, _spt_max_ms())


## TrackArea 空白处单击只移动 Add cursor; 双击才按点击位置新增 keyframe。
func _on_track_area_clicked(actor_idx: int, track_area: Control, event: InputEvent) -> void:
	if _host._is_playing:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	if track_area == null or not is_instance_valid(track_area) or track_area.size.x <= 0.0:
		return
	if actor_idx < 0 or actor_idx >= _host._actors.size():
		return  # row 在 free 队列中, actor 已变 — 忽略点击
	var raw_ms := _time_for_track_x(mb.position.x, track_area.size.x)
	_set_spt_cursor(actor_idx, raw_ms)
	if not mb.double_click:
		_host._select_actor_at(actor_idx)
		_host._set_status(
			"Cursor set on %s at %dms" % [_host._role_id_for(actor_idx), raw_ms]
		)
		_host.get_viewport().set_input_as_handled()
		return
	var new_idx: int = _host._add_keyframe_at(actor_idx, raw_ms)
	if new_idx >= 0:
		_select_spt_keyframe(actor_idx, new_idx)
		_host._set_status("Added keyframe at %dms" % raw_ms)
	_host.get_viewport().set_input_as_handled()


## auto-fit: 取所有 keyframe 最大 time_ms + buffer, 并保证不低于 1000ms 防空 track 退化。
func _compute_auto_max_ms() -> int:
	var m := 0
	for actor_data in _host._actors:
		var track: Array = (actor_data as Dictionary).get("track", []) as Array
		for kf in track:
			m = maxi(m, int((kf as Dictionary).get("time_ms", 0)))
	return maxi(m + SPT_AUTO_BUFFER_MS, SPT_MIN_AUTO_MS)


## 当前生效的时间轴 max。override>0 强制覆盖。纯函数, 不写 status —— 警告由
## _warn_if_override_below_keyframes 在 mutation 点单次触发。
func _spt_max_ms() -> int:
	if _spt_max_override > 0:
		return _spt_max_override
	return _compute_auto_max_ms()


func _spt_track_width() -> float:
	return maxf(SPT_MIN_TRACK_W, float(_spt_max_ms()) * SPT_MS_TO_PX)


## Override 比实际最大 keyframe 还小时, 在改 override 的 SpinBox 上即时提醒一次。
func _warn_if_override_below_keyframes() -> void:
	if _spt_max_override <= 0:
		return
	var max_kf_ms := _compute_auto_max_ms() - SPT_AUTO_BUFFER_MS
	if _spt_max_override < max_kf_ms:
		_host._set_status("Override below max keyframe (%d ms)" % max_kf_ms)


## 根据 max_ms 选合适的刻度步长 (250/500/1000/2000), 比固定 5 段更直观。
func _pick_tick_step(max_ms: int) -> int:
	if max_ms <= 1500:
		return 250
	if max_ms <= 3000:
		return 500
	if max_ms <= 8000:
		return 1000
	return 2000


func _draw_spt_ruler_on(ruler: Control) -> void:
	if ruler == null:
		return
	var max_ms := _spt_max_ms()
	var step := _pick_tick_step(max_ms)
	var w := ruler.size.x
	var h := ruler.size.y
	if w <= 0.0:
		return
	ruler.draw_rect(Rect2(Vector2.ZERO, ruler.size), SPT_EDITOR_BG, true)
	var t := 0
	while t <= max_ms:
		var x := int(float(t) / float(max_ms) * w)
		var is_major := t % (step * 2) == 0
		ruler.draw_line(
			Vector2(x, SPT_RULER_LABEL_H + 4.0),
			Vector2(x, h - 4.0),
			SPT_EDITOR_GRID_MAJOR if is_major else SPT_EDITOR_GRID,
			1.0
		)
		t += step


func _rebuild_spt_ruler_labels(ruler: Control) -> void:
	if ruler == null or not is_instance_valid(ruler):
		return
	if ruler.is_queued_for_deletion():
		return
	for child_variant in ruler.get_children():
		var child := child_variant as Node
		if child != null:
			ruler.remove_child(child)
			child.queue_free()
	var max_ms := _spt_max_ms()
	var step := _pick_tick_step(max_ms) * 2
	var w := ruler.size.x
	if w <= 0.0 or max_ms <= 0:
		return
	var t := 0
	while t <= max_ms:
		var tick_x := float(t) / float(max_ms) * w
		var label := Label.new()
		label.text = _format_spt_ruler_time(t)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(SPT_RULER_LABEL_W, SPT_RULER_LABEL_H)
		label.size = Vector2(SPT_RULER_LABEL_W, SPT_RULER_LABEL_H)
		label.position = Vector2(
			clampf(tick_x - SPT_RULER_LABEL_W * 0.5, 0.0, maxf(0.0, w - SPT_RULER_LABEL_W)),
			1.0
		)
		label.add_theme_font_override("font", _host._clay_font_bold())
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", SPT_EDITOR_TEXT_SOFT)
		ruler.add_child(label)
		t += step


func _format_spt_ruler_time(ms: int) -> String:
	if ms >= 1000 and ms % 1000 == 0:
		return "%ds" % int(ms / 1000)
	return "%dms" % ms
