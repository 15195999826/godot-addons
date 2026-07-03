## BattleAnimator - 战斗动画播放器（叠加层）
##
## 消费 BattleProcedure.finish() 产出的 event_timeline（兼容现阶段 v2
## 录像格式 dict），在 WorldView 提供的已有 unit view 上叠加飘字 / 特效 /
## 死亡动画。不拥有 unit view 生命周期 —— 战斗结束时 WorldGI 里 actor 已是
## 终态，animator 只负责让视觉追上该终态。
##
## 详见 docs/README.md（World owns Battle + 响应式前端 节）
class_name FrontendBattleAnimator
extends Node3D


# ========== 信号 ==========

signal playback_started
signal playback_ended
## 播放 / 暂停切换,供外部 UI 同步按钮态。
signal playback_state_changed(is_playing: bool)
## 当前帧推进,供外部 UI 显示进度。
signal frame_changed(current_frame: int, total_frames: int)


# ========== 内部组件 ==========

var _director: FrontendBattleDirector
var _replay_units_root: Node3D
var _effects_root: Node3D

var _unit_views: Dictionary = {}            # actor_id -> FrontendUnitView
var _base_unit_views: Dictionary = {}       # actor_id -> FrontendUnitView, owned by WorldView
var _excluded_base_unit_views: Dictionary = {} # actor_id -> FrontendUnitView, live-world mid-spawn views hidden during replay
var _owned_replay_unit_views: Dictionary = {} # actor_id -> FrontendUnitView, owned by animator
var _attack_vfx_views: Dictionary = {}      # vfx_id -> FrontendAttackVFXView
var _projectile_views: Dictionary = {}      # projectile_id -> FrontendProjectileView

const SPAWN_VIEW_COST_WARN_MS: float = 3.0
const FLOATING_TEXT_COST_WARN_MS: float = 2.0


# ========== 生命周期 ==========

func _ready() -> void:
	_replay_units_root = Node3D.new()
	_replay_units_root.name = "ReplayUnitsRoot"
	add_child(_replay_units_root)

	_effects_root = Node3D.new()
	_effects_root.name = "EffectsRoot"
	add_child(_effects_root)

	_director = FrontendBattleDirector.new()
	_director.name = "BattleDirector"
	add_child(_director)

	_director.actor_state_changed.connect(_on_actor_state_changed)
	_director.actor_spawned.connect(_on_actor_spawned)
	_director.actor_died.connect(_on_actor_died)
	_director.floating_text_created.connect(_on_floating_text_created)
	_director.attack_vfx_created.connect(_on_attack_vfx_created)
	_director.attack_vfx_updated.connect(_on_attack_vfx_updated)
	_director.attack_vfx_removed.connect(_on_attack_vfx_removed)
	_director.projectile_created.connect(_on_projectile_created)
	_director.projectile_updated.connect(_on_projectile_updated)
	_director.projectile_removed.connect(_on_projectile_removed)
	_director.cone_debug_overlay_created.connect(_on_cone_debug_overlay_created)
	_director.playback_ended.connect(_on_playback_ended)
	_director.playback_state_changed.connect(func(p: bool) -> void: playback_state_changed.emit(p))
	_director.frame_changed.connect(func(c: int, t: int) -> void: frame_changed.emit(c, t))


func _process(_delta: float) -> void:
	if _director == null or not _director.is_playing():
		return
	# 移动动画期间单位位置平滑更新:逻辑层 hex_position 跳跃,视觉层每帧 lerp 到目标。
	for actor_id in _unit_views:
		var view: FrontendUnitView = _unit_views[actor_id]
		if is_instance_valid(view):
			view.set_world_position(_director.get_actor_world_position(actor_id))


# ========== 公共 API ==========

