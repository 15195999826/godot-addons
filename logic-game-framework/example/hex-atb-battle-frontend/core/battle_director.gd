## BattleDirector - 战斗回放核心调度器
##
## 整合 VisualizerRegistry、ActionScheduler、RenderWorld，
## 提供完整的战斗回放控制能力。
##
## 作为 Node 实现，负责：
## - _process(delta) 驱动 tick
## - 引用场景节点（UnitsRoot、EffectsRoot、CameraRig、UI）
## - 接收输入（play/pause）
class_name FrontendBattleDirector
extends Node


# ========== 信号 ==========

## 播放状态变化
signal playback_state_changed(is_playing: bool)

## 帧变化
signal frame_changed(current_frame: int, total_frames: int)

## 播放结束
signal playback_ended()

## 角色状态变化（转发自 RenderWorld）
signal actor_state_changed(actor_id: String, state: FrontendActorRenderState)

## 飘字创建（转发自 RenderWorld）
signal floating_text_created(data: FrontendRenderData.FloatingText)

## 角色死亡（转发自 RenderWorld）
signal actor_died(actor_id: String)

## 攻击特效创建（转发自 RenderWorld）
signal attack_vfx_created(data: FrontendRenderData.AttackVfx)

## 攻击特效更新（转发自 RenderWorld）
signal attack_vfx_updated(vfx_id: String, progress: float, scale_factor: float, alpha: float)

## 攻击特效移除（转发自 RenderWorld）
signal attack_vfx_removed(vfx_id: String)

## 投射物创建（转发自 RenderWorld）
signal projectile_created(data: FrontendRenderData.Projectile)

## 投射物更新（转发自 RenderWorld）
signal projectile_updated(projectile_id: String, position: Vector3, direction: Vector3)

## 投射物移除（转发自 RenderWorld）
signal projectile_removed(projectile_id: String)


# ========== 常量 ==========

## 逻辑帧间隔（毫秒）
const LOGIC_TICK_MS: float = 100.0


# ========== 导出属性 ==========

## 初始播放速度
@export var initial_speed: float = 1.0

## 是否自动播放
@export var auto_play: bool = false


# ========== 核心组件 ==========

## Visualizer 注册表
var _registry: FrontendVisualizerRegistry

## 动作调度器
var _scheduler: FrontendActionScheduler

## 渲染世界
var _world: FrontendRenderWorld


# ========== 状态 ==========

## 回放数据
var _replay_data: ReplayData.BattleRecord

## 帧数据 Map（frame -> events）
var _frame_data_map: Dictionary = {}

## 是否正在播放
var _is_playing: bool = false

## 当前播放速度
var _speed: float = 1.0

## 当前逻辑帧
var _current_frame: int = 0

## 总帧数
var _total_frames: int = 0

## 逻辑帧累积时间
var _logic_accumulator: float = 0.0


# ========== 生命周期 ==========

func _ready() -> void:
	_speed = initial_speed
	
	# 初始化核心组件
	_registry = FrontendDefaultRegistry.create()
	_scheduler = FrontendActionScheduler.new()
	_world = FrontendRenderWorld.new()
	
	# 连接 RenderWorld 信号
	_world.actor_state_changed.connect(_on_actor_state_changed)
	_world.floating_text_created.connect(_on_floating_text_created)
	_world.actor_died.connect(_on_actor_died)
	_world.attack_vfx_created.connect(_on_attack_vfx_created)
	_world.attack_vfx_updated.connect(_on_attack_vfx_updated)
	_world.attack_vfx_removed.connect(_on_attack_vfx_removed)
	_world.projectile_created.connect(_on_projectile_created)
	_world.projectile_updated.connect(_on_projectile_updated)
	_world.projectile_removed.connect(_on_projectile_removed)
	
	if auto_play and not _replay_data.is_empty():
		play()


func _exit_tree() -> void:
	# 断开 RenderWorld 信号连接
	if _world:
		_world.actor_state_changed.disconnect(_on_actor_state_changed)
		_world.floating_text_created.disconnect(_on_floating_text_created)
		_world.actor_died.disconnect(_on_actor_died)
		_world.attack_vfx_created.disconnect(_on_attack_vfx_created)
		_world.attack_vfx_updated.disconnect(_on_attack_vfx_updated)
		_world.attack_vfx_removed.disconnect(_on_attack_vfx_removed)
		_world.projectile_created.disconnect(_on_projectile_created)
		_world.projectile_updated.disconnect(_on_projectile_updated)
		_world.projectile_removed.disconnect(_on_projectile_removed)
	
	# 清空 RefCounted 引用，打破循环引用
	_world = null
	_scheduler = null
	_registry = null


