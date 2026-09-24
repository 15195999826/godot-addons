## HexProjection - hex 逻辑平面（axial 浮点 Vector2）到 3D 世界坐标的换算，view 层的唯一入口。
##
## 表演核心（context / 卡片 / 账本 / 信号 payload）只讲 axial；像素 / 3D 只在 view 层出现。
## hex→pixel 是线性映射，浮点 axial 取所在格 (q0, r0) 与 q / r 方向各一步的像素做线性组合即精确
## （整数格退化为 coord_to_pixel，与棋盘渲染逐位一致）。没有棋盘（录像无 map_config / 测试裸建 view）
## 时退化成恒等映射 (q, 0, r)，与 FrontendWorldView.hex_to_world 的无棋盘分支一致。
class_name FrontendHexProjection


## axial 浮点坐标 → 世界坐标（XZ 平面，Y = 0）
static func to_world(layout: GridLayout, axial: Vector2) -> Vector3:
	if layout == null:
		return Vector3(axial.x, 0.0, axial.y)
	var q0 := floori(axial.x)
	var r0 := floori(axial.y)
	var p00 := layout.coord_to_pixel(Vector2i(q0, r0))
	var p10 := layout.coord_to_pixel(Vector2i(q0 + 1, r0))
	var p01 := layout.coord_to_pixel(Vector2i(q0, r0 + 1))
	var pixel := p00 + (p10 - p00) * (axial.x - q0) + (p01 - p00) * (axial.y - r0)
	return Vector3(pixel.x, 0.0, pixel.y)


## axial 位移（不含平移）→ 世界位移；bump 偏移这类叠在位置上的向量用这个
static func delta_to_world(layout: GridLayout, delta: Vector2) -> Vector3:
	return to_world(layout, delta) - to_world(layout, Vector2.ZERO)
