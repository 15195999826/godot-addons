# sim-nav-map Issues

Discrete tracker for known bugs, gaps, and improvement work in
`addons/sim-nav-map`. Each `.md` is one issue. `BASELINE.md` defines the
state below which no regression should land.

The earlier lab-side open-issues summary has been absorbed into these issue
files and removed as a separate entry point. Issues seeded from that discussion
are tagged `Source: codex-discussion`.

## Index

Repro column legend:
- **smoke (FAIL)** — dedicated repro smoke exists and FAILs at HEAD with stable output. Fix turns it green.
- **smoke (PASS lock-in)** — current behavior is correct; smoke locks it in. Future regression flips it red.
- **text** — no smoke (API missing, instrumentation missing, or process-only). Manual repro recipe in the issue file.

| ID | Layer | Severity | Title | Status | Repro |
|---|---|---|---|---|---|
| [CORE-001](core-001-vertex-obb-outset.md) | core | P0 | VertexPathfinder OBB vertex outset wrong direction | resolved | smoke (PASS) |
| [CORE-002](core-002-long-path-los-sampling.md) | core | P0 | LongPathfinder LOS refinement sampling can miss narrow gaps | open | text (adversarial scenario pending) |
| [CORE-003](core-003-hierarchical-fallback-radius.md) | core | P0 | Hierarchical fallback uses fixed 256-cell radius | open | smoke (FAIL) |
| [CORE-004](core-004-set-bounds-missing.md) | core | P1 | `SetBounds()` missing — out-of-bounds undefined | open | smoke (FAIL) |
| [CORE-005](core-005-clearance-extension-radius.md) | core | P1 | `CLEARANCE_EXTENSION_RADIUS` not implemented | open | smoke (FAIL) |
| [CORE-006](core-006-flag-setter-api.md) | core | P2 | Per-tag flag mutation API incomplete (dirty propagation missing) | resolved | smoke (PASS) |
| [CORE-007](core-007-static-rasterize-aabb.md) | core | P3 | Static obstruction rasterization scans full grid | resolved | smoke (PASS) |
| [CORE-008](core-008-vertex-quadrant-prune.md) | core | P3 | VertexPathfinder lacks quadrant pruning | open | text (instrumentation pending) |
| [CORE-009](core-009-heap-improve.md) | core | P3 | Pathfinder heap is O(n) sorted-array insert | open | text (instrumentation pending) |
| [LAB-001](lab-001-default-avg-step.md) | lab | P1 | Default avg step ~0.45ms vs ~0.1ms target | open | smoke (FAIL) |
| [LAB-002](lab-002-stress-long-frames.md) | lab | P1 | Stress long frames still 10-15ms | open | smoke (FAIL) |
| [LAB-003](lab-003-active-jump-55px.md) | lab | P1 | Active position jump can hit ~55px (static-escape teleport) | open | smoke (FAIL) |
| [LAB-004](lab-004-overlap-arrival-policy.md) | lab | P2 | Overlap / arrival policy is fragile | open | smoke (PASS lock-in) |
| [LAB-005](lab-005-command-vs-path-target.md) | lab | P2 | Command target vs path target separation | open | smoke (PASS lock-in) |
| [PROCESS-001](process-001-core-lab-proof-protocol.md) | process | P1 | Core-vs-lab proof protocol | open | text (process) |

### Smokes at a glance

Core repro smokes (run with `godot --headless --path . <tscn>`):

```text
addons/sim-nav-map/tests/repro/repro_core_001_vertex_obb_outset.tscn
addons/sim-nav-map/tests/repro/repro_core_003_hierarchical_far_goal.tscn
addons/sim-nav-map/tests/repro/repro_core_004_set_bounds.tscn
addons/sim-nav-map/tests/repro/repro_core_005_clearance_extension.tscn
addons/sim-nav-map/tests/repro/repro_core_006_flag_setter_propagation.tscn
addons/sim-nav-map/tests/repro/repro_core_007_static_rasterize_aabb.tscn
```

Lab repro smokes:

```text
addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_001_default_avg_step.tscn
addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_002_stress_long_frames.tscn
addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_003_max_jump.tscn
addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_004_overlap_policy.tscn
addons/sim-nav-map/examples/rts-pathfinding-lab/tests/repro/repro_lab_005_target_vs_path_target.tscn
```

Repro smokes are intentionally **not** in `tests/test_groups.json` —
they FAIL at HEAD and are not part of the regression matrix until each
issue is fixed. After a fix lands and the matching smoke turns PASS,
register it in the appropriate group.

## Severity legend

- **P0** — known correctness bug; can produce wrong path or collision violation
- **P1** — invariant gap, missing primitive, or perf gap visible in baseline metrics
- **P2** — API completeness or fragile policy; can cause future regressions
- **P3** — optimization opportunity; not urgent

## Layer legend

- **core** — addon `core/`, `model/`, `obstruction/`, `pathfinding/`
- **lab** — `examples/rts-pathfinding-lab/`
- **process** — how we work, not code

## Source legend

- `claude-audit-2026-05-07` — 5-agent comparative audit vs 0 A.D. C++ reference
- `codex-discussion` — surfaced in prior Codex discussion and now tracked here
- `both` — confirmed from both threads

## Status workflow

1. Pick an issue and flip `Status: open` → `Status: in-progress`. Claim owner.
2. For navigation / movement / obstruction issues, read the relevant 0 A.D.
   source files directly under `../references/0ad-source/`. Do not rely on
   removed AI summary notes.
3. Write the failing smoke first (each issue lists a "Repro / regression test"
   sketch). Land it red.
4. Fix. Smoke turns green.
5. Flip to `Status: resolved` and add a short "Resolution" section with
   commit hash, smoke name, checked 0 A.D. source files when relevant, and any
   baseline number it moves.
6. Move resolved files to `_resolved/` after 1-2 cycles to keep this index lean.

Allowed status values: `open`, `in-progress`, `blocked`, `resolved`.

## Adding a new issue

Copy any existing file as a template. ID format `[LAYER]-[NNN]-[short-slug].md`,
NNN monotonically increasing per layer. Update this README's index table in
the same change.

## Cross-refs

- Baseline snapshot: [`BASELINE.md`](BASELINE.md)
- 0 A.D. source map: [`../references/0ad-source-map.md`](../references/0ad-source-map.md)
- 0 A.D. source setup: [`../references/0ad-source-setup.md`](../references/0ad-source-setup.md)
- Public API: [`../public-api.md`](../public-api.md)
- Smoke matrix: [`../smoke-matrix.md`](../smoke-matrix.md)