func _process(delta: float) -> void:
	if not _is_playing:
		return
	
	# delta 是 Godot _process(delta) 传入的，单位是秒（比如 60fps 时 ≈ 0.0167 秒）。
	# 整个表演层内部的时间单位统一用毫秒（duration、delay、elapsed 全是 ms）。
	# 转为毫秒后再乘以播放速度。
	_tick(delta * 1000.0 * _speed)


# ========== 公共方法 ==========

## 加载回放数据
func load_replay(record: ReplayData.BattleRecord) -> void:
	_replay_data = record
	
	# 构建帧数据 Map
	_frame_data_map.clear()
	for frame_data: ReplayData.FrameData in record.timeline:
		_frame_data_map[frame_data.frame] = frame_data
	
	# 获取总帧数
	_total_frames = record.meta.total_frames
	
	# 初始化渲染世界
	_world.initialize_from_replay(record)
	
	# 分析事件覆盖情况（只在加载时打印一次）
	_analyze_event_coverage()
	
	# 重置状态
	_current_frame = 0
	_logic_accumulator = 0.0
	_scheduler.cancel_all()
	
	frame_changed.emit(_current_frame, _total_frames)


## 开始播放
func play() -> void:
	# 自动重置已结束的回放
	if _is_ended():
		reset()
	
	_is_playing = true
	playback_state_changed.emit(true)


## 暂停播放
func pause() -> void:
	_is_playing = false
	playback_state_changed.emit(false)


## 切换播放/暂停
func toggle() -> void:
	if _is_ended():
		return
	
	if _is_playing:
		pause()
	else:
		play()


## 重置到初始状态
func reset() -> void:
	# 停止播放
	_is_playing = false
	playback_state_changed.emit(false)
	
	# 重置调度器
	_scheduler.cancel_all()
	
	# 重置世界状态
	_world.reset_to(_replay_data)
	
	# 重置帧状态
	_current_frame = 0
	_logic_accumulator = 0.0
	
	frame_changed.emit(_current_frame, _total_frames)


## 设置播放速度
func set_speed(speed: float) -> void:
	_speed = speed


## 获取当前播放速度
func get_speed() -> float:
	return _speed


## 获取当前帧
func get_current_frame() -> int:
	return _current_frame


## 获取总帧数
func get_total_frames() -> int:
	return _total_frames


## 是否正在播放
func is_playing() -> bool:
	return _is_playing


## 是否已结束
func is_ended() -> bool:
	return _is_ended()


## 获取 Actor 状态快照（actor_id -> FrontendActorRenderState）
func get_actors_snapshot() -> Dictionary:
	return _world.get_actors_snapshot()


## 获取角色世界坐标
func get_actor_world_position(actor_id: String) -> Vector3:
	return _world.get_actor_world_position(actor_id)


## 获取震屏偏移
func get_screen_shake_offset() -> Vector2:
	return _world.get_screen_shake_offset()


# ========== 内部方法 ==========

