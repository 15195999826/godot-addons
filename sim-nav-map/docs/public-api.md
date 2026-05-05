# Sim Nav Map Public API

This file defines the current public boundary for `addons/sim-nav-map`.

`sim-nav-map` owns navigation data structures and path queries. It does not own
game entities, movement integration, steering, pushing, formation, combat, UI, or
editor workflow.

## Audit Status

This document is audited against the current `class_name` set in:

```text
addons/sim-nav-map/{core,model,obstruction,pathfinding}/
```

Public API smoke coverage is registered in `simnav/smoke`, including
`smoke_sim_nav_public_api_contract.tscn` for constructor/defaults, map projection
entry points, dirty/cache lifecycle, long/short query boundaries, and queued
request cloning. Feature-specific coverage includes
`smoke_sim_nav_clearance_rasterization.tscn` for class-aware terrain/static
clearance rasterization, `smoke_sim_nav_dirty_lifecycle.tscn` for dirty
edit/cache lifecycle, and `smoke_sim_nav_reachability_query.tscn` for explicit
reachability and canonical goal metadata.

## Stable Entry Points

These classes are the supported integration surface for game/example adapters:

| Class | Responsibility |
|---|---|
| `SimNavMap` | Central map state: navcell geometry, terrain data, derived terrain passability, class-aware clearance raster data, obstruction data, dirty tracking, world/navcell conversion. |
| `SimNavPassabilityClassConfig` | Per-class passability configuration: name, clearance, terrain mask, and pathfinding participation. |
| `SimNavPassabilityClassRegistry` | Registers passability classes and assigns masks. Usually accessed through `SimNavMap`. |
| `SimNavTerrainTileMap` | Coarser terrain tile data used by `SimNavMap`. Usually accessed through `SimNavMap`. |
| `SimNavObstructionFlags` | Shared obstruction flags such as `BLOCK_PATHFINDING`, `BLOCK_MOVEMENT`, and `MOVING`. |
| `SimNavObstructionShape` | Base projection DTO returned by map/manager query APIs. Adapters normally instantiate `Static` or `Unit`, not this base class. |
| `SimNavObstructionShapeStatic` | Static oriented rectangle projection for buildings, walls, rocks, blockers, and terrain-like obstacles. |
| `SimNavObstructionShapeUnit` | Dynamic circular projection for units. This is not a unit model. |
| `SimNavPathGoal` | Path target geometry: point, circle, square, and inverted variants. |
| `SimNavReachabilityResult` | Result DTO for explicit reachability/canonical goal queries. |
| `SimNavWaypointPath` | Returned path container. Callers own movement along these waypoints. |
| `SimNavHierarchicalPathfinder` | Reachability and nearest reachable navcell canonicalization. |
| `SimNavLongPathfinder` | Long navcell path search. |
| `SimNavVertexPathfinder` | Local short path search around nearby obstructions. |
| `SimNavShortPathRequest` | Request DTO for short-path queries. |
| `SimNavPathfinderFacade` | Synchronous long-path facade with reachable-goal canonicalization. |
| `SimNavPathRequestQueue` | Budgeted/worker batch queue for long and short path requests. |

## Public Function Boundary

General rule: non-underscore methods on stable entry-point classes are supported
unless this document marks them as diagnostics/test support. Underscore-prefixed
methods remain implementation details.

### Map And Projection

`SimNavMap` public entry points:

- Constructor: `SimNavMap.new(width, height, navcell_size, origin, navcells_per_tile)`.
  `navcells_per_tile` is clamped to at least `1`; default constructor creates an
  empty clean map.
- Passability: `register_passability_class()`, `get_passability_registry()`,
  `get_passability_classes()`, `get_passability_mask()`.
- Terrain: `get_terrain_tile_map()`, `navcell_to_terrain_tile()`,
  `get_terrain_tile_data()`, `set_terrain_tile_data()`,
  `get_navcell_terrain_data()`, `rebuild_terrain_passability()`.
- Obstructions: `add_static_obstruction()`, `add_dynamic_obstruction()`,
  `remove_obstruction()`, `move_obstruction()`, `clear_dynamic_obstructions()`,
  `replace_dynamic_obstructions()`, `get_obstruction_shape()`,
  `get_obstruction_shapes_in_range()`, `get_static_obstruction_shapes()`,
  `get_dynamic_obstruction_shapes()`.
