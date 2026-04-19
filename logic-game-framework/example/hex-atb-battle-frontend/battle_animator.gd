## BattleAnimator - 战斗动画播放器（叠加层）
##
## 消费 BattleProcedure.finish() 产出的 event_timeline（兼容现阶段 v2
## 录像格式 dict），在 WorldView 提供的已有 unit view 上叠加飘字 / 特效 /
## 死亡动画。不拥有 unit view 生命周期 —— 战斗结束时 WorldGI 里 actor 已是
## 终态，animator 只负责让视觉追上该终态。
##
## 实现上是 FrontendBattleDirector 的薄包装：复用 timeline 解码 /
## ActionScheduler / visualizer registry，把 director 发出的状态变更信号
## 转发到外部传入的 unit view 字典，并自己承载 VFX / 投射物 / 飘字节点。
##
## 详见 docs/design-notes/2026-04-20-world-view.md
class_name FrontendBattleAnimator
extends Node3D


# ========== 信号 ==========

signal playback_started
signal playback_ended


# ========== 内部组件 ==========

var _director: FrontendBattleDirector
var _effects_root: Node3D

var _unit_views: Dictionary = {}            # actor_id -> FrontendUnitView
var _attack_vfx_views: Dictionary = {}      # vfx_id -> FrontendAttackVFXView
var _projectile_views: Dictionary = {}      # projectile_id -> FrontendProjectileView


# ========== 生命周期 ==========

func _ready() -> void:
	_effects_root = Node3D.new()
	_effects_root.name = "EffectsRoot"
	add_child(_effects_root)

	_director = FrontendBattleDirector.new()
	_director.name = "BattleDirector"
	add_child(_director)

	_director.actor_state_changed.connect(_on_actor_state_changed)
	_director.floating_text_created.connect(_on_floating_text_created)
	_director.attack_vfx_created.connect(_on_attack_vfx_created)
	_director.attack_vfx_updated.connect(_on_attack_vfx_updated)
	_director.attack_vfx_removed.connect(_on_attack_vfx_removed)
	_director.projectile_created.connect(_on_projectile_created)
	_director.projectile_updated.connect(_on_projectile_updated)
	_director.projectile_removed.connect(_on_projectile_removed)
	_director.playback_ended.connect(_on_playback_ended)


func _process(_delta: float) -> void:
	if _director == null or not _director.is_playing():
		return
	# 移动动画期间单位位置平滑更新 —— 沿袭 FrontendBattleReplayScene 对 Director
	# 提供的 get_actor_world_position 的拉取模式。
	for actor_id in _unit_views:
		var view: FrontendUnitView = _unit_views[actor_id]
		if is_instance_valid(view):
			view.set_world_position(_director.get_actor_world_position(actor_id))


# ========== 公共 API ==========

## 播放战斗动画。
## record_data: BattleProcedure.finish() 返回的 dict（当前 v2 格式，含 initial_actors / map_config）。
## unit_views: actor_id -> FrontendUnitView 字典，由 WorldView 管理生命周期。
## 可调 set_speed() 加速；playback_ended signal 在所有动画排空时触发。
func play(record_data: Dictionary, unit_views: Dictionary) -> void:
	_unit_views = unit_views
	_clear_effects()

	var record := ReplayData.BattleRecord.from_dict(record_data)
	_director.load_replay(record)
	_director.play()
	playback_started.emit()


func stop() -> void:
	if _director != null:
		_director.pause()


func set_speed(speed: float) -> void:
	if _director != null:
		_director.set_speed(speed)


func is_playing() -> bool:
	return _director != null and _director.is_playing()


# ========== Director signal → 外部 unit view ==========

func _on_actor_state_changed(actor_id: String, state: FrontendActorRenderState) -> void:
	if not _unit_views.has(actor_id):
		return
	var view: FrontendUnitView = _unit_views[actor_id]
	if not is_instance_valid(view):
		return
	view.update_state(state)
	view.set_world_position(_director.get_actor_world_position(actor_id))


func _on_playback_ended() -> void:
	playback_ended.emit()


# ========== VFX / 投射物 / 飘字（自有节点） ==========

func _on_floating_text_created(data: FrontendRenderData.FloatingText) -> void:
	var floating_text := FrontendFloatingTextView.new()
	_effects_root.add_child(floating_text)
	floating_text.initialize(data.text, data.color, data.position, data.style, data.duration)


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


func _clear_effects() -> void:
	for child in _effects_root.get_children():
		child.queue_free()
	_attack_vfx_views.clear()
	_projectile_views.clear()
