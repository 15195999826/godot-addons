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
reachability and canonical goal metadata. Feature 5 long-path result coverage is
in `smoke_sim_nav_long_pathfinder.tscn` and
`smoke_sim_nav_path_request_queue.tscn`. Feature 6-8 coverage adds
`smoke_sim_nav_line_validation.tscn`, `smoke_sim_nav_diagnostics_exports.tscn`,
and expanded queue/vertex/public API smoke. Lab-side regression coverage lives
under `examples/0ad-rts-pathfinding-lab/tests/`.

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
| `SimNavObstructionFilter` | Reusable obstruction filter DTO for range queries, short-path queries, movement-line validation, and unit-only line validation. |
| `SimNavPathGoal` | Path target geometry: point, circle, square, and inverted variants. |
| `SimNavReachabilityResult` | Result DTO for explicit reachability/canonical goal queries. |
| `SimNavWaypointPath` | Returned path container. Callers own movement along these waypoints. |
| `SimNavLongPathQuery` | Request DTO for long-path queries: start, goal, passability mask/class name, request-scoped excluded regions, and post-processing preferences. |
| `SimNavLongPathResult` | Result DTO for long-path status, failure/canonicalization metadata, raw navcell path, refined waypoint path, cost, and length. |
| `SimNavShortPathResult` | Result DTO for short-path status, range failure, query metadata, path length, candidate count, and obstruction count. |
| `SimNavMovementLineResult` | Result DTO for movement-line and unit-only line validation status plus blocker metadata. |
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
- Playable bounds: `set_bounds(x0, z0, x1, z1)`, `is_inside_playable_bounds(world_pos)`,
  `get_playable_bounds_min()`, `get_playable_bounds_max()`. Mirrors 0 A.D.
  `ICmpObstructionManager::SetBounds`. Default bounds equal the full backing-grid
  world extent. Long-path queries with start or `POINT` goal outside the playable
  bounds return `STATUS_INVALID_QUERY` with `FAILURE_START_OUT_OF_BOUNDS` /
  `FAILURE_GOAL_OUT_OF_BOUNDS`. Static rasterization clips: a static obstruction
  straddling the rectangle only rasterizes its in-bounds cells. Circular bounds
  remain intentionally deferred.
- Passability: `register_passability_class()`, `get_passability_registry()`,
  `get_passability_classes()`, `get_passability_mask()`.
- Terrain: `get_terrain_tile_map()`, `navcell_to_terrain_tile()`,
  `get_terrain_tile_data()`, `set_terrain_tile_data()`,
  `get_navcell_terrain_data()`, `rebuild_terrain_passability()`.
- Obstructions: `add_static_obstruction()`, `add_dynamic_obstruction()`,
  `remove_obstruction()`, `move_obstruction()`, `clear_dynamic_obstructions()`,
  `replace_dynamic_obstructions()`, `mark_obstruction_shape_dirty()`,
  `get_obstruction_shape()`,
  `get_obstruction_shapes_in_range()`, `get_obstruction_shapes_in_range_filtered()`,
  `get_static_obstruction_shapes()`,
  `get_dynamic_obstruction_shapes()`.
  `mark_obstruction_shape_dirty(shape)` lets callers force re-rasterization of
  a registered static shape's body region after a flag-only edit; it no-ops
  for unit shapes (they are not baked into navcell data). The same dirtying
  is wired through `SimNavObstructionShape.flags`'s setter, so direct
  `shape.flags = ...` mutation on a registered shape also marks navcells dirty.
- Dirty/raster lifecycle: `rebuild_dirty()`, `rasterize_dirty_obstructions()`,
  `mark_dirty_navcell()`, `is_dirty_navcell()`, `collect_dirty_navcells()`,
  `collect_dirty_obstruction_navcells()`, `has_dirty_navcells()`,
  `has_dirty_obstruction_navcells()`, `clear_dirty_navcells()`,
  `clear_dirty_obstruction_navcells()`, `get_dirtiness_snapshot()`, and
  `get_diagnostics()`. Diagnostics are read-only snapshots.
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
- `SimNavObstructionFilter`: field DTO plus factories `all()`,
  `for_short_path()`, and `units_only()`. It supports static/unit inclusion,
  moving/stationary unit inclusion, ignored tag/entity ids, control-group
  filtering, required flags, excluded flags, `matches()`, and `clone()`.
  It describes navigation query participation only; it does not encode unit
  role, command, formation, priority, or movement policy.

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
   `pop_back()`, `push_back()`, and `clear()`. Stored waypoints are in
   reverse-consumption order: `waypoints[0]` is the final goal-side point and
   `back()` is the next point a consumer would pop. This preserves the existing
   `SimNavWaypointPath` contract and matches 0 A.D.'s consumption shape.
