# RTS Pathfinding Lab

This is an isolated playable lab for RTS pathfinding behavior. It consumes
`addons/sim-nav-map` through a small adapter, while lab-specific unit movement,
obstacle editing, push behavior, selection, drawing, and HUD code stay in this
example.

The lab is not `sim-nav-map` public API. It is the plugin-local application that
proves how an adapter can consume the addon without moving game policy into core.

## Current Architecture

The lab is intentionally split from the reusable addon:

- `logic/rts_pathfinding_lab_pathfinder.gd`: adapts lab obstacles and units into
  `SimNavMap`, `SimNavObstructionShapeStatic`, `SimNavObstructionShapeUnit`,
  `SimNavHierarchicalPathfinder`, `SimNavLongPathfinder`, and
  `SimNavVertexPathfinder`.
- `logic/rts_pathfinding_lab_world.gd`: owns the playable simulation loop,
  selected-unit move orders, formation offsets, replan queue, unit movement,
  overlap resolution, obstacle/blocker editing, and movement analysis metrics.
- `logic/rts_pathfinding_lab_unit.gd`: stores unit state, current path,
  `has_move_order`, arrival state, and trace points.
- `logic/rts_pathfinding_lab_obstacle.gd`: stores simple rectangle obstacles for
  lab editing and adapter conversion.
- `frontend/rts_pathfinding_lab.gd`: draws the playable scene and wires input,
  selection, editing modes, HUD counters, and world stepping.
- `tests/`: smoke tests for headless movement contracts and real scene loading.

The pathfinder adapter caches the static `SimNavMap` and hierarchical
reachability context by obstacle signature. Per-plan dynamic units are converted
to `SimNavObstructionShapeUnit`, so unit avoidance can change without rebuilding
the static map every frame.

The world processes replans through a small per-tick budget. This keeps
multi-unit orders from computing every unit's path in one long frame. Active
move orders replan periodically; idle units can be pushed and then settle at
their displaced position instead of trying to path back to a stale target.

Unreachable point commands are canonicalized to the nearest reachable navcell
reported by `sim-nav-map`, and the lab syncs the unit target to that reachable
goal so units can stop cleanly at building edges.

## Current Behavior

- Single-unit and 6-unit movement are expected to be stable in the default map.
- Multiple selected units moving to one point use simple fixed offsets, not a
  polished formation system.
- Narrow-passage behavior currently allows physical pushing when overlap
  resolution moves units apart.
- Two units meeting from opposite sides of a narrow passage can block each other
  until one unit is moved or the local geometry opens.
- `G` toggles same-control-group filtering for dynamic avoidance.
- `D` toggles moving-unit avoidance.
- The HUD prints movement quality and performance counters, including
  `world.step` current/average/max time, per-tick replan count, pending replan
  queue size, static context cache hits/misses, arrival count, overlap, and
  obstacle violations.

## Play

Open:

```text
addons/sim-nav-map/examples/rts-pathfinding-lab/frontend/rts_pathfinding_lab.tscn
```

Controls:

- `1`: select/move mode.
- Left click: select one unit.
- Left drag: box select units.
- Right click: move selected units. If nothing is selected, all blue units move.
- `2`: place static obstacle mode, then left click to place.
- `3`: place red blocker mode, then left click to place.
- `4`: erase mode, then left click near an obstacle/blocker.
- `A`: select all blue units.
- `C`: clear movement traces.
- `R`: reset the default scenario.
- `Space`: pause/resume.
- `G`: toggle group filter.
- `D`: toggle dynamic unit avoidance.

## Smoke

```powershell
./tools/run_tests.ps1 rtslab/smoke
```

This group is the stable regression entry for the lab adapter and playable scene
load. Core addon behavior belongs to `simnav/smoke`; legacy RTS private
pathfinder fixtures under `logic-game-framework/example/rts-auto-battle` are
archived compatibility coverage, not the lab baseline.

## Future Directions

- Add a real formation system if gameplay needs deterministic final layouts,
  priority slots, or no-clump destination assignment.
- Decide game-specific crowd rules for pushing, yielding, narrow-passage
  deadlocks, stuck detection, and unit priority. These are gameplay policy, not
  core pathfinding primitives.
- Tune replan cadence and budget for larger unit counts after adding larger lab
  scenarios.
- Add optional debug views for selected unit path, reachable-goal adjustment,
  dynamic obstruction shapes, and hierarchical regions.
- Keep production RTS behavior separate from lab-only comfort features unless a
  sample proves the behavior should be shared.
