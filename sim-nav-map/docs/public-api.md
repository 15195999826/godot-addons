# Sim Nav Map Public API

This file defines the current public boundary for `addons/sim-nav-map`.

`sim-nav-map` owns navigation data structures and path queries. It does not own
game entities, movement integration, steering, pushing, formation, combat, UI, or
editor workflow.

## Stable Entry Points

These classes are the supported integration surface for game/example adapters:

| Class | Responsibility |
|---|---|
| `SimNavMap` | Central map state: navcell geometry, terrain data, passability classes, obstruction data, dirty tracking, world/navcell conversion. |
| `SimNavPassabilityClassConfig` | Per-class passability configuration: name, clearance, terrain mask, and pathfinding participation. |
| `SimNavPassabilityClassRegistry` | Registers passability classes and assigns masks. Usually accessed through `SimNavMap`. |
| `SimNavTerrainTileMap` | Coarser terrain tile data used by `SimNavMap`. Usually accessed through `SimNavMap`. |
| `SimNavObstructionFlags` | Shared obstruction flags such as `BLOCK_PATHFINDING`, `BLOCK_MOVEMENT`, and `MOVING`. |
| `SimNavObstructionShapeStatic` | Static oriented rectangle projection for buildings, walls, rocks, blockers, and terrain-like obstacles. |
| `SimNavObstructionShapeUnit` | Dynamic circular projection for units. This is not a unit model. |
| `SimNavPathGoal` | Path target geometry: point, circle, square, and inverted variants. |
| `SimNavWaypointPath` | Returned path container. Callers own movement along these waypoints. |
| `SimNavHierarchicalPathfinder` | Reachability and nearest reachable navcell canonicalization. |
| `SimNavLongPathfinder` | Long navcell path search. |
| `SimNavVertexPathfinder` | Local short path search around nearby obstructions. |
| `SimNavShortPathRequest` | Request DTO for short-path queries. |
| `SimNavPathfinderFacade` | Synchronous long-path facade with reachable-goal canonicalization. |
| `SimNavPathRequestQueue` | Budgeted/worker batch queue for long and short path requests. |

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
