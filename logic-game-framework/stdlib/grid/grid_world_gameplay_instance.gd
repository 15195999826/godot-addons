## GridWorldGameplayInstance - 带 hex 棋盘的世界 Instance（stdlib 电池）
##
## core 的 WorldGameplayInstance 不认识棋盘；需要 ultra-grid-map 棋盘（占用 / 预订 / 寻路）的世界继承本类，
## 不需要的（如 dota2）直接继承 WorldGameplayInstance。棋盘归 instance 持有（instance → grid 向下强边）；
## GridMapModel 的 occupant 表存的是 actor 引用，与 registry 同向，所以 actor 离开 registry 必须同时
## 离开棋盘（remove_actor 里保证），否则棋盘持尸体到 instance 结束。死亡但留在 world 的 actor 由项目层
## 调 clear_grid_footprint 只清棋盘。
##
## Signal 只由显式 mutation API 触发、服务非战斗期的前端 view 同步（战斗期视觉由 BattleAnimator 消费录像）。
## actor_position_changed 由项目层在移动 actor 时 emit；grid_cell_changed 留给地形变化。
class_name GridWorldGameplayInstance
extends WorldGameplayInstance


# ========== Signal ==========

signal actor_position_changed(actor_id: String, old_coord: HexCoord, new_coord: HexCoord)
signal grid_configured(config: GridMapConfig)
signal grid_cell_changed(coord: HexCoord, change_type: String)


# ========== 字段 ==========

var grid: GridMapModel = null


# ========== 棋盘配置 ==========

## 用配置建一张新棋盘。子类可覆盖以接入数据驱动的棋盘来源，
## 最终仍须经 configure_grid_model 落到 grid 字段——棋盘只归 world 持有，没有全局槽位。
func configure_grid(config: GridMapConfig) -> void:
	var model := GridMapModel.new()
	model.initialize(config)
	configure_grid_model(model)


## 采用一张已建好的棋盘（数据驱动地图的产物）。grid_configured 只从这里发出。
func configure_grid_model(model: GridMapModel) -> void:
	Log.assert_crash(model != null, "GridWorldGameplayInstance", "configure_grid_model: model is null")
	grid = model
	grid_configured.emit(model.get_config())


## 录像快照的地图配置 = 当前棋盘的 config dict；未配图为 {}。
func _get_map_config() -> Dictionary:
	if grid == null:
		return {}
	return grid.to_config_dict()


# ========== 占用清理 ==========

## 清掉 actor 在棋盘上的占用与全部预订；不动 registry、不动 actor 的坐标。
## 死亡留尸体与 remove_actor 共用：占用只在该格 occupant 就是这个 actor 时才清——叠在别人格上的
## overlay actor（如火焰地形）不得清掉同格别人的占用；预订按 actor id 扫全图。
## 不用 GridMapModel.find_occupant_position：它对 Variant 做 ==，occupant 是 String（如主世界 NPC id）
## 时与 Object 比较会报 Invalid operands。
func clear_grid_footprint(actor: Actor) -> void:
	if grid == null or actor == null:
		return
	var position := IGridOccupant.get_grid_position(actor)
	if position.is_valid():
		var occupant: Variant = grid.get_occupant(position)
		if occupant is Object and occupant == actor:
			grid.remove_occupant(position)
	var actor_id := actor.get_id()
	for coord in grid.get_all_coords():
		if grid.get_reservation(coord) == actor_id:
			grid.cancel_reservation(coord)


# ========== Actor registry ==========

## 离开 registry 的 actor 同时离开棋盘。
func remove_actor(actor_id: String) -> bool:
	clear_grid_footprint(super.get_actor(actor_id))
	return super.remove_actor(actor_id)