## 每帧更新
func _tick(delta_ms: float) -> void:
	# 累积时间
	_logic_accumulator += delta_ms
	
	# 检查是否需要推进逻辑帧
	while _logic_accumulator >= LOGIC_TICK_MS:
		_logic_accumulator -= LOGIC_TICK_MS
		
		# 推进逻辑帧
		var next_frame := _current_frame + 1
		
		# 检查是否已到达最后一帧
		if next_frame > _total_frames:
			# 不要在这里停止播放，让动画继续播放
			break
		
		_current_frame = next_frame
		
		# 查找该帧的事件
		if _frame_data_map.has(next_frame):
			var frame_data: ReplayData.FrameData = _frame_data_map[next_frame]
			var events: Array[Dictionary] = frame_data.events
			
			if events.size() > 0:
				Log.debug("BattleDirector", "帧 %d: %d 个事件" % [next_frame, events.size()])
			
			# 翻译事件为动作
			var context := _world.as_context()
			for event: Dictionary in events:
				var actions := _registry.translate(event, context)
				_scheduler.enqueue(actions)
		
		frame_changed.emit(_current_frame, _total_frames)
	
	# 推进内部世界时间
	_world.advance_time(int(delta_ms))
	
	# 调度器 tick（即使逻辑帧结束，也要继续推进动画）
	var result := _scheduler.tick(delta_ms)
	
	# 应用动作到世界状态
	if result.has_changes:
		# 先应用活跃动作
		_world.apply_actions(result.active_actions)
		# 再应用本帧完成的动作（确保最终状态被应用）
		_world.apply_actions(result.completed_this_tick)
		_world.cleanup(_world.get_world_time())
	
	# 批量触发状态变化信号
	_world.flush_dirty_actors()
	
	# 检查是否所有动画都已完成
	# NOTE: 逻辑帧播完后不会立即结束，会继续 tick 动画调度器直到所有表演动作完成。
	# 因此无需额外填充帧数 —— _scheduler.get_action_count() == 0 确保所有动画播放完毕。
	if _current_frame >= _total_frames and _scheduler.get_action_count() == 0:
		_is_playing = false
		playback_state_changed.emit(false)
		playback_ended.emit()


## 检查是否已结束
func _is_ended() -> bool:
	return _current_frame >= _total_frames and _scheduler.get_action_count() == 0


## 分析事件覆盖情况
## 在表演开始时调用，打印一次事件类型与 Visualizer 匹配摘要
func _analyze_event_coverage() -> void:
	var all_event_kinds: Dictionary = {}  # kind -> count
	
	# 收集所有事件类型及其出现次数
	for frame_data: ReplayData.FrameData in _replay_data.timeline:
		for event: Dictionary in frame_data.events:
			var kind: String = event.get("kind", "unknown")
			all_event_kinds[kind] = all_event_kinds.get(kind, 0) + 1
	
	if all_event_kinds.is_empty():
		print("[Frontend:Director] 事件覆盖分析: 无事件")
		return
	
	# 分类：已覆盖 vs 未覆盖
	var covered: Array[String] = []
	var uncovered: Array[String] = []
	
	for kind: String in all_event_kinds.keys():
		var count: int = all_event_kinds[kind]
		var visualizers := _registry.get_visualizers_for(kind)
		
		if visualizers.size() > 0:
			covered.append("%s (%d) -> %s" % [kind, count, ", ".join(visualizers)])
		else:
			uncovered.append("%s (%d)" % [kind, count])
	
	# 打印摘要
	print("[Frontend:Director] 事件覆盖分析 (共 %d 种事件类型):" % all_event_kinds.size())
	
	if covered.size() > 0:
		print("  ✓ 已覆盖 (%d 种):" % covered.size())
		for item: String in covered:
			print("    - %s" % item)
	
	if uncovered.size() > 0:
		print("  ⚠ 未覆盖 (%d 种): %s" % [uncovered.size(), ", ".join(uncovered)])


# ========== 信号处理 ==========

func _on_actor_state_changed(actor_id: String, state: FrontendActorRenderState) -> void:
	actor_state_changed.emit(actor_id, state)


func _on_floating_text_created(data: FrontendRenderData.FloatingText) -> void:
	floating_text_created.emit(data)


func _on_actor_died(actor_id: String) -> void:
	actor_died.emit(actor_id)


func _on_attack_vfx_created(data: FrontendRenderData.AttackVfx) -> void:
	attack_vfx_created.emit(data)


func _on_attack_vfx_updated(vfx_id: String, progress: float, scale_factor: float, alpha: float) -> void:
	attack_vfx_updated.emit(vfx_id, progress, scale_factor, alpha)


func _on_attack_vfx_removed(vfx_id: String) -> void:
	attack_vfx_removed.emit(vfx_id)


func _on_projectile_created(data: FrontendRenderData.Projectile) -> void:
	projectile_created.emit(data)


func _on_projectile_updated(projectile_id: String, pos: Vector3, dir: Vector3) -> void:
	projectile_updated.emit(projectile_id, pos, dir)


func _on_projectile_removed(projectile_id: String) -> void:
	projectile_removed.emit(projectile_id)
