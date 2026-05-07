# CORE-001: VertexPathfinder OBB vertex outset wrong direction

- Status: open
- Severity: P0
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

## Symptoms

For non-square static `SimNavObstructionShapeStatic`, the four
visibility-graph corner vertices appended for that obstacle do not sit on
an axis-aligned (in the OBB's frame) clearance ring. Short paths around
elongated buildings can clip corners, take longer-than-necessary detours,
or have visually unstable angles depending on OBB rotation.

## Root cause

`addons/sim-nav-map/pathfinding/sim_nav_vertex_pathfinder.gd:107-111`:

```gdscript
var outset := clearance * CORNER_OUTSET_FACTOR  # 2.0
for corner in static_shape.get_corners():
    var direction := (corner - static_shape.center).normalized()
    vertices.append(corner + direction * outset)
```

Each corner is pushed outward along its corner-to-center *radial*. For a
non-square OBB, the radial is not perpendicular to either OBB axis, so the
four new corners do not form an axis-aligned (in OBB frame) outer
rectangle. Furthermore the hard-coded `2.0` factor over-expands the
half-diagonal rather than the half-width / half-height. Net effect:
expanded corner positions deviate from the intended clearance ring by a
factor that depends on the OBB's aspect ratio.

## 0 A.D. reference

`docs/references/0ad-source/source/simulation2/helpers/VertexPathfinder.cpp:636-685`.
0 A.D. computes expanded corners directly from half-extents on each OBB
axis:

```
corner = center ± (hw + clearance + EDGE_EXPAND_DELTA) · u
              ± (hh + clearance + EDGE_EXPAND_DELTA) · v
```

where `u` and `v` are the OBB's two unit axes. The result is uniform
clearance on each axis, regardless of aspect ratio.

## Proposed fix

Replace the radial-push loop with axis-based expansion. Pseudocode:

```gdscript
var u := static_shape.axis_u()
var v := static_shape.axis_v()
var ehw := static_shape.half_width + clearance + EDGE_EXPAND_DELTA
var ehh := static_shape.half_height + clearance + EDGE_EXPAND_DELTA
for sx in [-1.0, 1.0]:
    for sy in [-1.0, 1.0]:
        vertices.append(static_shape.center + sx * ehw * u + sy * ehh * v)
```

- Drop `CORNER_OUTSET_FACTOR`.
- Introduce a small `EDGE_EXPAND_DELTA` only if vertex degeneracy turns out
  to matter (start with `0.0`).
- If `axis_u()` / `axis_v()` accessors do not exist, add them next to the
  existing `get_corners()` on `SimNavObstructionShapeStatic`.

## Verify before fixing

- [ ] Re-read `sim_nav_vertex_pathfinder.gd:107-111` and `get_corners()` to confirm orientation conventions
- [ ] Confirm `SimNavObstructionShapeStatic` exposes (or can expose) the two unit axes
- [ ] Sanity check: the existing `clearance * 2.0` factor was intentional vs accidental — git blame for context

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/tests/repro_core_001_vertex_obb_outset.tscn
```

Smoke: [`tests/repro_core_001_vertex_obb_outset.gd`](../../tests/repro_core_001_vertex_obb_outset.gd).

Setup: 64×64 navcell map, one 80×16 static OBB at center (256, 256) with
rotation in {0°, 30°, 45°, 90°}, unit clearance 8.0. Plans short path from
(64, 256) to (448, 256). For each emitted waypoint (excluding the goal),
asserts distance to the nearest axis-aligned (in OBB frame) expanded
corner is ≤ 1.0 unit.

At HEAD (commit 6335f32) the smoke FAILs:

```text
SMOKE_TEST_RESULT: FAIL - CORE-001 reproduces:
  rot=0°: short path is empty (no route around OBB);
  rot=30°: waypoint (298.66, 293.49) is 9.10 away from nearest axis-aligned expanded corner;
  rot=45°: waypoint (287.50, 303.25) is 9.10 away from nearest axis-aligned expanded corner;
  rot=90°: waypoint (267.14, 200.31) is 9.10 away from nearest axis-aligned expanded corner
```

The 9.10 displacement is the radial-vs-axis difference for an 80×16 OBB
with clearance 8 — confirms the bug is the radial outset geometry, not
just over-expansion magnitude. The rot=0° empty path also confirms the
buggy graph can become unusable on elongated OBBs.

## Regression after fix

The smoke flips to `PASS` after the fix. Once the smoke is green, register
it in `tests/test_groups.json` under `simnav/smoke` so the regression is
locked in.

## Cross-refs

- [CORE-008](core-008-vertex-quadrant-prune.md) — also in vertex pathfinder
- Architecture: `../references/0ad-pathfinding.md`
