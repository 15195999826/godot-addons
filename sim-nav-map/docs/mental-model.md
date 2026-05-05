# Sim Nav Map 心智模型

`sim-nav-map` 是 simulation-side 的 RTS navigation addon。把它当成寻路基础设施层，而不是 game entity model 或移动系统。

## 一句话版本

```text
游戏里的单位 / 建筑
  -> 项目层 adapter
  -> SimNavObstructionShapeStatic / SimNavObstructionShapeUnit
  -> SimNavMap
  -> path query
  -> SimNavWaypointPath
  -> 项目层 movement code
```

游戏里的真实 entity 不需要，也不应该继承 `SimNavObstructionShapeStatic` 或 `SimNavObstructionShapeUnit`。

这两个类只是导航层的投影数据：它们描述“这个 entity 在寻路意义上如何阻挡路径”。

完整 public API 边界见 [`public-api.md`](public-api.md)，最小接入流程见
[`usage.md`](usage.md)。本文件只解释接入心智模型。

## 和 Ultra Grid Map 的区别

`ultra-grid-map` 的心智模型是 grid world model：

```text
GridMapModel
  -> standing actor at grid position
  -> find_path()
  -> 项目层消费 path
```

`sim-nav-map` 的心智模型是 continuous-world navigation model：

```text
SimNavMap
  -> static obstruction shapes
  -> dynamic unit obstruction shapes
  -> compute path / reachable goal
  -> 项目层消费 waypoints
```

关键差异：`sim-nav-map` 不拥有 Actor。它只拥有导航查询需要的 nav-map 数据和 obstruction shapes。

## Addon 自己负责什么

`sim-nav-map` 负责：

- navcell grid 的尺寸、origin，以及 world position 和 navcell 之间的转换
- passability class，例如 `"ground"`
- static obstruction shapes，例如建筑、墙、石头、地形 blocker
- dynamic obstruction shapes，通常是当前单位 blocker
- spatial index，用来查附近 obstruction
- dirty navcell tracking，用来处理静态地图变化
- hierarchical reachability，包括把不可达目标改成最近可达 navcell
- long-path 和 short-path pathfinder

它返回 `SimNavWaypointPath`。它不负责让单位沿路径移动。

当前推荐稳定入口是：

- `SimNavMap`
- `SimNavPassabilityClassConfig` / `SimNavPassabilityClassRegistry`
- `SimNavObstructionShapeStatic` / `SimNavObstructionShapeUnit`
- `SimNavPathGoal` / `SimNavWaypointPath`
- `SimNavHierarchicalPathfinder`
- `SimNavLongPathfinder`
- `SimNavVertexPathfinder`
- `SimNavPathfinderFacade`
- `SimNavPathRequestQueue`

## 项目层负责什么

真实游戏 / 示例层负责：

- unit / building 领域对象
- selection 和 move command
- movement integration、steering、turning、acceleration、stopping
- replan cadence 和每帧 pathfinding budget
- crowd policy：推挤、让路、优先级、同阵营过滤、死锁处理
- formation slot 和最终目标点分配
- rendering、debug drawing、HUD、editor tools

这些 policy 默认不进 addon。除非未来某个 sample 证明某块行为确实是可复用的 navigation infrastructure。

## Static 和 Dynamic Obstruction

static obstruction 用来表示不常移动的东西：

- building
- wall
- rock
- placed blocker
- terrain blocker

典型流程：

```gdscript
var nav_map := SimNavMap.new(width, height, cell_size, origin, 1)

var ground := SimNavPassabilityClassConfig.new()
ground.class_name_id = "ground"
ground.clearance = unit_radius
ground.affects_pathfinding = true
var pass_mask := nav_map.register_passability_class(ground)

var shape := SimNavObstructionShapeStatic.new()
shape.entity_id = building.id
shape.center = building.position
shape.width = building.size.x
shape.height = building.size.y
shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING

var tag := nav_map.add_static_obstruction(shape)
nav_map.rebuild_dirty()
```

如果建筑后续可能被拆除或移动，项目层应保存 `add_static_obstruction()` 返回的 `tag`。

dynamic obstruction 用来表示单位：

```gdscript
var shape := SimNavObstructionShapeUnit.new()
shape.entity_id = unit.id
shape.center = unit.position
shape.clearance = unit.radius
shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
shape.control_group = unit.group_id

nav_map.replace_dynamic_obstructions([shape])
```

dynamic unit shapes 通常在 path query 前根据当前单位状态重建。它们不是单位状态的 source of truth。

## Adapter Pattern

推荐集成方式是写一个 adapter，把项目里的对象转换成导航 shape：

```text
Building -> SimNavObstructionShapeStatic
Unit     -> SimNavObstructionShapeUnit
```

adapter 也是放项目侧 query policy 的地方：

- 这次 query 是否让同 `control_group` 的单位阻挡路径
- 是否避让正在移动的单位
- 用哪个 unit radius / clearance
- 是否先尝试 short path，再 fallback 到 long path
- 目标不可达时，是否 canonicalize 到最近可达 navcell
- path 失败时是否 retry、fallback、停止、或进入 stuck handling

`rts-pathfinding-lab` 里的 `RtsPathfindingLabPathfinder` 就是这个模型。

## 典型 Path Query

```gdscript
var hierarchical := SimNavHierarchicalPathfinder.new()
hierarchical.recompute(nav_map, [pass_mask])

var start := unit.position
var goal := SimNavPathGoal.point(target_position)

var short_request := SimNavShortPathRequest.new()
short_request.start = start
short_request.goal = goal
short_request.clearance = unit.radius
short_request.range_px = query_range
short_request.pass_mask = pass_mask
short_request.avoid_moving_units = true
short_request.control_group = unit.group_id

var vertex_pathfinder := SimNavVertexPathfinder.new(nav_map)
var path := vertex_pathfinder.compute_short_path_immediate(short_request)

if path.is_empty():
	var long_pathfinder := SimNavLongPathfinder.new(nav_map)
	var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
	path = facade.compute_path_immediate(start, goal, pass_mask)
```

返回的 `SimNavWaypointPath` 只是计划。单位怎么移动，什么时候重规划，路径是否平滑，最终都由项目层决定。

## 当前真实样例

`addons/sim-nav-map/examples/rts-pathfinding-lab` 是一个 playable usage sample，不是 reusable addon API 的一部分。

它添加了：

- `RtsPathfindingLabPathfinder`：把 lab object 转成 `sim-nav-map` shape 的 adapter
- `RtsPathfindingLabWorld`：simulation loop、replan queue、movement、overlap resolution、obstacle editing、metrics
- `RtsPathfindingLabUnit`：简单的 lab unit state
- `RtsPathfindingLabObstacle`：简单的 lab rectangle obstacle state
- `frontend/rts_pathfinding_lab.gd`：drawing、input、HUD、tool modes

这个 lab 可以用来验证行为，但里面的 movement / crowd policy 不应该被当成 addon API。

## 设计规则

不要让 game entity 继承 `SimNavObstructionShape*`。

边界保持成：

```text
真实 entity：项目层 domain object
obstruction shape：导航层 projection DTO
SimNavMap：导航查询数据结构
```
