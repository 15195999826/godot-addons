# CORE-007: Static obstruction rasterization scans full grid

- Status: resolved
- Severity: P3
- Layer: core
- Source: claude-audit-2026-05-07
- Created: 2026-05-07
- Resolved: 2026-05-07

## Resolution

- submodule commit: `f2bf447`
- smoke: `addons/sim-nav-map/tests/repro/repro_core_007_static_rasterize_aabb.tscn` (registered under `simnav/smoke` group)
- 0 A.D. files checked: `source/simulation2/components/CCmpObstructionManager.cpp` Rasterize() (AABB-clipped per-cell containment), `source/simulation2/helpers/Rasterize.cpp` (clearance-expanded AABB iteration)
- Fix:
  1. `_rasterize_static_obstruction` now iterates only the shape's clearance-expanded AABB instead of the full grid (mirrors `_mark_obstruction_shape_dirty`'s AABB).
  2. `rebuild_dirty` now scans only the union of every static shape's clearance-expanded AABB plus pre-existing obstruction-dirty cells (which capture removed/moved-shape footprints), recomputing each cell's mask via the spatial-index-backed `_blocked_mask_for_static_obstructions_at`. Drops the prior O(grid) `_compose_navcell_data` snapshot, full `_clear_obstruction_navcell_data`, and full-grid diff.
  3. Added a parallel `_obstruction_dirty_cell_list: Array[Vector2i]` so `collect_dirty_obstruction_navcells` / `has_dirty_obstruction_navcells` / `clear_dirty_obstruction_navcells` run in O(dirty_count) instead of O(grid). Membership stays sourced from the byte array (single source of truth).
- AABB expansion uses `max_clearance + navcell_size`, leaving a navcell of slack so a future CLEARANCE_EXTENSION_RADIUS (CORE-005, currently aborted) can fold in without breaking the AABB bound.
- baseline impact: smoke ratio collapses from 15-16× (area-bound) to ~1× (AABB-bound). No external API change. Dirty lifecycle, full-rebuild semantics, and rasterized data identical to prior implementation per the existing simnav/smoke + rtslab/smoke regression matrix.

## Symptoms

Adding or updating one static obstruction iterates every navcell in the
grid, testing OBB containment per cell per passability class. On larger
maps or when many static shapes are added in one frame this is the
dominant cost in obstacle setup and shows up in `LAB-001` / `LAB-002`
stress traces.

## Root cause

`addons/sim-nav-map/model/sim_nav_map.gd:404-421` —
`_rasterize_static_obstruction()` runs `for y in range(height)` /
`for x in range(width)` over the full grid, calling
`contains_point_with_clearance()` per cell per class.

## 0 A.D. reference

`docs/references/0ad-source/source/simulation2/components/CCmpObstructionManager.cpp`
`Rasterize()` first computes the AABB of the OBB (in navcells), clips to
the map bounds, then iterates only those cells. Per-cell containment is
still required (because the OBB is rotated), but the *number* of cells
scanned is `O(w·h)` of the OBB AABB, not of the whole map.

## Proposed fix

1. Compute the OBB's axis-aligned bounding box in navcells:
   - corners = `static_shape.get_corners()` (already exists)
   - `i_min, i_max, j_min, j_max` from corner navcell coordinates,
     expanded by `clearance + CLEARANCE_EXTENSION_RADIUS` (per
     [CORE-005](core-005-clearance-extension-radius.md)) and clipped to
     the map's navcell range (per [CORE-004](core-004-set-bounds-missing.md)).
2. Iterate only cells in that range.
3. Keep the per-cell `contains_point_with_clearance()` as-is.

This is an arithmetic-only change. Should not affect correctness as long
as the AABB expansion correctly accounts for clearance + extension.

## Verify before fixing

- [ ] Lock CORE-005 first or design the AABB expansion to fold in the extension radius cleanly
- [ ] Confirm `get_corners()` returns world-space corners (not navcell-space) and convert appropriately
- [ ] Add a debug assert: `iterated_cells ≤ aabb_w * aabb_h` to catch off-by-one in the new bounds

## Repro at HEAD

```powershell
godot --headless --path . addons/sim-nav-map/tests/repro/repro_core_007_static_rasterize_aabb.tscn
```

Smoke: [`tests/repro/repro_core_007_static_rasterize_aabb.gd`](../../tests/repro/repro_core_007_static_rasterize_aabb.gd).

Setup: rasterize the same 16×16 static OBB on a 256×256 navcell grid
versus a 1024×1024 grid. Area ratio is 16×; with AABB-clipped raster the
work is bounded by the OBB AABB and time should be roughly equal.

At HEAD (commit 6335f32) the smoke FAILs:

```text
CORE-007 rasterize timing: small_256² ≈ 75-92k µs, large_1024² ≈ 1.24-1.32M µs, ratio ≈ 13.5–17.0×
SMOKE_TEST_RESULT: FAIL - CORE-007 reproduces: rasterize time grew 16.0x going from 256² to 1024²; expected ≤ 5.0x with AABB-clipped raster
```

**Stability**: 5/5 runs FAIL. Ratio always > 13.5× (close to the
theoretical 16× from area scaling). Absolute timing varies ±15% with
machine load; the verdict (ratio > 5×) is stable.

## Regression after fix

After the AABB-clipped raster lands, the smoke flips to PASS (ratio ≤ 2×
within timing noise). Once green, register the smoke in
`tests/test_groups.json` under `simnav/smoke` to lock in the regression.
Existing `smoke_sim_nav_clearance_rasterization.gd` must remain
bit-identical against the full-scan baseline.

## Cross-refs

- [CORE-005](core-005-clearance-extension-radius.md) — AABB expansion must include the extension
- [CORE-004](core-004-set-bounds-missing.md) — AABB clip target
- [LAB-001](lab-001-default-avg-step.md) / [LAB-002](lab-002-stress-long-frames.md) — likely contributors to the stress numbers
