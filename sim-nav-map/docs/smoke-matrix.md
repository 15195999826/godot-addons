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
- dirty navcell lifecycle
- spatial index queries
- path goal geometry
- map tracing
- obstruction manager behavior
- hierarchical reachability and dirty recompute
- jump-point cache invalidation
- long pathfinder
- vertex pathfinder
- path request queue
- queued request cloning

`rtslab/smoke` covers:

- the headless lab movement/pathfinding contract
- the lab terrain preset adapter contract
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
