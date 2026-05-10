# Sim Nav Map Smoke Matrix

This file defines the stable regression gates for `sim-nav-map` issue work.
It should stay small enough to answer "what must stay green now?"

## Stable Gates

Run both groups before merging any issue fix:

```powershell
./tools/run_tests.ps1 simnav/smoke zeroadlab/smoke
```

| Group | Manifest | Responsibility |
|---|---|---|
| `simnav/smoke` | `addons/sim-nav-map/tests/test_groups.json` | Core addon contracts: public API defaults, map state, passability, terrain, obstruction, dirty lifecycle, reachability, long/short pathfinding, line validation, cache, request queue, and diagnostics exports. |
| `zeroadlab/smoke` | `addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/test_groups.json` | Plugin-local playable adapter sample: lab path planning, metadata consumption, movement-loop integration, metrics contract, and scene load. |

Baseline gate:

```powershell
./tools/run_tests.ps1 simnav/smoke zeroadlab/smoke
git -C addons diff --check
```

## Repro Tests

Issue repro scenes are intentionally separate from the stable smoke manifests.
They may fail at HEAD and should not be discovered by `./tools/run_tests.ps1`
until the matching issue is fixed.

| Kind | Location | Rule |
|---|---|---|
| Core repro | `addons/sim-nav-map/tests/repro/` | Add a focused scene for one core issue. Register it into `simnav/smoke` only after the fix turns it green. |
| Lab repro | `addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/repro/` | Add a focused scene for one lab issue. Register it into `zeroadlab/smoke` only after the fix turns it green or when it is a PASS lock-in guard. |
| Exploration | `addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/tests/exploration/` | Observation-only scripts. They always exit 0 and must not be added to smoke manifests. |

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
- reachability/canonical goal result metadata
- long-path query/result status, canonicalization metadata, raw/refined path boundary, max spacing, excluded-region isolation, and path cost/length
- jump-point cache invalidation
- vertex pathfinder
- filtered obstruction queries and line validation
- path request queue, queued request cloning, and queue diagnostics
- map dirtiness diagnostics and connectivity exports

`rtslab/smoke` covers:

- the headless lab movement/pathfinding contract
- repeated static obstacle add/remove stress while six units move between building sides
- terrain preset adapter behavior
- small/large clearance adapter behavior
- long-path result metadata adapter behavior
- short-result, movement-line, and unit-line metadata adapter behavior
- real lab scene loading

## Discovery Contract

`tools/run_tests.ps1` discovers sim-nav-map manifests from:

```text
addons/sim-nav-map/tests/test_groups.json
addons/sim-nav-map/examples/*/tests/test_groups.json
```

Paths inside each manifest are relative to that manifest directory. New core
addon smoke scenes belong under `addons/sim-nav-map/tests/` and should be added
to `simnav/smoke` after they are expected to pass. New lab behavior smoke scenes
belong under `examples/rts-pathfinding-lab/tests/` and should be added to
`rtslab/smoke` after they are expected to pass.

## Legacy RTS Fixture Boundary

`addons/logic-game-framework/example/rts-auto-battle/tests/test_groups.json`
still has `rts/pathfinding` and selected regression entries for older RTS
private pathfinder fixtures. Treat those as archived compatibility coverage for
the RTS example, not as the active `sim-nav-map` stabilization gate.

New `sim-nav-map` core coverage should not be added to `rts/pathfinding`.

## Issue Fix Checklist

- `README.md`, `docs/mental-model.md`, `docs/public-api.md`,
  and this file still agree on the same boundary.
- `simnav/smoke` and `rtslab/smoke` are discoverable by `./tools/run_tests.ps1 -List`.
- Fixed issue repros are promoted into the correct smoke manifest.
- Red repros stay in `tests/repro/` or lab `tests/repro/`, not in the stable manifest.
- Old RTS private pathfinder wording points to archived compatibility, not a future implementation path.
- `addons/sim-nav-map/docs/references/0ad-source/` remains ignored/untracked.
