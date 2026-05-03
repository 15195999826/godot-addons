## RtsObstructionShapeStatic - OBB (Oriented Bounding Box) 子类 (M0 引入)
##
## 表示一个矩形 obstruction (建筑 / 静态障碍物)。0 A.D. 的 `StaticShape` / `ObstructionSquare` 复刻。
##
## **OBB 几何**:
##   - center (基类): Vector2 (世界坐标)
##   - width:  float (沿 u 轴的全宽)
##   - height: float (沿 v 轴的全高)
##   - rotation_rad: float (弧度; 0 = u 轴沿 +x, v 轴沿 +y)
##
## **关键转换** (字段对照 0 A.D.):
##   - 0 A.D. `StaticShape::m_Hw / m_Hh` 是**半宽半高**,我们 width / height 是**全宽全高**
##   - rasterize / SAT 几何计算时若需"半宽" 用 `width * 0.5` (data-structures §10 字段对照表)
##
## **M0 范围**: 字段 + get_corners / get_axes helper。不挂寻路 / 注册逻辑。
##
## **0 A.D. 对照**:
##   - `ICmpObstructionManager.h:55` ObstructionSquare
##   - `CCmpObstructionManager.cpp` StaticShape
##
## **决策来源**:
##   - data-structures.md §2.1 (子类 RtsObstructionShapeStatic)
##   - milestones/M0-footprint-split.md §M0.2 步骤 2
class_name RtsObstructionShapeStatic
extends RtsObstructionShape


# ========== OBB 几何字段 ==========

## OBB 沿 u 轴 (rotation_rad = 0 时 = +x 方向) 的**全宽** (px)。
var width: float = 0.0

## OBB 沿 v 轴 (rotation_rad = 0 时 = +y 方向) 的**全高** (px)。
var height: float = 0.0

## OBB 旋转 (弧度); 0 = u 轴沿 +x, v 轴沿 +y。
##
## **M0 现状**: 所有建筑 rotation_rad = 0 (无旋转支持); M2 起 RtsObstructionManager 注册旋转。
var rotation_rad: float = 0.0


# ========== 初始化 ==========

func _init() -> void:
	type = Type.STATIC


# ========== Helper ==========

## 返回 OBB 4 个角点的世界坐标。
##
## **顺序**: (+u +v), (+u -v), (-u -v), (-u +v) — 局部坐标系四象限固定顺序。
##           data-structures §12.3 要求 vertex 加入 graph 顺序 deterministic; 此顺序在 M6 起被
##           VertexPathfinder 依赖, M0 阶段不影响 baseline (无寻路调用), 但提前固定避免后续返工。
##
## **数学**: corner_k = center + sign_u(k) * (width / 2) * u_hat + sign_v(k) * (height / 2) * v_hat
##           其中 u_hat / v_hat 由 rotation_rad 推出。
func get_corners() -> Array[Vector2]:
	var u: Vector2 = Vector2(cos(rotation_rad), sin(rotation_rad))
	var v: Vector2 = Vector2(-sin(rotation_rad), cos(rotation_rad))
	var hw: float = width * 0.5
	var hh: float = height * 0.5
	var corners: Array[Vector2] = [
		center + u * hw + v * hh,
		center + u * hw - v * hh,
		center - u * hw - v * hh,
		center - u * hw + v * hh,
	]
	return corners


## 返回 OBB 局部坐标系的两条单位轴 (u, v)。
##
## - u: 局部 +x 轴 (rotation_rad = 0 时 = (1, 0))
## - v: 局部 +y 轴 (rotation_rad = 0 时 = (0, 1))
##
## 用于 SAT 碰撞测试 (M2 ObstructionManager.test_*_shape) 与 vertex pathfinder 候选生成 (M6)。
func get_axes() -> Array[Vector2]:
	var u: Vector2 = Vector2(cos(rotation_rad), sin(rotation_rad))
	var v: Vector2 = Vector2(-sin(rotation_rad), cos(rotation_rad))
	var axes: Array[Vector2] = [u, v]
	return axes