- Dirty/raster lifecycle: `rebuild_dirty()`, `rasterize_dirty_obstructions()`,
  `mark_dirty_navcell()`, `is_dirty_navcell()`, `collect_dirty_navcells()`,
  `collect_dirty_obstruction_navcells()`, `has_dirty_navcells()`,
  `has_dirty_obstruction_navcells()`, `clear_dirty_navcells()`,
  `clear_dirty_obstruction_navcells()`.
- Navcell helpers: `navcell_center_world()`, `world_to_navcell()`,
  `is_passable_navcell()`, `get_navcell_data()`, `set_navcell_data()`,
  `or_navcell_data()`, `and_navcell_data()`, `is_valid_navcell()`.
  `get_navcell_data()` composes manual/base navcell data, derived terrain
  passability, and static obstruction raster data.

Projection DTOs:

- `SimNavObstructionShapeStatic`: public fields from the base shape plus
  `width`, `height`, `rotation_rad`; methods `get_corners()`, `get_axes()`,
  `contains_point()`, and `contains_point_with_clearance()`.
- `SimNavObstructionShapeUnit`: public fields from the base shape plus
  `clearance`, `moving`; method `contains_point()`.
- `SimNavObstructionShape`: base fields `type`, `tag`, `entity_id`, `center`,
  `flags`, `control_group`, and `control_group_2`. Treat it as a returned base
  type, not as an adapter input type.

### Passability And Terrain

- `SimNavPassabilityClassConfig` is a field DTO: `class_name_id`, `bit_index`,
  `clearance`, `affects_pathfinding`, and `terrain_mask`.
- `clearance` is the path-center radius for that passability class. During
  navcell rasterization, terrain and static obstruction masks are expanded by
  this radius for the class's bit. `clearance == 0` means only the terrain cell
  or static shape footprint blocks that class.
- `terrain_mask` is interpreted against `SimNavTerrainTileMap` tile data. When
  `(tile_data & terrain_mask) != 0`, the tile's navcells are blocked for that
  passability class and neighboring navcells are also blocked when the class
  `clearance` circle around the navcell center overlaps the blocked terrain
  navcell rectangle. `terrain_mask == 0` means terrain data does not block that
  class. Terrain bits remain project-owned, so a game can map bits to water,
  cliff, slope, shore, material, or other navigation surface inputs without
  making those concepts core gameplay policy.
- `SimNavPassabilityClassRegistry` exposes `register()`, `get_pass_class()`,
  `get_mask()`, `get_class_by_mask()`, `get_classes()`, `max_clearance()`, and
  `size()`.
- `SimNavTerrainTileMap` exposes `navcell_to_tile()`, `tile_origin_navcell()`,
  `is_valid_tile()`, `get_tile_data()`, `set_tile_data()`, and
  `get_navcell_terrain_data()`.
- Prefer `SimNavMap.set_terrain_tile_data()` for terrain edits. It updates the
  raw tile data, derives clearance-expanded terrain passability into navcells,
  and marks changed navcells dirty. A terrain edit recomputes the edited tile
  plus the surrounding navcells that may be affected by registered class
  clearances. If a tool edits `SimNavTerrainTileMap` directly, call
  `SimNavMap.rebuild_terrain_passability()` before path queries.

### Static Obstruction Rasterization

- Static obstructions with `SimNavObstructionFlags.BLOCK_PATHFINDING` rasterize
  into the same composed navcell passability data used by terrain.
- For each registered pathfinding class, `SimNavMap` tests the navcell center
  against `SimNavObstructionShapeStatic.contains_point_with_clearance(point,
  config.clearance)`. This lets the same static obstruction block a large class
  while still allowing a small class through a narrow gap.
- Dynamic unit obstructions are not baked into long-range navcell data. They
  remain short-path/local-query input.

### Path Queries

- `SimNavPathGoal` exposes factories `point()`, `circle()`,
   `inverted_circle()`, `square()`, and `inverted_square()`, plus
   `navcell_contains_goal()`, `contains_point()`, `distance_to_point()`, and
   `nearest_point_on_goal()`, `clone()`, and `copy_from()`.
- `SimNavReachabilityResult` exposes:
  - booleans `is_reachable` and `canonicalized`;
  - failure reason strings `none`, `not_recomputed`, `invalid_query`,
    `no_start_region`, `original_goal_unreachable`, and `no_reachable_goal`;
  - metadata `pass_mask`, `passability_class_name`, `start_navcell`,
    `effective_start_navcell`, `canonical_navcell`, `start_global_region`,
    `canonical_global_region`, `query_goal`, and `canonical_goal`;
  - helpers `has_canonical_goal()` and `is_failure()`.
  `is_reachable == false` can still return a canonical fallback goal when
  `canonicalized == true`; adapter policy decides whether to move there, notify,
  retry, or cancel.