- `SimNavLongPathQuery` exposes:
  - `start_world`, `goal`, `pass_mask`, and `passability_class_name`;
  - request-scoped `excluded_regions`, populated with `add_excluded_circle()`.
    These regions are treated as blocked only for that query and do not mutate
    `SimNavMap`;
  - post-processing constants `raw`, `line_of_sight`, and `max_spacing`;
  - `waypoint_spacing`, used directly when positive. If it is zero and
    `goal.maxdist > 0`, the goal's max distance acts as the spacing preference;
  - `from_values()` and `clone()` helpers. Queue enqueue clones the query.
- `SimNavLongPathResult` exposes:
  - statuses `success`, `canonicalized`, `start_recovered`, `direct_goal`,
    `unreachable`, `no_path`, `invalid_start`, and `invalid_query`;
  - failure reasons `none`, `nav_map_missing`, `goal_missing`,
    `pass_mask_missing`, `map_too_large`, `start_out_of_bounds`,
    `start_blocked`, `goal_out_of_bounds`, `goal_blocked`, and `no_route`;
  - canonicalization metadata `canonicalized`, `canonicalization_reason`,
    `reachability_result`, `query_goal`, `canonical_goal`, `start_navcell`,
    `effective_start_navcell`, and `canonical_navcell`;
  - request metadata `pass_mask`, `passability_class_name`, `excluded_regions`,
    `post_process`, and `waypoint_spacing`;
  - path metadata `raw_navcell_path`, `raw_waypoint_path`,
    `refined_waypoint_path`, `path`, `path_cost`, `path_length`,
    `raw_navcell_count`, `raw_waypoint_count`, and `refined_waypoint_count`.
    `raw_navcell_path` is stored from start to goal for diagnostics; waypoint
    paths remain reverse-consumption order.
  - helpers `is_success()` and `has_path()`.
- `SimNavHierarchicalPathfinder` exposes `recompute()`, `recompute_dirty()`,
   `is_recomputed()`, `get_region()`, `get_global_region()`,
   `is_navcell_reachable()`, `query_goal_reachability()`,
   `make_goal_reachable_navcell()`, and `find_nearest_passable_navcell()` for
   integration. `export_connectivity()` returns a passability-scoped read-only
   connectivity snapshot. `get_chunk()`, `get_global_regions()`,
   `next_global_region()`, and `get_diagnostics()` are diagnostics/test support
   and should not become game logic dependencies.
- `SimNavLongPathfinder` exposes `compute_path_immediate()` and
  `compute_path_result()`, plus `invalidate_jump_point_cache()`. Dirty navcells
  invalidate the jump-point cache before subsequent queries.
  `compute_path_immediate()` is the compatibility path-only API.
  `compute_path_result()` is the Feature 5 contract API and returns
  `SimNavLongPathResult`.
- `SimNavVertexPathfinder` exposes `compute_short_path_immediate()` and
  `compute_short_path_result()`. The immediate method preserves path-only
  compatibility; the result method returns status/metadata.
- `SimNavShortPathRequest` is a field DTO: `start`, `goal`, `clearance`,
  `range_px`, `pass_mask`, `avoid_moving_units`, `control_group`, and optional
  `obstruction_filter`. `get_obstruction_filter()` derives the legacy
  `avoid_moving_units` / `control_group` fields into the shared filter protocol
  when no explicit filter is supplied. `clone()` owns the goal and filter data.
- `SimNavShortPathResult` exposes statuses `success`, `direct_goal`,
  `same_goal`, `out_of_range`, `no_path`, and `invalid_query`; failure reasons
  `none`, `nav_map_missing`, `goal_missing`, `range_exceeded`, and `no_route`;
  query metadata, filter snapshot, path, path length, candidate count, and
  obstruction count.
- `SimNavPathfinderFacade` exposes `recompute_dirty()`, `query_reachability()`,
  `compute_path_result()`, `compute_path_immediate()`, `validate_movement_line()`,
  `validate_unit_line()`, and `get_navigation_diagnostics()`. `recompute_dirty()` is the stable batch edit
  lifecycle entry: it rasterizes dirty static obstructions, recomputes dirty
  hierarchical chunks, invalidates the long-path jump-point cache, and clears
  dirty navcells by default. `query_reachability()` returns
  `SimNavReachabilityResult` for `POINT`, `CIRCLE`, `SQUARE`, and inverted goals.
  `compute_path_result()` uses the same reachability query before long-path
  search and snapshots canonicalization/start-recovery metadata into
  `SimNavLongPathResult`. `compute_path_immediate()` remains a compatibility
  path-only API and may canonicalize the supplied goal object in place when a
  fallback point goal is required. `validate_movement_line()` checks a swept
  segment against passability and filtered obstructions. `validate_unit_line()`
  checks only dynamic unit obstructions under the same filter protocol. Neither
  method decides retry, stop, push, yield, or stuck behavior.
