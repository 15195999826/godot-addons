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
- terrain tile data
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
