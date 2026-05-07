# Sim Nav Map Smoke Matrix

This matrix defines the stable regression entry points for `sim-nav-map`
stabilization work.

## Entry Points

| Group | Manifest | Responsibility |
|---|---|---|
| `simnav/smoke` | `addons/sim-nav-map/tests/test_groups.json` | Core addon contracts: map state, passability, terrain, obstruction, dirty lifecycle, reachability, long/short pathfinding, cache, and request queue. |
| `rtslab/smoke` | `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/test_groups.json` | Plugin-local playable adapter sample: lab path planning, movement-loop integration, metrics contract, and scene load. |

Run both with:

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
```

## V1 Baseline Guard Contract

Feature 0 is the post-`sim-nav-map-v1.0.0` regression guard. It does not add a
navigation capability; it keeps the public API docs, smoke groups, and example
boundary aligned so later roadmap work can be compared against the V1 baseline.

Baseline gate:

```powershell
./tools/run_tests.ps1 simnav/smoke rtslab/smoke
git -C addons diff --check
```

`simnav/smoke` is the core addon contract. It verifies reusable navigation
primitives: map state, passability, terrain data access and derived terrain
passability, obstruction projection, dirty lifecycle, reachability, long/short
query behavior, cache invalidation, and request queue behavior.

`rtslab/smoke` is the adapter/playable regression contract. It verifies that
`examples/rts-pathfinding-lab` can consume the core addon through its adapter and
that the real lab scene still loads. Lab movement, HUD, formation offsets,
toggle UX, push behavior, and replan cadence remain application policy and do
not become `sim-nav-map` public API.

Feature 1 may start only after both baseline groups pass, this document and
`public-api.md` still describe the same boundary, and
`docs/references/0ad-source/` remains untracked. Feature-specific smoke added by
later roadmap items should be registered into `simnav/smoke` for core addon
contracts or `rtslab/smoke` for lab adapter/playable contracts.

## Feature 1 Terrain Passability Contract

Feature 1 is covered by:

- `addons/sim-nav-map/tests/smoke_sim_nav_terrain_tile_map.tscn` in
  `simnav/smoke`: verifies terrain tile projection, terrain mask -> navcell
  passability derivation, dirty marking on terrain edit, class-specific terrain
  masks, and rebuild stability.
- `addons/sim-nav-map/tests/smoke_sim_nav_public_api_contract.tscn` in
  `simnav/smoke`: verifies the public map-level terrain edit and rebuild entry
  points.
- `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/smoke/smoke_rts_pathfinding_lab_terrain_adapter.tscn`
  in `rtslab/smoke`: verifies the lab adapter can project a terrain preset into
  `SimNavMap` and query two passability classes without adding ship gameplay or
  lab movement policy to core.

Feature 2 may start when these Feature 1 smoke contracts, the default lab
playable regression, `git -C addons diff --check`, and the
`docs/references/0ad-source/` untracked check are all green.

## Feature 2 Clearance Rasterization Contract

Feature 2 is covered by:

- `addons/sim-nav-map/tests/smoke_sim_nav_clearance_rasterization.tscn` in
  `simnav/smoke`: verifies class-specific `clearance` expansion for terrain and
  static obstruction rasterization, different masks for small/large classes on
  the same terrain/obstruction, dirty marking when clearance-expanded terrain is
  cleared, and long-path behavior through a one-navcell gap.
- `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/smoke/smoke_rts_pathfinding_lab_clearance_adapter.tscn`
  in `rtslab/smoke`: verifies the lab adapter can build a terrain context with
  small/large passability classes and consume the resulting reachability/path
  difference without promoting unit type, movement, selection, command, or
  formation policy into core.

Feature 3 may start when these Feature 2 smoke contracts, the existing terrain
and lab playable regressions, `git -C addons diff --check`, and the
`docs/references/0ad-source/` untracked check are all green. Feature 3 should
start from dirty edit/cache lifecycle only; it should not introduce reachability
result DTOs, long path result contracts, short filters, line validation, queue
expansion, scale diagnostics, or lab gameplay policy in the same step.

## Feature 3 Dirty Lifecycle Contract

Feature 3 is covered by:

- `addons/sim-nav-map/tests/smoke_sim_nav_dirty_lifecycle.tscn` in
  `simnav/smoke`: verifies direct dirty marking, static obstruction dirty
  rasterization, terrain edit dirty lifecycle, hierarchical dirty recompute,
  long-path jump-point cache invalidation, and default dirty cleanup through
  `SimNavPathfinderFacade.recompute_dirty()`.
- Existing hierarchical/cache smoke in `simnav/smoke`: verifies dirty chunk
  replacement and jump-point cache invalidation behavior remain stable.

Feature 4 may start when Feature 3 smoke is green. Feature 3 does not add long
path result status, path post-processing, excluded regions, short path filters,
line validation, queue expansion, scale diagnostics, ship gameplay, formation,
HUD policy, or game-specific movement policy.

## Feature 4 Reachability Contract

Feature 4 is covered by:

- `addons/sim-nav-map/tests/smoke_sim_nav_reachability_query.tscn` in
  `simnav/smoke`: verifies explicit reachability result metadata, `POINT`,
  `CIRCLE`, `SQUARE`, inverted goal canonicalization, passability class/mask
  echo, and dirty recompute changing the canonical target.
- `addons/sim-nav-map/tests/smoke_sim_nav_long_pathfinder.tscn` in
  `simnav/smoke`: verifies the facade still canonicalizes unreachable long-path
  point goals before search.
- `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/smoke/smoke_rts_pathfinding_lab.tscn`
  and adapter smoke in `rtslab/smoke`: verify the lab consumes canonical goals
  and reachability metadata without promoting movement, selection, command,
  formation, HUD, or arrival policy into core.

Feature 5's scope is only the long-path query/result contract: query status,
path metadata, raw vs refined waypoints, optional excluded regions, and
post-processing primitives. Do not fold short filters, line validation, queue
expansion, scale diagnostics, or game-specific movement policy into Feature 5.

## Feature 5 Long-Path Query/Result Contract

Feature 5 is covered by:

- `addons/sim-nav-map/tests/smoke_sim_nav_long_pathfinder.tscn` in
  `simnav/smoke`: verifies explicit long-path result statuses, canonicalization
  metadata, start recovery, raw navcell path vs refined waypoint path boundaries,
  max waypoint spacing, path cost/length, and request-scoped excluded-region
  isolation.
- `addons/sim-nav-map/tests/smoke_sim_nav_public_api_contract.tscn` in
  `simnav/smoke`: verifies `SimNavLongPathQuery` clone/default behavior and
  `SimNavLongPathResult` query metadata snapshots.
- `addons/sim-nav-map/tests/smoke_sim_nav_path_request_queue.tscn` in
  `simnav/smoke`: verifies queue cloning for long-path query preferences and
  `take_long_path_result()` metadata retrieval while preserving path-only
  compatibility.
- `addons/sim-nav-map/examples/rts-pathfinding-lab/tests/smoke/smoke_rts_pathfinding_lab_long_path_result_adapter.tscn`
  in `rtslab/smoke`: verifies the lab adapter consumes and exposes long-path
  result metadata through `last_report` without moving core policy into lab
  movement code.

Feature 5 does not add short-path filters, movement-line validation,
unit-line validation, request queue budget expansion, worker scaling,
diagnostics, formation, push/yield, stuck/deadlock, retry cadence, or gameplay
movement policy. `rts-pathfinding-lab` remains an adapter consumer and playable
regression surface.

## Discovery Contract

`tools/run_tests.ps1` discovers sim-nav-map manifests from:

```text
addons/sim-nav-map/tests/test_groups.json
addons/sim-nav-map/examples/*/tests/test_groups.json
```

Paths inside each manifest are relative to that manifest directory. New core
addon smoke scenes belong under `addons/sim-nav-map/tests/` and should be added
to `simnav/smoke`. New lab behavior smoke scenes belong under
`examples/rts-pathfinding-lab/tests/` and should be added to `rtslab/smoke`.

## Current Coverage

`simnav/smoke` covers:

- public API constructor/default contracts
- passability class registration
- terrain tile data and terrain-derived navcell passability
- class-aware clearance rasterization for terrain and static obstructions
- dirty navcell lifecycle
- spatial index queries
- path goal geometry
- map tracing
- obstruction manager behavior
- hierarchical reachability and dirty recompute
- explicit reachability/canonical goal result metadata
- explicit long-path query/result contract: status, canonicalization metadata,
  raw/refined path boundary, max spacing, excluded-region isolation, and
  path cost/length
- jump-point cache invalidation
- long pathfinder
- vertex pathfinder
- path request queue
- queued request cloning

`rtslab/smoke` covers:

- the headless lab movement/pathfinding contract
- repeated static obstacle add/remove stress while six units move between
  building sides
- the lab terrain preset adapter contract
- the lab small/large clearance adapter contract
- the lab long-path result metadata adapter contract
- the real lab scene loading path

## Legacy RTS Fixture Boundary

`addons/logic-game-framework/example/rts-auto-battle/tests/test_groups.json`
still has `rts/pathfinding` and selected regression entries for older RTS
private pathfinder fixtures. Treat those as archived compatibility coverage for
the RTS example, not as the active `sim-nav-map` stabilization gate.

New `sim-nav-map` core coverage should not be added to `rts/pathfinding`.

## Final Audit Checklist

- `README.md`, `docs/mental-model.md`, `docs/public-api.md`,
  `docs/feature-roadmap.md`, and this file agree on the same boundary.
- `simnav/smoke` and `rtslab/smoke` are discoverable by `./tools/run_tests.ps1 -List`.
- `simnav/smoke` includes `smoke_sim_nav_public_api_contract.tscn` for the
  current public entry-point boundary.
- Old RTS private pathfinder wording points to archived compatibility, not a
  future implementation path.
- `addons/sim-nav-map/docs/references/0ad-source/` remains untracked.