## 加载战斗动画(不自动播放)。完成后 frame 停在 0,等 play() / resume() 启动。
## record_data: BattleProcedure.finish() 返回的 dict(v2 格式,含 initial_actors / map_config)。
## unit_views: actor_id -> FrontendUnitView 字典,由 WorldView 管理生命周期。
## 反复调用 = 重新加载(老 timeline 被替换,VFX/飘字/投射物清空)。
func load(record_data: Dictionary, unit_views: Dictionary) -> void:
	var record := PlaybackData.BattleRecord.from_dict(record_data)
	_clear_replay_unit_views()
	_base_unit_views = _filter_initial_base_unit_views(record, unit_views)
	_unit_views = _base_unit_views.duplicate()
	_clear_effects()

	_director.load_playback(record)
	_prebuild_replay_unit_views(record)


## 启动播放当前已 load 的 timeline;未 load 时 no-op。
## 调 set_speed() 调速;playback_ended signal 在所有动画排空时触发。
func play() -> void:
	if _director == null:
		return
	_director.play()
	playback_started.emit()


func stop() -> void:
	if _director != null:
		_director.pause()


## 暂停当前播放(可恢复);若已暂停或未启动,no-op。
func pause() -> void:
	if _director != null:
		_director.pause()


## 从暂停恢复播放;若已在播放或未启动,no-op。
func resume() -> void:
	if _director != null:
		_director.play()


## 重置到 frame 0,清空特效,复活所有 view。Reset 是 playback session control
## 不是战斗内事件,不走 Director signal — 直接遍历 view 调 revive() 拉回视觉态。
func reset() -> void:
	_clear_effects()
	_deactivate_replay_unit_views()
	_hide_excluded_base_unit_views()
	_unit_views = _base_unit_views.duplicate()
	if _director != null:
		_director.reset()
	for view in _unit_views.values():
		if is_instance_valid(view):
			view.revive()


func set_speed(speed: float) -> void:
	if _director != null:
		_director.set_speed(speed)


## 暂停态确定性步进回放(供 DevAgent 定格截图)。手动步进时 _process 的位置
## lerp 不跑,这里直接把 unit view 拉到 director 目标位,保证定格画面正确。
func step(delta_ms: float) -> void:
	if _director == null:
		return
	_director.step(delta_ms)
	for actor_id in _unit_views:
		var view: FrontendUnitView = _unit_views[actor_id]
		if is_instance_valid(view):
			view.snap_world_position(_director.get_actor_world_position(actor_id))


func is_playing() -> bool:
	return _director != null and _director.is_playing()


func get_total_frames() -> int:
	if _director == null:
		return 0
	return _director.get_total_frames()


func get_current_frame() -> int:
	if _director == null:
		return 0
	return _director.get_current_frame()


## 当前所有 actor 的视觉态(visual_hp / max_hp / position / is_dead 等),供测试 / UI 拉取。
func get_actors_snapshot() -> Dictionary:
	if _director == null:
		return {}
	return _director.get_actors_snapshot()


func is_ended() -> bool:
	return _director != null and _director.is_ended()


# ========== Director signal → 外部 unit view ==========

func _on_actor_spawned(actor_id: String, state: FrontendActorRenderState) -> void:
	if _unit_views.has(actor_id):
		_on_actor_state_changed(actor_id, state)
		return
	if _replay_units_root == null:
		return
	var start_usec := Time.get_ticks_usec()
	var view := _get_or_create_replay_unit_view(actor_id, state)
	if view == null:
		return
	view.revive()
	view.visible = true
	_initialize_replay_unit_view(view, actor_id, state)
	var world_position := _director.get_actor_world_position(actor_id)
	view.snap_world_position(world_position)
	_owned_replay_unit_views[actor_id] = view
	_unit_views[actor_id] = view
	var cost_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	if cost_ms >= SPAWN_VIEW_COST_WARN_MS or state.config_id == "fire_tile":
		print("[Frontend:FrameDiag] spawn_view actor=%s config=%s type=%s world_pos=%s cost_ms=%.2f" % [
			actor_id,
			state.config_id,
			state.type,
			world_position,
			cost_ms,
		])


