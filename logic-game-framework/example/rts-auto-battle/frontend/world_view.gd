## RtsWorldView - RTS 响应式世界视图 (P2.7)
##
## 职责: 监听 world.actor_added / actor_removed signal, 维护 unit / building visualizer 的
## 生命周期; 不直接读 actor 字段做位置同步 — 那是 RtsBattleDirector 的职责.
##
## 与 hex frontend FrontendWorldView 区别:
##   - hex 用 HexCoord; 这里用 Vector2 连续坐标
##   - hex 战斗期间靠 BattleAnimator 消费 event_timeline 离线回放; 这里 Director 实时 sim,
##     position 通过 actor_render_state_updated signal 推 push 给 visualizer
##   - hex Director 不跑 tick (离线); 这里 Director 每 _process tick 推 procedure 跑战斗
##
## 创建顺序:
##   demo_rts_frontend (或 smoke):
##     1. world = create world
##     2. battle_map (含 grid) 创建
##     3. director = new RtsBattleDirector + add_child
##     4. world_view = new RtsWorldView + add_child
##     5. world_view.bind(world, director)        — 监听 actor_added/removed; hydrate 已存在 actor
##     6. world.start_rts_battle(...) → procedure
##     7. director.attach(world, procedure)       — director 接管 event_sink + 起手 _seed_render_state
##     8. (director._process 自动跑 tick)
##
## 关键不变量:
##   - WorldView 不读 actor.position_2d / actor.attribute_set (创建期 hydrate 必要字段除外)
##   - 战斗期间 visualizer 通过 director signal 拿渲染状态, 不读 actor
##   - actor_removed (world.remove_actor 触发) 时清掉 visualizer; 死亡但仍在 world 的 actor 由
##     visualizer 自己改色 (actor_died signal); 真正 queue_free 由 actor_removed 决定
class_name RtsWorldView
extends Node2D


# ========== 字段 ==========

var _world_ref: WeakRef = null
var _director: RtsBattleDirector = null

## actor_id → RtsUnitVisualizer / RtsBuildingVisualizer (Node2D, add_child 到 self)
var _visualizers: Dictionary = {}


# ========== 生命周期 ==========

func _exit_tree() -> void:
	unbind()


# ========== 公共 API ==========

## 把 view 接到 world + director.
##
## 调用时机: world 已存在但未必有 actor (hydrate 阶段会 spawn 已存在的 view); director 已 add_child
## 但 attach() 通常在此调用之后 (因为 procedure 还没创建).
##
## 后续 actor_added (战斗中 spawn / PlaceBuildingCommand 新建建筑) 会自动触发 visualizer 创建.
func bind(world: RtsWorldGameplayInstance, director: RtsBattleDirector) -> void:
	Log.assert_crash(world != null, "RtsWorldView", "bind: world is null")
	Log.assert_crash(director != null, "RtsWorldView", "bind: director is null")
	unbind()
	_world_ref = weakref(world)
	_director = director

	# 监听 world 的 actor lifecycle
	world.actor_added.connect(_on_actor_added)
	world.actor_removed.connect(_on_actor_removed)

	# 监听 director 的渲染状态推送 + 死亡事件
	director.actor_render_state_updated.connect(_on_actor_render_state_updated)
	director.actor_died.connect(_on_actor_died)

	# Hydrate 已存在的 actor (起手 4v4 / 起手建筑等)
	for actor in world.get_actors():
		if actor != null:
			_spawn_visualizer(actor.get_id())


## 解绑 + queue_free 所有 visualizer. _exit_tree / scene 切换时调用.
func unbind() -> void:
	var world := _get_world()
	if world != null:
		if world.actor_added.is_connected(_on_actor_added):
			world.actor_added.disconnect(_on_actor_added)
		if world.actor_removed.is_connected(_on_actor_removed):
			world.actor_removed.disconnect(_on_actor_removed)
	if _director != null:
		if _director.actor_render_state_updated.is_connected(_on_actor_render_state_updated):
			_director.actor_render_state_updated.disconnect(_on_actor_render_state_updated)
		if _director.actor_died.is_connected(_on_actor_died):
			_director.actor_died.disconnect(_on_actor_died)
	for vis in _visualizers.values():
		if is_instance_valid(vis):
			(vis as Node).queue_free()
	_visualizers.clear()
	_world_ref = null
	_director = null


