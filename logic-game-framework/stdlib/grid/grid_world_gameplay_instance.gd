## GridWorldGameplayInstance - 带棋盘的世界 Instance（stdlib 电池）
##
## core 的 WorldGameplayInstance 不认识棋盘；需要 ultra-grid-map 棋盘（占用 / 预订 / 寻路）的世界继承本类，
## 不需要的（如 dota2）直接继承 WorldGameplayInstance。棋盘归 instance 持有（instance → grid 向下强边）；
## GridMapModel 的 occupant 表存的是 actor 引用，与 registry 同向，所以 actor 离开 registry 必须同时
## 离开棋盘（remove_actor 里保证），否则棋盘持尸体到 instance 结束。死亡但留在 world 的 actor 由项目层
## 调 clear_grid_footprint 只清棋盘。
##
## 本类只管「世界持一张棋盘」：持板、出 registry 必出棋盘、录像地图钩子、三个观察 signal。
## 谁能走哪、怎么预订、开局怎么摆、死亡留不留尸体是项目层的事。actor 站在哪由棋盘记着（占用 / 预订两本反向索引），
## 本类不读 actor 身上任何坐标字段；坐标是 hex 还是四边形由 ultra-grid-map 决定。
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

## 清掉 actor 在棋盘上的占用与全部预订；不动 registry、不动 actor。
## 死亡留尸体与 remove_actor 共用。全部问棋盘的反向索引：占用按 actor 对象查——只清它自己站的那格，
## 叠在别人格上的 overlay actor（如火焰地形）从没 place_occupant，自然不清同格别人的占用；预订按 actor id 查。
## 没有足迹的 actor（投射物等载体）两次查找落空即返回：离场广播对谁都调，子系统自查是 O(1)。
func clear_grid_footprint(actor: Actor) -> void:
	if grid == null or actor == null:
		return
	grid.remove_occupant_of(actor)
	grid.cancel_reservations_by(actor.get_id())


# ========== Actor registry ==========

## 离开 registry 的 actor 同时离开棋盘。
func remove_actor(actor_id: String) -> bool:
	clear_grid_footprint(super.get_actor(actor_id))
	return super.remove_actor(actor_id)