func _prebuild_replay_unit_views(record: PlaybackData.BattleRecord) -> void:
	for frame_data: PlaybackData.FrameData in record.timeline:
		for event: Dictionary in frame_data.events:
			if event.get("kind", "") != "actorSpawned":
				continue
			var state := _actor_spawn_event_to_state(event)
			if state.id.is_empty() or _base_unit_views.has(state.id):
				continue
			var view := _get_or_create_replay_unit_view(state.id, state)
			if view == null:
				continue
			_initialize_replay_unit_view(view, state.id, state)
			view.visible = false


func _actor_spawn_event_to_state(event: Dictionary) -> FrontendActorRenderState:
	var actor: Dictionary = event.get("actor", {}) as Dictionary
	var state := FrontendActorRenderState.new()
	state.id = actor.get("id", event.get("actorId", "")) as String
	state.type = actor.get("type", "Character") as String
	state.config_id = actor.get("configId", "") as String
	state.display_name = actor.get("displayName", state.config_id) as String
	state.team = int(actor.get("team", 0))
	var attributes: Dictionary = actor.get("attributes", {}) as Dictionary
	state.max_hp = float(attributes.get("max_hp", 100.0))
	state.visual_hp = float(attributes.get("hp", state.max_hp))
	state.target_hp = state.visual_hp
	state.is_alive = state.visual_hp > 0.0
	return state


func _get_or_create_replay_unit_view(actor_id: String, state: FrontendActorRenderState) -> FrontendUnitView:
	var existing_view: FrontendUnitView = _owned_replay_unit_views.get(actor_id, null)
	if existing_view != null and is_instance_valid(existing_view):
		return existing_view
	var view := FrontendUnitView.new()
	view.name = actor_id
	_replay_units_root.add_child(view)
	_owned_replay_unit_views[actor_id] = view
	return view


func _initialize_replay_unit_view(
	view: FrontendUnitView,
	actor_id: String,
	state: FrontendActorRenderState
) -> void:
	view.initialize(
		actor_id,
		state.display_name,
		state.team,
		state.max_hp,
		state.visual_hp,
		state.type,
		state.facing_direction
	)
	if state.type == "Environment":
		var environment_kind := state.config_id if not state.config_id.is_empty() else state.display_name
		view.set_environment_style(environment_kind)


func _on_actor_state_changed(actor_id: String, state: FrontendActorRenderState) -> void:
	if not _unit_views.has(actor_id):
		return
	var view: FrontendUnitView = _unit_views[actor_id]
	if not is_instance_valid(view):
		return
	view.update_state(state)
	view.set_world_position(_director.get_actor_world_position(actor_id))


## actor_died 是 transition-only event(RenderWorld 在 alive 真翻 false 那帧 emit
## 一次)。view 自己负责 once 语义,这里不做幂等。
func _on_actor_died(actor_id: String) -> void:
	if not _unit_views.has(actor_id):
		return
	var view: FrontendUnitView = _unit_views[actor_id]
	if is_instance_valid(view):
		view.play_death()


func _on_playback_ended() -> void:
	playback_ended.emit()


# ========== VFX / 投射物 / 飘字（自有节点） ==========

func _on_floating_text_created(data: FrontendRenderData.FloatingText) -> void:
	var start_usec := Time.get_ticks_usec()
	var floating_text := FrontendFloatingTextView.new()
	_effects_root.add_child(floating_text)
	floating_text.initialize(data.text, data.color, data.position, data.style, data.duration)
	var cost_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	if cost_ms >= FLOATING_TEXT_COST_WARN_MS:
		print("[Frontend:FrameDiag] floating_text text='%s' pos=%s duration=%.2f cost_ms=%.2f" % [
			data.text,
			data.position,
			data.duration,
			cost_ms,
		])


func _on_attack_vfx_created(data: FrontendRenderData.AttackVfx) -> void:
	if data.id.is_empty():
		return
	var vfx_view := FrontendAttackVFXView.new()
	vfx_view.name = "AttackVFX_" + data.id
	_effects_root.add_child(vfx_view)
	_attack_vfx_views[data.id] = vfx_view
	vfx_view.global_position = data.source_position
	vfx_view.initialize(data.id, data.vfx_type, data.vfx_color, data.direction, data.distance, data.is_critical)


