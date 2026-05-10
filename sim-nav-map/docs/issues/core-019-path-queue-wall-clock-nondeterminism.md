# CORE-019: Path Queue Wall-Clock Cap Causes Simulation Nondeterminism

Status: **fixed (2026-05-11)** — `DEFAULT_SYNC_PATH_BUDGET_USEC` now defaults
to `0` (no time cap). Per-tick request count cap (`PATH_REQUEST_BUDGET_PER_TICK`
in `ZeroAdRtsLabWorld`) remains. Callers can pass an explicit `max_usec > 0`
if they accept nondeterminism in exchange for a hard frame budget.

## Symptom

Same RNG seed + same setup running `ZeroAdRtsLabWorld.step()` produced
different unit trajectories on each run. Three consecutive headless runs of
`stress_playthrough.tscn -- --swarm` (seed=42, 50 units, 600 ticks) triggered
the static-clearance violation guard at three different combinations of
`(tick, unit, position)`:

```text
run 1: swarm_3  tick=364 at (429.9, 114.9)
run 2: swarm_3  tick=361 at (433.2, 114.6)
run 3: swarm_12 tick=513 at (436.2, 112.6)
```

Initial spawn positions were identical across runs (RNG-based, deterministic).
Divergence appeared inside `world.step()` execution.

## Root cause

`SimNavPathRequestQueue.process_budget(max_requests, max_usec)` breaks out of
its processing loop on either condition:

```gdscript
if max_usec > 0 and _last_process_elapsed_usec >= max_usec:
    break
```

`ZeroAdRtsLabPathfinder.process_path_budget` was passing
`DEFAULT_SYNC_PATH_BUDGET_USEC = 3500` as `max_usec`. Per-tick processing
therefore stopped on whichever came first:
- `max_requests = 2` requests processed (the explicit per-tick cap), or
- 3.5 ms wall-clock elapsed.

The wall-clock branch is not deterministic. CPU load, OS scheduler quirks,
JIT warmup, GC pauses, and even input-method-editor activity change how many
microseconds a path computation takes. When a tick processes 1 request
instead of 2 because the second request would have crossed the 3.5 ms
boundary, the path arrival schedule for downstream units shifts by one tick,
and motion / push interaction diverges from there.

This is `sim-nav-map` deviation from 0 A.D. 0 A.D.'s
`m_MaxSameTurnMoves` (`CCmpPathfinder_Common.h`) is a pure request-count cap
with no wall-clock component, which keeps simulation deterministic. The
audit note in `docs/references/0ad-source-map.md` (Feature 7) captures this:
"`m_MaxSameTurnMoves` is the configured cap when same-turn processing should
be budgeted." Time is not part of the cap.

## Fix

`addons/sim-nav-map/examples/0ad-rts-pathfinding-lab/logic/zero_ad_rts_lab_pathfinder.gd`
const default changed from `3500` to `0`. The queue interprets `max_usec = 0`
as "no time cap"; only `max_requests` gates processing.

## Verification

- `stress_playthrough.tscn -- --swarm` ran 3 times with identical output
  (same tick, same unit, same position).
- Full `zeroadlab/smoke` (6 scenes) PASS.
- Full `simnav/smoke` (TBD scenes) PASS.

## Why the time cap existed

Likely defensive: avoid frame spikes if a single path computation is
unusually expensive. With the count cap (`PATH_REQUEST_BUDGET_PER_TICK = 2`)
this is over-protection — at most 2 path computations per tick limits cost
already, and a single pathological compute is itself a separate bug worth
investigating rather than masking with a wall-clock guillotine.

If a future caller needs a hard wall-clock guarantee (real-time UI thread,
game render frame), it can still pass an explicit `max_usec` to
`process_path_budget()` and accept the determinism cost knowingly.

## Downstream effects

- `stress_playthrough.tscn -- --swarm` is now deterministic, which makes
  CORE-020 (`motion brushes static clearance ring under push pressure`)
  reproducible from a single seed.
- Multi-tick smoke / repro scenes are no longer at risk of CI flakes from
  slow CI runners triggering the time cap differently than dev machines.
- Future replay / bit-identical record-and-replay features become feasible
  on the lab adapter (the long-standing `fixed-point determinism` deferral
  is unaffected — float math remains, but float math is itself deterministic
  given identical operation order, which is now restored).