- `SimNavPathRequestQueue` exposes `enqueue_long_path()`, `enqueue_short_path()`,
  `enqueue_long_path_query()`, `cancel()`, `process_budget()`, `start_worker()`,
  `is_worker_running()`, `collect_worker_results()`, `has_result()`,
  `take_result()`, `take_long_path_result()`, `take_short_path_result()`,
  `pending_count()`, `result_count()`, `pending_tickets()`, `result_tickets()`,
  `get_diagnostics()`, and `clear()`. Queue enqueue clones the supplied
  goal/request/query data, so later caller-side mutation does not alter the
  queued request. `take_result()` preserves the path-only compatibility contract;
  `take_long_path_result()` and `take_short_path_result()` return metadata DTOs.
  `process_budget(max_requests)` computes at most that many live queued requests
  per call. `start_worker(max_requests)` takes a deterministic batch and
  `collect_worker_results()` stores live results while skipping cancelled
  in-flight tickets as stale results.
- `SimNavMovementLineResult` exposes statuses `clear`, `blocked`, and
  `invalid_query`; failure reasons for passability, out-of-bounds, static
  obstruction, unit obstruction, and missing map; checked counts; blocked
  navcell; blocked obstruction tag/entity/type; filter snapshot; and
  `is_success()`.

### Diagnostics And Exports

- `SimNavMap.get_dirtiness_snapshot()` returns read-only arrays/counts for dirty
  navcells and dirty obstruction navcells. `get_diagnostics()` adds map size,
  origin, navcell size, passability class count, and obstruction counts.
- `SimNavHierarchicalPathfinder.export_connectivity(pass_mask, class_name)`
  returns a read-only global-region grid snapshot for one passability class plus
  chunk/map metadata. Consumers must not depend on chunk objects.
- `SimNavPathfinderFacade.get_navigation_diagnostics(passability_masks)`
  aggregates map and hierarchical diagnostics.
- `SimNavPathRequestQueue.get_diagnostics()` returns scheduling facts: pending
  and result tickets, cancellation/stale counts, worker state, batch size, and
  processed/collected ticket ids. It does not expose movement cadence or unit
  command policy.

### 0 A.D. Intentional Differences

Feature 5 uses 0 A.D. as a source-design reference but does not copy its public
API:

- 0 A.D. exposes long-path results mostly as ticket + `WaypointPath`; `sim-nav-map`
  exposes explicit status, failure reason, canonicalization metadata, path cost,
  path length, raw/refined counts, and request echo metadata.
- 0 A.D. internal canonicalization and start recovery are mostly hidden from
  consumers; `sim-nav-map` surfaces them in `SimNavLongPathResult`.
- `SimNavWaypointPath` keeps reverse-consumption order for compatibility, while
  `SimNavLongPathResult.raw_navcell_path` is start-to-goal for diagnostics.
- 0 A.D. UnitMotion layers short-path fallback, retry cadence, push/yield, and
  movement policy on top of sparse results. Those policies remain outside
  `sim-nav-map` core.
- Feature 6-8 follow the same boundary: 0 A.D. supplies filter, line-test,
  ticket/batch, dirtiness, and connectivity ideas; `sim-nav-map` exposes small
  GDScript DTOs and snapshots while leaving movement policy to adapters.

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
| `SimNavObstructionManager` | Convenience wrapper around obstruction registration and rasterization for tests or tools. `SimNavMap` remains the primary map owner. Setters: `set_unit_moving_flag()`, `set_control_group()`, `set_static_flags(tag, flags)`, `set_unit_flags(tag, flags)`. The flag setters propagate dirty navcells through `SimNavObstructionShape.flags`'s setter. |
| `SimNavSpatialIndex` | Spatial query primitive for obstruction bounds. |
| `SimNavLineOfSight` | Geometry helper used by short paths and diagnostics. |
| `SimNavJumpPointCache` | Long-path JPS+ ray tables (cardinal jump/obstruction/boundary distances precomputed per reset) plus the baked passability grid. Call `SimNavLongPathfinder.invalidate_jump_point_cache()` instead for normal integration. |

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

`examples/0ad-rts-pathfinding-lab` may experiment with those behaviors as
application policy, but that does not make them reusable `sim-nav-map` API.

## Compatibility Note

`addons/logic-game-framework/example/rts-auto-battle` keeps an RTS-shaped
`RtsPathfinderFacade` adapter for production call sites. Its old private
pathfinder classes are archived fixture implementations. New navigation work
should target `sim-nav-map` directly or through a project adapter.
