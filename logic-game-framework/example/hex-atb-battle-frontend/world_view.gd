## WorldView - 响应式世界视图（非战斗期 view lifecycle 同步）
##
## 订阅 WorldGameplayInstance 的 mutation signal 维护 unit view / grid renderer 的
## 生命周期。不订阅战斗期属性变化 —— 战斗期视觉由 BattleAnimator 消费
## event_timeline 回放，在已有 view 上叠加飘字 / 特效。
##
## 设计哲学：view 是 state 的 reactive projection，不存在 destructive 重建 API。
## 详见 docs/design-notes/2026-04-19-world-as-single-instance.md 与
## docs/design-notes/2026-04-20-world-view.md
class_name FrontendWorldView
extends Node3D


# ========== 节点引用 ==========

var _units_root: Node3D
var _grid_renderer: GridMapRenderer3D
var _unit_views: Dictionary = {}    # actor_id -> FrontendUnitView
var _world_ref: WeakRef = null


# ========== 生命周期 ==========

func _ready() -> void:
	_units_root = Node3D.new()
	_units_root.name = "UnitsRoot"
	add_child(_units_root)

	_grid_renderer = GridMapRenderer3D.new()
	_grid_renderer.name = "GridRenderer"
	_grid_renderer.grid_color = Color(0.4, 0.45, 0.5, 0.8)
	_grid_renderer.highlight_color = Color.YELLOW
	_grid_renderer.fill_color = Color(0.2, 0.6, 1.0, 0.2)
	add_child(_grid_renderer)


func _exit_tree() -> void:
	unbind_world()


# ========== 绑定 / 解绑 ==========

## 绑定到 world。hydrate 当前所有 actor + 订阅 mutation signal。
## 调用前 WorldView 必须已经 _ready（进入场景树）；否则内部节点未创建。
func bind_world(world: WorldGameplayInstance) -> void:
	if world == null:
		return
	unbind_world()
	_world_ref = weakref(world)

	if world.grid != null:
		_apply_grid_model(world.grid)

	for actor in world.get_actors():
		if actor != null:
			_spawn_unit_view(actor.get_id())

	world.actor_added.connect(_on_actor_added)
	world.actor_removed.connect(_on_actor_removed)
	world.actor_position_changed.connect(_on_actor_position_changed)
	world.grid_configured.connect(_on_grid_configured)
	world.grid_cell_changed.connect(_on_grid_cell_changed)


func unbind_world() -> void:
	var world := _get_world()
	if world != null:
		world.actor_added.disconnect(_on_actor_added)
		world.actor_removed.disconnect(_on_actor_removed)
		world.actor_position_changed.disconnect(_on_actor_position_changed)
		world.grid_configured.disconnect(_on_grid_configured)
		world.grid_cell_changed.disconnect(_on_grid_cell_changed)
	_world_ref = null

	for view in _unit_views.values():
		if is_instance_valid(view):
			view.queue_free()
	_unit_views.clear()


# ========== 查询 ==========

func get_unit_views() -> Dictionary:
	return _unit_views


func get_unit_view(actor_id: String) -> FrontendUnitView:
	return _unit_views.get(actor_id, null)


func get_unit_view_count() -> int:
	return _unit_views.size()


# ========== Signal handlers ==========

func _on_actor_added(actor_id: String) -> void:
	_spawn_unit_view(actor_id)


func _on_actor_removed(actor_id: String) -> void:
	if not _unit_views.has(actor_id):
		return
	var view: FrontendUnitView = _unit_views[actor_id]
	if is_instance_valid(view):
		view.queue_free()
	_unit_views.erase(actor_id)


func _on_actor_position_changed(actor_id: String, _old_coord: HexCoord, new_coord: HexCoord) -> void:
	if not _unit_views.has(actor_id):
		return
	var view: FrontendUnitView = _unit_views[actor_id]
	if is_instance_valid(view):
		view.set_world_position(_hex_to_world(new_coord))


func _on_grid_configured(_config: GridMapConfig) -> void:
	var world := _get_world()
	if world != null and world.grid != null:
		_apply_grid_model(world.grid)


## 地形破坏类技能的预留钩子；MVP 无实际地形变更，重渲染整幅网格即可。
func _on_grid_cell_changed(_coord: HexCoord, _change_type: String) -> void:
	if _grid_renderer != null:
		_grid_renderer.render_grid()


# ========== 内部：unit view ==========

## 创建 unit view 并从 world actor 当前属性 hydrate（pull 模式）。
## 未放置到网格的 actor（如未 place_occupant 前）位置为 Vector3.ZERO，
## 由后续 actor_position_changed signal 更新。
##
## 只为 CharacterActor 建 view —— ProjectileActor 等非可视单位（体型 / 飞行物）
## 由 BattleAnimator 消费 event_timeline 自行出场，不在 WorldView 生命周期里。
func _spawn_unit_view(actor_id: String) -> void:
	if _unit_views.has(actor_id):
		return
	var world := _get_world()
	if world == null:
		return
	var actor := world.get_actor(actor_id)
	if actor == null or not (actor is CharacterActor):
		return

	var view := FrontendUnitView.new()
	view.name = actor_id
	_units_root.add_child(view)   # 触发 _ready, 让内部 mesh / label 建好
	_unit_views[actor_id] = view

	_hydrate_from_actor(view, actor)


func _hydrate_from_actor(view: FrontendUnitView, actor: Actor) -> void:
	var team := 0
	if actor.has_method("get_team_id"):
		team = actor.call("get_team_id")

	var max_hp := 100.0
	var cur_hp := 100.0
	var hex_pos: HexCoord = null

	if actor is CharacterActor:
		var cchar := actor as CharacterActor
		if cchar.attribute_set != null:
			max_hp = cchar.attribute_set.max_hp
			cur_hp = cchar.attribute_set.hp
		hex_pos = cchar.hex_position

	view.initialize(actor.get_id(), actor.get_display_name(), team, max_hp, cur_hp)
	if hex_pos != null and hex_pos.is_valid():
		view.set_world_position(_hex_to_world(hex_pos))


# ========== 内部：grid ==========

func _apply_grid_model(model: GridMapModel) -> void:
	if _grid_renderer == null or model == null:
		return
	_grid_renderer.set_model(model)
	_grid_renderer.render_grid()


func _hex_to_world(coord: HexCoord) -> Vector3:
	if coord == null or not coord.is_valid():
		return Vector3.ZERO
	var world := _get_world()
	if world == null or world.grid == null:
		return Vector3(coord.q, 0.0, coord.r)
	var pixel: Vector2 = world.grid.coord_to_world(coord)
	return Vector3(pixel.x, 0.0, pixel.y)


func _get_world() -> WorldGameplayInstance:
	if _world_ref == null:
		return null
	return _world_ref.get_ref() as WorldGameplayInstance