func _on_attack_vfx_updated(vfx_id: String, progress: float, scale_factor: float, alpha: float) -> void:
	var vfx_view: FrontendAttackVFXView = _attack_vfx_views.get(vfx_id, null)
	if vfx_view != null:
		vfx_view.update_progress(progress, scale_factor, alpha)


func _on_attack_vfx_removed(vfx_id: String) -> void:
	var vfx_view: FrontendAttackVFXView = _attack_vfx_views.get(vfx_id, null)
	if vfx_view != null:
		vfx_view.cleanup()
		_attack_vfx_views.erase(vfx_id)


func _on_projectile_created(data: FrontendRenderData.Projectile) -> void:
	if data.id.is_empty():
		return
	var projectile_view := FrontendProjectileView.new()
	projectile_view.name = "Projectile_" + data.id
	_effects_root.add_child(projectile_view)
	_projectile_views[data.id] = projectile_view
	projectile_view.global_position = data.start_position
	projectile_view.initialize(data.id, data.projectile_type, data.projectile_color, data.projectile_size, data.direction)


func _on_projectile_updated(projectile_id: String, pos: Vector3, dir: Vector3) -> void:
	var projectile_view: FrontendProjectileView = _projectile_views.get(projectile_id, null)
	if projectile_view != null:
		projectile_view.update_position(pos)
		projectile_view.set_direction(dir)


func _on_projectile_removed(projectile_id: String) -> void:
	var projectile_view: FrontendProjectileView = _projectile_views.get(projectile_id, null)
	if projectile_view != null:
		projectile_view.cleanup()
		_projectile_views.erase(projectile_id)


func _on_cone_debug_overlay_created(data: FrontendRenderData.ConeDebugOverlay) -> void:
	var overlay_view := FrontendConeDebugOverlayView.new()
	overlay_view.name = "ConeDebugOverlay_" + data.id
	_effects_root.add_child(overlay_view)
	overlay_view.initialize(data)


func _filter_initial_base_unit_views(record: PlaybackData.BattleRecord, unit_views: Dictionary) -> Dictionary:
	_excluded_base_unit_views.clear()
	var initial_actor_ids := {}
	for actor_init: PlaybackData.ActorInitData in record.initial_actors:
		if not actor_init.id.is_empty():
			initial_actor_ids[actor_init.id] = true

	if initial_actor_ids.is_empty():
		return unit_views.duplicate()

	var result := {}
	for actor_id_variant in unit_views.keys():
		var actor_id := str(actor_id_variant)
		var view: FrontendUnitView = unit_views[actor_id]
		if not is_instance_valid(view):
			continue
		if initial_actor_ids.has(actor_id):
			result[actor_id] = view
		else:
			view.visible = false
			_excluded_base_unit_views[actor_id] = view
	return result


func _hide_excluded_base_unit_views() -> void:
	for actor_id: String in _excluded_base_unit_views.keys():
		var view: FrontendUnitView = _excluded_base_unit_views[actor_id]
		if is_instance_valid(view):
			view.visible = false


func _clear_effects() -> void:
	for child in _effects_root.get_children():
		child.queue_free()
	_attack_vfx_views.clear()
	_projectile_views.clear()


func _clear_replay_unit_views() -> void:
	for actor_id: String in _owned_replay_unit_views.keys():
		var view: FrontendUnitView = _owned_replay_unit_views[actor_id]
		if is_instance_valid(view):
			view.queue_free()
		_unit_views.erase(actor_id)
	_owned_replay_unit_views.clear()


func _deactivate_replay_unit_views() -> void:
	for actor_id: String in _owned_replay_unit_views.keys():
		var view: FrontendUnitView = _owned_replay_unit_views[actor_id]
		if is_instance_valid(view):
			view.revive()
			view.visible = false
		_unit_views.erase(actor_id)
