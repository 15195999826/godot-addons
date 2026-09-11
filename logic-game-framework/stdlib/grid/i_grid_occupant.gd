class_name IGridOccupant
## 协议：有 `hex_position: HexCoord` 字段的 actor 站在棋盘上。
##
## core 的 Actor 不认识坐标（棋盘是 stdlib 电池，core 零引用 HexCoord）；GridWorldGameplayInstance
## 经本类读 actor 的格子来清占用。没有该字段、字段为 null、坐标无效三者同一答案——HexCoord.invalid()，
## 占用清理对它们都是 no-op（预订仍按 actor id 扫全图）。


static func get_grid_position(actor: Actor) -> HexCoord:
	if actor == null or not ("hex_position" in actor):
		return HexCoord.invalid()
	var position := actor.get("hex_position") as HexCoord
	if position == null:
		return HexCoord.invalid()
	return position