# ========== 查询 ==========

func get_visualizer(actor_id: String) -> Node:
	return _visualizers.get(actor_id, null) as Node


func get_visualizer_count() -> int:
	return _visualizers.size()


# ========== Signal handlers ==========

func _on_actor_added(actor_id: String) -> void:
	_spawn_visualizer(actor_id)


func _on_actor_removed(actor_id: String) -> void:
	if not _visualizers.has(actor_id):
		return
	var vis := _visualizers[actor_id] as Node
	if is_instance_valid(vis):
		vis.queue_free()
	_visualizers.erase(actor_id)


## director.actor_render_state_updated 路由到对应 visualizer.
##
## visualizer 不持 actor 引用, 只持 actor_id; 通过此 signal 收到 (prev_pos, curr_pos, hp, ...)
## 后内部更新 + queue_redraw / 触发文本变化.
func _on_actor_render_state_updated(
	actor_id: String,
	prev_pos: Vector2,
	curr_pos: Vector2,
	hp: float,
	max_hp: float,
	is_dead: bool,
) -> void:
	var vis := _visualizers.get(actor_id, null)
	if vis == null:
		return
	# Visualizer 自己实现 update_render_state(prev_pos, curr_pos, hp, max_hp, is_dead).
	if vis.has_method("update_render_state"):
		vis.update_render_state(prev_pos, curr_pos, hp, max_hp, is_dead)


func _on_actor_died(actor_id: String) -> void:
	var vis := _visualizers.get(actor_id, null)
	if vis == null:
		return
	if vis.has_method("on_died"):
		vis.on_died()


# ========== 内部: visualizer 创建 ==========

## 按 actor 类型创建对应 visualizer.
##
## 创建期 hydrate (一次性读 actor 类型 + 创建期元数据 — team_id / footprint_size / unit_class):
## 这是合规的 — actor 创建期一次性读;  战斗期间 visualizer 不再读 actor.
func _spawn_visualizer(actor_id: String) -> void:
	if _visualizers.has(actor_id):
		return
	var world := _get_world()
	if world == null or _director == null:
		return
	var actor := world.get_actor(actor_id)
	if actor == null:
		return

	# Unit
	if actor is RtsUnitActor:
		var unit_actor := actor as RtsUnitActor
		var unit_vis := RtsUnitVisualizer.new()
		add_child(unit_vis)
		# P2.8: 一次性 hydrate render_height (AIR 单位画在 8px 上空); 创建期读 actor 是允许的,
		# render_height 是 layer 派生静态量, 战斗期间不变, 不需要每帧推 push (与 team_id / footprint 同级).
		unit_vis.bind(actor_id, unit_actor.get_team_id(), _director, unit_actor.get_render_height())
		_visualizers[actor_id] = unit_vis
		return

	# Building
	if actor is RtsBuildingActor:
		var bld_actor := actor as RtsBuildingActor
		var bld_vis := RtsBuildingVisualizer.new()
		add_child(bld_vis)
		bld_vis.bind(
			actor_id,
			bld_actor.get_team_id(),
			bld_actor.footprint_size,
			bld_actor.is_crystal_tower,
			_director,
		)
		_visualizers[actor_id] = bld_vis
		return

	# 其它类型 (RtsBattleActor 子类没覆盖到的) — 不创建 view
	# (Phase 2 P2.8 飞行单位作为 RtsUnitActor 子集仍走 unit visualizer; 不需要新分支)


# ========== 工具 ==========

func _get_world() -> RtsWorldGameplayInstance:
	if _world_ref == null:
		return null
	return _world_ref.get_ref() as RtsWorldGameplayInstance
