# CORE-005: `CLEARANCE_EXTENSION_RADIUS` not implemented

- Status: open
- Severity: P1
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07

## Symptoms

There is no place in the codebase where the long-path passability
rasterization is +1 navcell more conservative than the short-path
obstruction edges. The 0 A.D. invariant "a path the long pathfinder
returns is always traversable by the short pathfinder" is therefore not
guaranteed. In tight corridors with corners, the long path can hand the
lab a waypoint sequence the short path then refuses.

## Root cause

The constant `CLEARANCE_EXTENSION_RADIUS = 1` (in entity-pos units) is
defined in 0 A.D. (`Pathfinding.h:160`) and applied during static
obstruction rasterization to artificially inflate the rasterized blocker
by one navcell more than the class clearance. `addons/sim-nav-map/`
defines no such constant and does not extend during rasterization.

## 0 A.D. reference

- `docs/references/0ad-source/source/simulation2/helpers/Pathfinding.h:157-160`
  documents the +1 navcell extension explicitly: "make sure the
  long-range pathfinder is more strict than the short-range one".
- The extension is consumed in `Rasterize()` paths inside
  `CCmpObstructionManager.cpp` when stamping the navcell grid for each
  passability class.

## Proposed fix

1. Define `CLEARANCE_EXTENSION_RADIUS` as a named constant on
   `SimNavObstructionFlags` (or a sibling `sim_nav_constants.gd` if the
   flags file is the wrong home). Default value `1.0 * navcell_size`.
2. In `SimNavMap._rasterize_static_obstruction()`
   (`model/sim_nav_map.gd:404-421`), pass
   `clearance + CLEARANCE_EXTENSION_RADIUS` to
   `contains_point_with_clearance()` instead of just `clearance` from the
   passability class.
3. Document the invariant in `public-api.md`: long-path may refuse paths
   the short-path could in principle take, but never the reverse.
4. Coordinate with [CORE-007](core-007-static-rasterize-aabb.md) — the
   AABB iteration optimization will need to expand its AABB by the same
   extension radius.

## Verify before fixing

- [ ] Audit each call to `contains_point_with_clearance` for any unit-side use that should NOT include the extension (vertex graph short-path expansion is already separate; verify)
- [ ] Confirm there is no smoke that currently relies on long-path being equally-permissive-as-short-path (would need updating)
- [ ] Decide constant unit — navcell-multiples or world-units, document choice

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/tests/repro_core_005_clearance_extension.tscn
```

Smoke: [`tests/repro_core_005_clearance_extension.gd`](../../tests/repro_core_005_clearance_extension.gd).

Setup: 16×16 navcell grid, navcell_size=8. Pass class clearance 0. One
1-cell static OBB centered at navcell (7, 7). Per the missing
`CLEARANCE_EXTENSION_RADIUS = 1` invariant, navcells immediately adjacent
to the body — (8, 7), (6, 7), (7, 8), (7, 6) — should be impassable too.

At HEAD (commit 6335f32) the smoke FAILs:

```text
SMOKE_TEST_RESULT: FAIL - CORE-005 reproduces:
  navcell (8, 7) (1 navcell from OBB body) is passable; expected impassable per CLEARANCE_EXTENSION_RADIUS;
  navcell (6, 7) (1 navcell from OBB body) is passable; ...
  navcell (7, 8) (1 navcell from OBB body) is passable; ...
  navcell (7, 6) (1 navcell from OBB body) is passable; ...
```

All 4 cardinally-adjacent cells are passable; only the body cell (7, 7)
is impassable. Long-path is therefore not stricter than short-path.

## Regression after fix

Add `CLEARANCE_EXTENSION_RADIUS` and apply it during static rasterization.
The smoke flips to `PASS` because each of the 4 adjacent cells becomes
impassable. Add a follow-up smoke for the long-vs-short corridor invariant
once short-path tests can rely on the extended raster.

## Cross-refs

- [CORE-001](core-001-vertex-obb-outset.md) — both touch how clearance is applied around static OBBs
- [CORE-007](core-007-static-rasterize-aabb.md) — rasterize loop will gain the extension
- [LAB-003](lab-003-active-jump-55px.md) — a hand-off failure between long and short can produce visible movement glitches