- `SimNavWaypointPath` exposes `waypoints`, `size()`, `is_empty()`, `back()`,
   `pop_back()`, `push_back()`, and `clear()`. Stored waypoints are consumed by
   callers; movement execution is outside the addon.
- `SimNavHierarchicalPathfinder` exposes `recompute()`, `recompute_dirty()`,
   `is_recomputed()`, `get_region()`, `get_global_region()`,
   `is_navcell_reachable()`, `query_goal_reachability()`,
   `make_goal_reachable_navcell()`, and `find_nearest_passable_navcell()` for
   integration. `get_chunk()`,
   `get_global_regions()`, and `next_global_region()` are diagnostics/test
   support and should not become game logic dependencies.
- `SimNavLongPathfinder` exposes `compute_path_immediate()` and
  `invalidate_jump_point_cache()`. Dirty navcells invalidate the jump-point cache
  before subsequent queries.
- `SimNavVertexPathfinder` exposes `compute_short_path_immediate()`.
- `SimNavShortPathRequest` is a field DTO: `start`, `goal`, `clearance`,
  `range_px`, `pass_mask`, `avoid_moving_units`, and `control_group`.
- `SimNavPathfinderFacade` exposes `recompute_dirty()`, `query_reachability()`,
  and `compute_path_immediate()`. `recompute_dirty()` is the stable batch edit
  lifecycle entry: it rasterizes dirty static obstructions, recomputes dirty
  hierarchical chunks, invalidates the long-path jump-point cache, and clears
  dirty navcells by default. `query_reachability()` returns
  `SimNavReachabilityResult` for `POINT`, `CIRCLE`, `SQUARE`, and inverted goals.
  `compute_path_immediate()` uses the same reachability query before long-path
  search and may canonicalize the supplied goal object in place when a fallback
  point goal is required.
- `SimNavPathRequestQueue` exposes `enqueue_long_path()`, `enqueue_short_path()`,
  `cancel()`, `process_budget()`, `start_worker()`, `is_worker_running()`,
  `collect_worker_results()`, `has_result()`, `take_result()`,
  `pending_count()`, `result_count()`, and `clear()`. Queue enqueue clones the
  supplied goal/request data, so later caller-side mutation does not alter the
  queued request.

## Adapter Boundary

Game or example code should keep its own domain objects and convert them into
navigation projections:

```text
Game unit/building/obstacle
  -> project adapter
  -> SimNavObstructionShapeStatic / SimNavObstructionShapeUnit
  -> SimNavMap
  -> path query
  -> SimNavWaypointPath
  -> project movement code
```

Adapter-owned policy includes:

- which entities participate in a query
- how often dynamic obstructions are rebuilt
- whether same-control-group units block this query
- whether moving units are avoided
- what clearance/radius is used for a unit type
- whether to try short path before long path
- how unreachable goals are exposed back to gameplay

Those choices are not core addon API.

## Advanced Support Classes

These classes are usable, but they are lower-level than the main integration
surface and may remain more implementation-shaped:

| Class | Use |
|---|---|
| `SimNavObstructionManager` | Convenience wrapper around obstruction registration and rasterization for tests or tools. `SimNavMap` remains the primary map owner. |
| `SimNavSpatialIndex` | Spatial query primitive for obstruction bounds. |
| `SimNavLineOfSight` | Geometry helper used by short paths and diagnostics. |
| `SimNavJumpPointCache` | Long-path cache helper. Call `SimNavLongPathfinder.invalidate_jump_point_cache()` instead for normal integration. |

## Internal Helpers

These classes are implementation details unless a future documented use case
promotes them:

- `SimNavHierarchicalChunk`
- `SimNavJumpPointHit`
- `SimNavPathfinderHeap`
- `SimNavRegionIdHelper`

Do not build application logic against these helpers.

## Non-Goals

The core addon intentionally does not implement:

- unit movement, acceleration, turning, stopping, or arrival policy
- crowd steering
- formation assignment
- push/yield or soft-block policy
- deadlock resolution
- combat, command, selection, HUD, rendering, or editor tools

`examples/rts-pathfinding-lab` may experiment with those behaviors as
application policy, but that does not make them reusable `sim-nav-map` API.

## Compatibility Note

`addons/logic-game-framework/example/rts-auto-battle` keeps an RTS-shaped
`RtsPathfinderFacade` adapter for production call sites. Its old private
pathfinder classes are archived fixture implementations. New navigation work
should target `sim-nav-map` directly or through a project adapter.
