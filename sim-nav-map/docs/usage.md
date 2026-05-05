# Sim Nav Map Usage

This is the minimal integration path for a game or example that consumes
`sim-nav-map`.

For the conceptual boundary, read [`mental-model.md`](mental-model.md). For the
supported class boundary, read [`public-api.md`](public-api.md).

## 1. Create The Map

```gdscript
var nav_map := SimNavMap.new(width, height, cell_size, origin, navcells_per_tile)
```

`SimNavMap` owns navcell geometry, passability classes, static obstructions,
dynamic obstructions, and dirty tracking. It does not own game units.

## 2. Register Passability

```gdscript
const TERRAIN_WATER := 1
const TERRAIN_CLIFF := 2

var ground := SimNavPassabilityClassConfig.new()
ground.class_name_id = "ground"
ground.clearance = unit_radius
ground.affects_pathfinding = true
ground.terrain_mask = TERRAIN_WATER | TERRAIN_CLIFF
var ground_mask := nav_map.register_passability_class(ground)
```

Keep passability names project-owned. The addon only assigns masks and evaluates
map/path queries against those masks.
`terrain_mask` is a project-owned bitmask over terrain tile data: if a terrain
tile contains any bit from a class's `terrain_mask`, the covered navcells are
blocked for that class.

## 3. Project Terrain Data

```gdscript
nav_map.set_terrain_tile_data(Vector2i(3, 2), TERRAIN_WATER)
```

Use `SimNavMap.set_terrain_tile_data()` for edits that should affect path
queries. It stores the raw terrain tile value, derives navcell passability for
registered classes, and marks changed navcells dirty. If a map tool edits
`nav_map.get_terrain_tile_map()` directly, call
`nav_map.rebuild_terrain_passability()` before rebuilding reachability or
querying paths.

Terrain remains navigation input, not gameplay. The addon does not define land,
water, ship behavior, terrain art, or movement rules.

## 4. Project Entities Into Shapes

Static obstacles:

```gdscript
var shape := SimNavObstructionShapeStatic.new()
shape.entity_id = building.id
shape.center = building.position
shape.width = building.size.x
shape.height = building.size.y
shape.flags = SimNavObstructionFlags.BLOCK_PATHFINDING
var tag := nav_map.add_static_obstruction(shape)
nav_map.rebuild_dirty()
```

Dynamic unit blockers:

```gdscript
var unit_shape := SimNavObstructionShapeUnit.new()
unit_shape.entity_id = unit.id
unit_shape.center = unit.position
unit_shape.clearance = unit.radius
unit_shape.flags = SimNavObstructionFlags.BLOCK_MOVEMENT
unit_shape.control_group = unit.group_id
nav_map.replace_dynamic_obstructions([unit_shape])
```

Do not subclass `SimNavObstructionShape*` for real game entities. Treat shapes as
projection DTOs created by an adapter.

## 5. Query A Long Path

```gdscript
var hierarchical := SimNavHierarchicalPathfinder.new()
hierarchical.recompute(nav_map, [ground_mask])

var long_pathfinder := SimNavLongPathfinder.new(nav_map)
var facade := SimNavPathfinderFacade.new(nav_map, hierarchical, long_pathfinder)
var path := facade.compute_path_immediate(
	unit.position,
	SimNavPathGoal.point(target_position),
	ground_mask
)
```

`SimNavPathfinderFacade` canonicalizes unreachable goals to a reachable navcell
before long-path search. For `POINT` goals, it may rewrite the supplied
`SimNavPathGoal` object to that reachable navcell. Clone the goal first, or use
`SimNavPathRequestQueue`, if the original command target must remain unchanged.
If your game wants different fallback behavior, keep that policy in the adapter.

## 6. Query A Short Path

```gdscript
var request := SimNavShortPathRequest.new()
request.start = unit.position
request.goal = SimNavPathGoal.point(target_position)
request.clearance = unit.radius
request.range_px = 192.0
request.pass_mask = ground_mask
request.avoid_moving_units = true
request.control_group = unit.group_id

var vertex_pathfinder := SimNavVertexPathfinder.new(nav_map)
var path := vertex_pathfinder.compute_short_path_immediate(request)
```

Short-path query policy, such as control-group filtering and moving-unit
avoidance, is request data supplied by the caller.

## 7. Queue Requests

Use `SimNavPathRequestQueue` when a caller wants to process long/short path
requests through a small frame budget or worker batch:

```gdscript
var queue := SimNavPathRequestQueue.new(facade, vertex_pathfinder)
var ticket := queue.enqueue_long_path(unit.position, SimNavPathGoal.point(target_position), ground_mask)
queue.process_budget(1)
var path := queue.take_result(ticket)
```

The queue clones the submitted `SimNavPathGoal` / `SimNavShortPathRequest` at
enqueue time. Later mutations to the caller-owned goal/request do not change the
queued work item.

## 8. Consume The Result

`SimNavWaypointPath` is a plan, not movement execution. The caller decides:

- waypoint consumption order
- speed, acceleration, turning, and stopping
- retry/replan cadence
- stuck handling
- push/yield or crowd policy
- formation or target-slot assignment

The addon deliberately does not implement those application policies.

## Stable Regression Commands

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```
